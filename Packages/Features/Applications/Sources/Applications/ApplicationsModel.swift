import Foundation
import AppKit
import Observation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
import DeletionUI

/// State behind the Applications section (CLAUDE.md §6.6).
@Observable
@MainActor
public final class ApplicationsModel {
    public enum Sort: Sendable, CaseIterable { case name, size, lastUsed }

    public enum LoadState: Sendable, Equatable { case idle, loading, loaded }

    public private(set) var apps: [InstalledApp] = []
    public private(set) var loadState: LoadState = .idle
    public var searchText = ""
    public var sort: Sort = .name
    /// Show only apps not opened for this many days. Nil shows all (CLAUDE.md §6.6, unused apps).
    public var unusedForDays: Int?
    public var includeApple = false

    /// The application whose removal is being reviewed.
    public private(set) var plan: UninstallPlan?
    public var selection: Set<UUID> = []
    public private(set) var isLoadingLeftovers = false

    /// Orphaned folders from applications that are gone.
    public private(set) var orphans: [ScanItem] = []
    public private(set) var isScanningOrphans = false
    public var orphanSelection: Set<UUID> = []

    public let canRecordHistory: Bool

    private let approval = ApprovalFlow()
    private let history: HistoryStore?
    private let catalogue: AppCatalogue
    private let leftoverFinder: LeftoverFinder
    private let inspector: any RunningApplicationInspecting
    private let clock: @Sendable () -> Date

    public var pendingPlan: DeletionPlan? { approval.pendingPlan }
    public var report: DeletionReport? { approval.report }
    public var isDeleting: Bool { approval.isDeleting }

