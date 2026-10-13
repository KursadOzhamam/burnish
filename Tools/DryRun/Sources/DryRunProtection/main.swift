import Foundation
import Protection

// Read-only: runs the protection checks and prints what they find. Changes nothing.
let home = FileManager.default.homeDirectoryForCurrentUser
let roots = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop"), URL(fileURLWithPath: "/Applications")]
let started = Date()
let findings = try await ProtectionScanner(roots: roots, blocklist: .empty).scan()
print("Scan: \(findings.count) findings in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
for finding in findings.prefix(12) {
    print("  [\(finding.severity)] \(finding.url.path.replacingOccurrences(of: home.path, with: "~")): \(finding.reason)")
}

let persistence = PersistenceAnalyzer().findings()
print("\nPersistence: \(persistence.count)")
for finding in persistence { print("  [\(finding.severity)] \(finding.url.path): \(finding.reason)") }

let status = await AppleDefense().systemStatus()
print("\nGatekeeper: \(status.gatekeeperEnabled.map(String.init(describing:)) ?? "unknown"), SIP: \(status.sipEnabled.map(String.init(describing:)) ?? "unknown"), XProtect: \(status.xprotectVersion ?? "unknown")")

do {
    let entries = try TCCReader().entries()
    let allowed = entries.filter(\.isAllowed)
    print("\nPrivacy permissions: \(allowed.count) allowed entries")
    for service in [TCCReader.Entry.Service.camera, .microphone, .screenRecording, .fullDiskAccess] {
        print("  \(service): \(allowed.filter { $0.service == service }.map(\.client).sorted().prefix(6).joined(separator: ", "))")
    }
} catch {
    print("\nPrivacy permissions: not readable (\(error)), needs Full Disk Access for this process")
}
print("Nothing was changed.")
