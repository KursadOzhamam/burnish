import Foundation
import AppKit
import Observation
import CoreKit
import CoreKitMac
import SafetyKitMac

/// State behind the Protection section (CLAUDE.md §6.4).
@Observable
@MainActor
public final class ProtectionModel {
    public enum Phase: Sendable, Equatable {
        case idle
        case scanning(examined: Int, path: String)
        case finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var findings: [Finding] = []
    public private(set) var quarantined: [QuarantineStore.Record] = []
    public private(set) var status: AppleDefense.SystemStatus?
    public private(set) var permissions: [TCCReader.Entry] = []
    public private(set) var permissionsNeedFullDiskAccess = false
    public private(set) var lastScan: Date?
    public private(set) var message: Message?

    public enum Message: Sendable, Equatable {
        case quarantined(String)
        case restored(String)
        case refused(String)
        case failed(String)
    }

    private var task: Task<Void, Never>?
    private let roots: [URL]
    private let blocklist: Blocklist
    private let store: QuarantineStore
    private let allowListURL: URL
    private var allowList: AllowList
    private let persistence: PersistenceAnalyzer
    private let defense: AppleDefense
    private let tcc: TCCReader
    private let clock: @Sendable () -> Date

    public init(
        roots: [URL] = ProtectionModel.defaultRoots(),
        blocklist: Blocklist = .empty,
        supportDirectory: URL,
        persistence: PersistenceAnalyzer = PersistenceAnalyzer(),
        defense: AppleDefense = AppleDefense(),
        tcc: TCCReader = TCCReader(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.roots = roots
        self.blocklist = blocklist
        self.store = QuarantineStore(directory: supportDirectory.appendingPathComponent("Quarantine"))
        self.allowListURL = supportDirectory.appendingPathComponent("allowlist.json")
        self.allowList = AllowList.load(from: allowListURL)
        self.persistence = persistence
        self.defense = defense
        self.tcc = tcc
        self.clock = clock
        quarantined = store.records()
    }

    /// Where malware tends to arrive: downloads, the desktop, applications.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop"),
         URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    public var blocklistVersion: Int { blocklist.version }
    public var blocklistCount: Int { blocklist.count }

    // MARK: Scan

    public func scan() {
        cancel()
        message = nil
        phase = .scanning(examined: 0, path: "")
        let scanner = ProtectionScanner(roots: roots, blocklist: blocklist)
        let analyzer = persistence
        let allow = allowList
        task = Task { [weak self] in
            let found = (try? await scanner.scan { examined, path in
                Task { @MainActor in self?.phase = .scanning(examined: examined, path: path) }
            }) ?? []
            guard !Task.isCancelled else { return }
            let all = allow.filtering(found + analyzer.findings()).sorted { $0.severity > $1.severity }
            await MainActor.run {
                self?.findings = all
                self?.lastScan = self?.clock()
                self?.phase = .finished
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if case .scanning = phase { phase = .idle }
    }

    // MARK: Actions on a finding

    /// Moves the item to quarantine. Protected locations are refused by the safety layer.
    public func quarantine(_ finding: Finding) {
        let guardrail = PathGuard(allowedRoots: [], allowedTargets: [finding.url])
        guard guardrail.isAllowed(finding.url) else {
            message = .refused(finding.url.lastPathComponent)
            return
        }
        do {
            try store.quarantine(finding.url, reason: String(describing: finding.reason), now: clock())
            findings.removeAll { $0.url == finding.url }
            quarantined = store.records()
            message = .quarantined(finding.url.lastPathComponent)
        } catch {
            message = .failed(error.localizedDescription)
        }
    }

    /// "This is safe, do not ask again" (§6.4): remembered across scans, and removed from the list.
    public func allow(_ finding: Finding) {
        allowList.allow(finding)
        try? allowList.save(to: allowListURL)
        findings.removeAll { $0.id == finding.id }
    }

    public func restore(_ record: QuarantineStore.Record) {
        do {
            try store.restore(record)
            quarantined = store.records()
            message = .restored(record.storedName)
        } catch {
            message = .failed("\(error)")
        }
    }

    // MARK: System state

    public func refreshStatus() async {
        status = await defense.systemStatus()
        do {
            permissions = try tcc.entries().filter(\.isAllowed)
            permissionsNeedFullDiskAccess = false
        } catch {
            permissions = []
            permissionsNeedFullDiskAccess = true
        }
    }

    public func openSettings(for service: TCCReader.Entry.Service) {
        if let url = TCCReader.settingsURL(for: service) { NSWorkspace.shared.open(url) }
    }

    /// Worst thing found, for the summary.
    public var worstSeverity: Finding.Severity? { findings.map(\.severity).max() }
}