    public init(
        catalogue: AppCatalogue = AppCatalogue(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inspector: any RunningApplicationInspecting = RunningApplicationInspector(),
        history: HistoryStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.catalogue = catalogue
        self.leftoverFinder = LeftoverFinder(home: home)
        self.inspector = inspector
        self.history = history
        self.canRecordHistory = history != nil
        self.clock = clock
    }

    // MARK: Loading

    public func load() async {
        guard loadState != .loading else { return }
        loadState = .loading
        let catalogue = catalogue
        // The list appears at once, without sizes: measuring every bundle is what takes the time.
        apps = await Task.detached { (try? catalogue.installedApps(measureSizes: false)) ?? [] }.value
        loadState = .loaded

        // Sizes fill in as they are measured, a few apps at a time.
        let pending = apps
        await withTaskGroup(of: (String, ByteCount).self) { group in
            var next = 0
            func launch() {
                guard next < pending.count else { return }
                let app = pending[next]
                next += 1
                group.addTask { (app.id, catalogue.size(of: app.url)) }
            }
            for _ in 0..<4 { launch() }
            for await (id, size) in group {
                if let index = apps.firstIndex(where: { $0.id == id }) { apps[index] = apps[index].withSize(size) }
                launch()
            }
        }
    }

    // MARK: List

    /// The list as the user sees it: filtered and sorted.
    public var visibleApps: [InstalledApp] {
        var list = apps
        if !includeApple { list = list.filter { !$0.isApple } }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if let days = unusedForDays {
            let cutoff = clock().addingTimeInterval(-Double(days) * 86_400)
            // An app with no recorded use is not called unused: not knowing is not evidence.
            list = list.filter { ($0.lastUsed ?? .distantFuture) < cutoff }
        }
        switch sort {
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: list.sort { $0.size > $1.size }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantFuture) < ($1.lastUsed ?? .distantFuture) }
        }
        return list
    }

    public func isRunning(_ app: InstalledApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return inspector.runningBundleIdentifiers().contains { $0 == id || $0.hasPrefix(id + ".") }
    }

    /// Asks a running app to quit, the way the user would from its menu (§6.6). Never forced.
    public func requestQuit(_ app: InstalledApp) {
        guard let id = app.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }

    // MARK: Uninstall review

    /// Opens the review for one app: finds what it left behind, preselects the safe part.
    public func review(_ app: InstalledApp) async {
        approval.reset()
        plan = nil
        selection = []
        isLoadingLeftovers = true
        let others = Set(apps.compactMap(\.bundleID)).subtracting([app.bundleID ?? ""])
        let finder = leftoverFinder
        let leftovers: [ScanItem] = await Task.detached { (try? finder.leftovers(of: app, otherBundleIDs: others)) ?? [] }.value
        let built = UninstallPlan(app: app, leftovers: leftovers, running: inspector.runningBundleIdentifiers())
        plan = built
        selection = Set(built.preselected.map(\.id))
        isLoadingLeftovers = false
        useService(for: built.all)
    }

    /// Reset: keep the application, clear its settings and caches. Unticks the app itself and
    /// ticks only the sure leftovers.
    public func resetOnly() {
        guard let plan else { return }
        selection = Set(plan.leftovers.filter { $0.isActionable && $0.confidence > .low }.map(\.id))
    }

    public func closeReview() {
        plan = nil
        selection = []
        approval.reset()
    }

    public func toggle(_ item: ScanItem) {
        guard item.isActionable else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    public var selectedItems: [ScanItem] { (plan?.all ?? []).filter { selection.contains($0.id) } }
    public var selectedSize: ByteCount { selectedItems.totalSize() }

    /// Exactly the app and the leftovers found are the targets: nothing beside them can be removed.
    private func useService(for items: [ScanItem]) {
        approval.use(
            DeletionService(
                guards: [LeftoverFinder.scannerID: PathGuard(allowedRoots: [], allowedTargets: items.map(\.url))],
                history: history
            )
        )
    }

    // MARK: Orphans

    public func scanOrphans() async {
        isScanningOrphans = true
        orphanSelection = []
        approval.reset()
        let finder = OrphanFinder(home: leftoverFinder.home)
        let installed = apps
        let running = inspector.runningBundleIdentifiers()
        orphans = await Task.detached { (try? finder.orphans(installed: installed, running: running)) ?? [] }.value
        isScanningOrphans = false
        useService(for: orphans)
    }

    public func toggleOrphan(_ item: ScanItem) {
        guard item.isActionable else { return }
        if orphanSelection.contains(item.id) { orphanSelection.remove(item.id) } else { orphanSelection.insert(item.id) }
    }

    public var selectedOrphans: [ScanItem] { orphans.filter { orphanSelection.contains($0.id) } }

    // MARK: Extensions

    public private(set) var extensions: [ScanItem] = []
    public var extensionSelection: Set<UUID> = []

    public func scanExtensions() async {
        extensionSelection = []
        let finder = ExtensionFinder(home: leftoverFinder.home)
        extensions = await Task.detached { (try? finder.extensions()) ?? [] }.value
        useService(for: extensions)
    }

    public func toggleExtension(_ item: ScanItem) {
        guard item.isActionable else { return }
        if extensionSelection.contains(item.id) { extensionSelection.remove(item.id) } else { extensionSelection.insert(item.id) }
    }

    public var selectedExtensions: [ScanItem] { extensions.filter { extensionSelection.contains($0.id) } }
    public func prepareExtensionRemoval() { approval.prepare(selectedExtensions) }

    // MARK: Updates

    /// Points the user at the right place. Burnish does not update anything itself and makes no
    /// network request (CLAUDE.md §6.6): an App Store app goes to the Store, any other app is
    /// opened so it can run its own updater.
    public func openUpdates(for app: InstalledApp) {
        switch app.updateSource {
        case .appStore:
            if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
        case .sparkle, .unknown:
            NSWorkspace.shared.open(app.url)
        }
    }

    // MARK: Approval

    public func prepareUninstall() { approval.prepare(selectedItems) }
    public func prepareOrphanRemoval() { approval.prepare(selectedOrphans) }
    public func dismissConfirmation() { approval.dismiss() }

    public func confirm(_ plan: DeletionPlan) {
        approval.confirm(plan) { [weak self] in
            guard let self else { return }
            self.selection = []
            self.orphanSelection = []
            self.extensionSelection = []
        }
    }

    /// After a finished removal: forget the review and reload the list.
    public func finish() async {
        closeReview()
        orphans = []
        await load()
    }
}
