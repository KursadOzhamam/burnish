import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
import HelperProtocol

/// The privileged helper (CLAUDE.md §7, §10.8).
///
/// - Only a client signed by *our* team, with our app's identifier, may connect. The requirement
///   is built from this helper's own team identifier, and if it has none (an ad-hoc build) every
///   connection is refused: the helper fails closed.
/// - It never runs a string it was given. `runCommand` looks the name up in a closed enum.
/// - It never trusts a path. `removeSystemItems` applies `HelperPolicy` itself (§4.10) and then
///   removes through `DeletionService`, the same single gate the app uses.
final class HelperService: NSObject, NSXPCListenerDelegate, HelperXPC {
    private let requirement: String?
    private let policy = HelperPolicy()

    override init() {
        requirement = CodeSigning.ownTeamID().flatMap { HelperRequirement.isValid(teamID: $0) ? HelperRequirement.forMainApp(teamID: $0) : nil }
        super.init()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: HelperXPC

    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperIdentity.protocolVersion)
    }

    func runCommand(_ rawValue: String, reply: @escaping (Int32, String) -> Void) {
        guard let command = HelperPolicy.command(named: rawValue) else {
            reply(-1, "unknown command")
            return
        }
        let fixed = command.command
        // The executable and arguments come from the closed `HelperCommand` enum, never from the
        // caller's text (decision 2026-10-13).
        // swiftlint:disable:next no_shell_in_helper
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fixed.executable)
        process.arguments = fixed.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            reply(-1, "could not start: \(error.localizedDescription)")
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        reply(process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func removeSystemItems(_ paths: [String], reply: @escaping ([String]) -> Void) {
        var failures: [String] = []
        var accepted: [ScanItem] = []
        let scanner = ScannerID("helper.system")

        for path in paths {
            do {
                let url = try policy.validate(path)
                accepted.append(ScanItem(scanner: scanner, url: url, size: .zero, confidence: .low))
            } catch {
                failures.append("\(path): refused (\(error))")
            }
        }
        guard !accepted.isEmpty else { reply(failures); return }

        let roots = HelperPolicy.removableRoots.map { URL(fileURLWithPath: $0) }
        let service = DeletionService(guards: [scanner: PathGuard(allowedRoots: roots, home: URL(fileURLWithPath: "/var/root"))], history: nil)
        let plan = service.plan(for: accepted, mode: .permanent)
        do {
            // The app showed the irreversible confirmation before asking; the helper still checked
            // every path above on its own.
            let report = try service.execute(plan, confirmedIrreversible: true)
            for outcome in report.failures { failures.append("\(outcome.item.url.path): failed") }
        } catch {
            failures.append("removal failed: \(error)")
        }
        reply(failures)
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.current.run()
