import Testing
import Foundation
@testable import HelperProtocol

@Suite("Helper commands")
struct HelperCommandTests {
    @Test("Every step of every command is an absolute executable with plain arguments")
    func fixed() {
        for command in HelperCommand.allCases {
            #expect(!command.steps.isEmpty)
            for step in command.steps {
                #expect(step.executable.hasPrefix("/"))
                #expect(!step.arguments.contains { $0.contains(";") || $0.contains("$") || $0.contains("`") || $0.contains("|") })
            }
        }
    }

    @Test("Flushing DNS also makes mDNSResponder drop its own cache")
    func dnsSteps() {
        let steps = HelperCommand.flushDNS.steps
        #expect(steps.map(\.executable) == ["/usr/bin/dscacheutil", "/usr/bin/killall"])
        #expect(steps[1].arguments == ["-HUP", "mDNSResponder"])
    }

    @Test("Thinning local snapshots names no snapshot: macOS chooses what to reclaim")
    func snapshotThinning() {
        let step = HelperCommand.thinLocalSnapshots.command
        #expect(step.executable == "/usr/bin/tmutil")
        #expect(step.arguments == ["thinlocalsnapshots", "/", "999999999999", "4"])
    }

    @Test("An unknown name is not a command")
    func unknown() {
        #expect(HelperPolicy.command(named: "rm -rf /") == nil)
        #expect(HelperPolicy.command(named: "") == nil)
        #expect(HelperPolicy.command(named: "flushDNS") == .flushDNS)
    }

    @Test("There is no command that takes a free-form argument")
    func noFreeText() {
        // The set is closed: the raw values are exactly the documented names.
        #expect(Set(HelperCommand.allCases.map(\.rawValue)) == [
            "flushDNS", "reindexSpotlight", "verifyDisk", "purgeMemory", "runPeriodicScripts", "thinLocalSnapshots"
        ])
    }
}

@Suite("Helper policy")
struct HelperPolicyTests {
    private let policy = HelperPolicy()

    @Test("A relative path is refused")
    func relative() {
        #expect(throws: HelperPolicy.Refusal.notAbsolute) { try policy.validate("Library/Caches/x") }
    }

    @Test("The allowed folders themselves are refused")
    func roots() {
        #expect(throws: HelperPolicy.Refusal.isRoot) { try policy.validate("/Library/Caches") }
        #expect(throws: HelperPolicy.Refusal.isRoot) { try policy.validate("/Library/Logs") }
    }

    @Test("Paths outside the allowed folders are refused")
    func outside() {
        let paths = [
            "/System/Library/Caches/x", "/usr/local/bin/x", "/Applications/Safari.app",
            "/Library/Application Support/x", "/etc/hosts", "/Users/someone/Documents/x"
        ]
        for path in paths {
            #expect(throws: HelperPolicy.Refusal.outsideAllowedRoots, "\(path)") { try policy.validate(path) }
        }
    }

    @Test("A lookalike folder name is refused")
    func lookalike() {
        #expect(throws: HelperPolicy.Refusal.outsideAllowedRoots) { try policy.validate("/Library/Caches-evil/x") }
    }

    @Test("Dot-dot cannot climb out of an allowed folder")
    func traversal() {
        #expect(throws: HelperPolicy.Refusal.outsideAllowedRoots) { try policy.validate("/Library/Caches/../../etc/passwd") }
    }

    @Test("A symlink inside an allowed folder is judged by where it points")
    func symlinkEscape() throws {
        // Needs write access to /Library/Caches, so it runs only when that is possible. The check
        // itself is path-based and is covered above; this proves the resolution step.
        let probe = URL(fileURLWithPath: "/Library/Caches/burnish-policy-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createSymbolicLink(at: probe, withDestinationURL: URL(fileURLWithPath: "/etc"))
        } catch {
            return  // not permitted here, which is the normal case for a non-root test run
        }
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: probe)
        }
        #expect(throws: HelperPolicy.Refusal.outsideAllowedRoots) { try policy.validate(probe.path) }
    }

    @Test("A normal item inside an allowed folder is accepted")
    func accepted() throws {
        let url = try policy.validate("/Library/Caches/com.example.cache/item.bin")
        #expect(url.path.hasPrefix("/Library/Caches/"))
    }
}

@Suite("Helper requirement")
struct HelperRequirementTests {
    @Test("The requirement names the app identifier and the team")
    func requirement() {
        let text = HelperRequirement.forMainApp(teamID: "ABCDE12345")
        #expect(text.contains("identifier \"com.burnish.app\""))
        #expect(text.contains("subject.OU] = \"ABCDE12345\""))
        #expect(text.hasPrefix("anchor apple generic"))
    }

    @Test("Only a well-formed team identifier is accepted")
    func teamValidation() {
        #expect(HelperRequirement.isValid(teamID: "9DM69754D2"))
        for bad in ["", "short", "9dm69754d2", "9DM69754D2X", "9DM6975 4D2", "9DM69754D\"", "9DM69754D\\"] {
            #expect(!HelperRequirement.isValid(teamID: bad), "\(bad)")
        }
    }
}

@Suite("Helper requirement for the app side")
struct HelperAppSideRequirementTests {
    @Test("The app pins the helper by its identifier and our team")
    func pinsHelper() {
        let text = HelperRequirement.forHelper(teamID: "ABCDE12345")
        #expect(text.contains("identifier \"com.burnish.app.helper\""))
        #expect(text.contains("subject.OU] = \"ABCDE12345\""))
    }
}
