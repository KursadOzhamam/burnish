import Foundation
import CoreKit
import CoreKitMac

/// The on-demand scan (CLAUDE.md §6.4). Not real-time protection: it looks when the user asks.
///
/// For each file in the chosen folders it asks three questions, cheapest first:
/// - is its hash on the signed blocklist (exact match, a "threat");
/// - does a rule describe it (a "suspicious" pattern);
/// - for an application, does macOS consider it validly signed, and did it come from the
///   internet without a signature (information only).
/// Reports only. Nothing is changed or removed by scanning.
public struct ProtectionScanner: Sendable {
    public let roots: [URL]
    public let blocklist: Blocklist
    public let rules: any RuleMatching
    /// Files larger than this are not hashed: malware droppers and scripts are small, and
    /// hashing every video on the disk would cost minutes for nothing.
    public let maxHashSize: Int

    static let interestingExtensions: Set<String> = [
        "app", "dmg", "pkg", "sh", "command", "scpt", "js", "py", "pl", "rb", "jar", "exe", "dylib", "so", "plist", "zip"
    ]

    public init(roots: [URL], blocklist: Blocklist, rules: any RuleMatching = RuleEngine(rules: RuleEngine.builtIn), maxHashSize: Int = 200_000_000) {
        self.roots = roots
        self.blocklist = blocklist
        self.rules = rules
        self.maxHashSize = maxHashSize
    }

    /// - Parameter progress: called with the count of files examined so far and the current path.
    public func scan(progress: @Sendable (Int, String) -> Void = { _, _ in }) async throws -> [Finding] {
        try inspect(progress: progress)
    }

    // Synchronous: DirectoryEnumerator cannot be iterated from async code. Cancellation is
    // checked per file.
    private func inspect(progress: @Sendable (Int, String) -> Void) throws -> [Finding] {
        var findings: [Finding] = []
        var examined = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .isExecutableKey]

        for root in roots {
            guard let enumerator = FileManager().enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isSymbolicLink == true { continue }

                if values.isPackage == true {
                    findings += inspectBundle(url)
                    examined += 1
                    if examined % 20 == 0 { progress(examined, url.path) }
                    continue
                }
                guard values.isRegularFile == true else { continue }
                let size = values.fileSize ?? 0
                guard size > 0 else { continue }
                let looksRelevant = Self.interestingExtensions.contains(url.pathExtension.lowercased()) || values.isExecutable == true
                guard looksRelevant else { continue }

                examined += 1
                if examined % 20 == 0 { progress(examined, url.path) }
                findings += inspectFile(url, size: size)
            }
        }
        progress(examined, "")
        return findings.sorted { $0.severity > $1.severity }
    }

    private func inspectFile(_ url: URL, size: Int) -> [Finding] {
        var result: [Finding] = []
        if size <= maxHashSize, let hash = try? FileHasher.sha256(of: url), let name = blocklist.name(forHash: hash) {
            result.append(Finding(url: url, severity: .threat, reason: .knownBadHash(name: name)))
        }
        for rule in rules.matches(for: url, size: size) {
            // The EICAR test file is a "threat" so the user can see the scan works; ordinary rules
            // are "suspicious": a pattern is not proof.
            let severity: Finding.Severity = rule.id == "burnish.eicar" ? .threat : .suspicious
            result.append(Finding(url: url, severity: severity, reason: .ruleMatch(rule: rule.id, description: rule.description)))
        }
        return result
    }

    private func inspectBundle(_ url: URL) -> [Finding] {
        guard url.pathExtension == "app" else { return [] }
        var result: [Finding] = []
        let state = AppleDefense.signatureState(of: url)
        switch state {
        case .invalid:
            // Information, not a threat: on a real Mac several ordinary apps (Opera, DaVinci Resolve,
            // anything whose languages were trimmed) fail the strict check without being malicious.
            // Calling them suspicious would be the false-alarm marketing §10.3 rules out.
            result.append(Finding(url: url, severity: .info, reason: .invalidSignature))
        case .unsigned where AppleDefense.isQuarantined(url):
            result.append(Finding(url: url, severity: .info, reason: .unsignedFromInternet))
        case .unsigned, .valid:
            break
        }
        // The main executable is hashed like any other file.
        let macOS = url.appendingPathComponent("Contents/MacOS")
        if let executables = try? FileManager().contentsOfDirectory(at: macOS, includingPropertiesForKeys: [.fileSizeKey]) {
            for executable in executables {
                let size = (try? executable.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { result += inspectFile(executable, size: size).filter { $0.severity == .threat } }
            }
        }
        return result
    }
}
