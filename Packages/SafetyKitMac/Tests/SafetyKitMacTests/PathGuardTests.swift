import Testing
import Foundation
import ScanEngine
import SafetyKit
@testable import SafetyKitMac

/// CLAUDE.md §4.9: a "cannot be deleted" test for every protected path.
///
/// These tests never touch the real filesystem — they operate on a synthetic home directory, so
/// a bug here cannot damage the machine running them (§9).
@Suite("Protected paths")
struct ProtectedPathTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    /// A guard permissive enough that only the protected list can refuse a path.
    private func wideOpenGuard() -> PathGuard {
        PathGuard(allowedRoots: [URL(fileURLWithPath: "/")], home: home)
    }

    @Test("Every system root is protected, with its contents",
          arguments: ProtectedPaths.systemRoots)
    func systemRootsAreProtected(root: String) {
        let subject = wideOpenGuard()
        let inside = URL(fileURLWithPath: root).appendingPathComponent("something/deep")

        #expect(subject.protectedMatch(for: URL(fileURLWithPath: root)) != nil, "\(root) itself")
        #expect(subject.protectedMatch(for: inside) != nil, "inside \(root)")
        #expect(throws: SafetyError.self) { try subject.validate(inside) }
    }

    @Test("Every protected home folder is refused, with its contents",
          arguments: ProtectedPaths.homeRelative)
    func homeFoldersAreProtected(relative: String) {
        let subject = wideOpenGuard()
        let folder = home.appendingPathComponent(relative)
        let inside = folder.appendingPathComponent("file.txt")

        #expect(subject.protectedMatch(for: folder) != nil, "\(relative) itself")
        #expect(subject.protectedMatch(for: inside) != nil, "inside \(relative)")
        #expect(throws: SafetyError.self) { try subject.validate(inside) }
    }

    @Test("Protected components are refused wherever they appear",
          arguments: ProtectedPaths.protectedComponents)
    func protectedComponentsAreRefused(component: String) {
        let subject = wideOpenGuard()
        let url = URL(fileURLWithPath: "/Volumes/External/\(component)/anything")
        #expect(subject.protectedMatch(for: url) != nil)
    }

    @Test("Protected package types are refused",
          arguments: ProtectedPaths.protectedPackageExtensions)
    func protectedPackagesAreRefused(ext: String) {
        let subject = wideOpenGuard()
        let url = home.appendingPathComponent("Stuff/Library.\(ext)/inner")
        #expect(subject.protectedMatch(for: url) != nil)
    }

    @Test("/usr is protected but /usr/local is not")
    func usrLocalIsTheDocumentedException() {
        let subject = wideOpenGuard()
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/usr/lib/libSystem.dylib")) != nil)
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/usr/bin/swift")) != nil)
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/usr/local/Cellar/foo")) == nil)
    }

    @Test("A sibling whose name merely starts with a protected path is not protected")
    func prefixCollisionsAreNotProtected() {
        // "/Systemic" must not be caught by the rule protecting "/System".
        let subject = wideOpenGuard()
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/Systemic/data")) == nil)
        #expect(subject.protectedMatch(for: home.appendingPathComponent("Documents-old/x")) == nil)
    }

    @Test("An ordinary cache path is not protected")
    func ordinaryCachesAreAllowed() {
        let subject = wideOpenGuard()
        let cache = home.appendingPathComponent("Library/Caches/com.example.app/data")
        #expect(subject.protectedMatch(for: cache) == nil)
    }
}

@Suite("Allowlist and symlinks")
struct AllowlistTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func cacheGuard() -> PathGuard {
        PathGuard(
            allowedRoots: [home.appendingPathComponent("Library/Caches")],
            home: home
        )
    }

    @Test("A path inside the declared root is allowed")
    func insideRootIsAllowed() throws {
        let subject = cacheGuard()
        let url = home.appendingPathComponent("Library/Caches/com.example/data")
        #expect(throws: Never.self) { try subject.validate(url) }
    }

    @Test("A path outside every declared root is refused — §4.2")
    func outsideRootIsRefused() {
        let subject = cacheGuard()
        let url = home.appendingPathComponent("Downloads/installer.dmg")

        #expect(throws: SafetyError.self) { try subject.validate(url) }
        #expect(!subject.isAllowed(url))
    }

    @Test("The scanner's own root cannot be deleted")
    func rootItselfIsRefused() {
        let subject = cacheGuard()
        let root = home.appendingPathComponent("Library/Caches")
        #expect(throws: SafetyError.self) { try subject.validate(root) }
    }

    @Test("Parent traversal cannot escape the root")
    func traversalIsRefused() {
        let subject = cacheGuard()
        let escape = home.appendingPathComponent("Library/Caches/../../Documents/secret.txt")
        #expect(!subject.isAllowed(escape))
    }

    @Test("Component comparison does not treat a name prefix as containment")
    func containmentUsesComponents() {
        #expect(PathGuard.path("/a/b/c", isWithin: "/a/b"))
        #expect(PathGuard.path("/a/b", isWithin: "/a/b"))
        #expect(!PathGuard.path("/a/bc", isWithin: "/a/b"))
        #expect(!PathGuard.path("/a", isWithin: "/a/b"))
    }
}

/// Symlink behaviour needs real links, so these build a disposable tree in a temp directory
/// and remove it afterwards. Nothing outside that directory is touched.
@Suite("Symlink resolution", .serialized)
struct SymlinkTests {
    private func withTemporaryTree(
        _ body: (_ root: URL, _ allowed: URL, _ outside: URL) throws -> Void
    ) throws {
        // Not NSTemporaryDirectory(): that lives under /private/var/folders, which is on the
        // protected list, so the guard would refuse the fixture itself. /private/tmp is not.
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishSafetyTests-\(UUID().uuidString)")
        let allowed = root.appendingPathComponent("allowed")
        let outside = root.appendingPathComponent("outside")

        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: root) }

        try body(root, allowed, outside)
    }

    @Test("A symlink pointing outside the allowlist is refused as an escape — §4.4")
    func symlinkEscapeIsRefused() throws {
        try withTemporaryTree { _, allowed, outside in
            let target = outside.appendingPathComponent("precious.txt")
            FileManager.default.createFile(atPath: target.path, contents: Data("keep".utf8))

            let link = allowed.appendingPathComponent("innocent.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let subject = PathGuard(allowedRoots: [allowed])

            // The link *looks* like it is inside the allowed root. Resolving first is what
            // catches it.
            #expect(!subject.isAllowed(link))
            #expect(throws: SafetyError.self) { try subject.validate(link) }

            // And the target survives.
            #expect(FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test("A symlink staying inside the allowlist is permitted, and resolves to its target")
    func symlinkWithinRootIsAllowed() throws {
        try withTemporaryTree { _, allowed, _ in
            let target = allowed.appendingPathComponent("real.txt")
            FileManager.default.createFile(atPath: target.path, contents: Data("x".utf8))

            let link = allowed.appendingPathComponent("alias.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let subject = PathGuard(allowedRoots: [allowed])
            let resolved = try subject.validate(link)

            // The caller must act on the resolved path, not the link.
            #expect(resolved.lastPathComponent == "real.txt")
        }
    }
}

/// Regression cover for the `/private` firmlink normalization bug.
///
/// `standardizedFileURL` rewrites `/private/var/db` to `/var/db` but leaves
/// `/private/var/db/x` untouched, so a naive component comparison made the `/private/var/db`
/// protection a no-op for everything beneath it. These assertions pin both spellings.
@Suite("Firmlink normalization")
struct FirmlinkNormalizationTests {
    @Test("Both spellings of a firmlinked path canonicalize the same way",
          arguments: [
            ("/var/db/x", "/private/var/db/x"),
            ("/tmp/a/b", "/private/tmp/a/b"),
            ("/etc/hosts", "/private/etc/hosts")
          ])
    func spellingsAgree(pair: (short: String, long: String)) {
        #expect(
            PathGuard.canonicalComponents(of: pair.short)
                == PathGuard.canonicalComponents(of: pair.long)
        )
    }

    @Test("Containment holds across spellings in both directions")
    func containmentIsSpellingAgnostic() {
        #expect(PathGuard.path("/private/var/db/something", isWithin: "/var/db"))
        #expect(PathGuard.path("/var/db/something", isWithin: "/private/var/db"))
        #expect(PathGuard.path("/private/var/folders/ab/c", isWithin: "/private/var/folders"))
    }

    @Test("Normalization does not catch unrelated top-level folders")
    func unrelatedRootsAreUntouched() {
        #expect(PathGuard.canonicalComponents(of: "/Users/x") == ["/", "Users", "x"])
        #expect(!PathGuard.path("/variable/data", isWithin: "/private/var"))
    }

    @Test("A protected firmlinked root refuses both spellings")
    func protectedFirmlinkRefusesBothSpellings() {
        let subject = PathGuard(
            allowedRoots: [URL(fileURLWithPath: "/")],
            home: URL(fileURLWithPath: "/Users/tester")
        )
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/var/db/anything")) != nil)
        #expect(subject.protectedMatch(for: URL(fileURLWithPath: "/private/var/db/anything")) != nil)
    }
}

/// A declared target may be removed whole; nothing beside it may, and roots stay protected.
@Suite("Allowed targets")
struct AllowedTargetTests {
    private let home = URL(fileURLWithPath: "/Users/tester")
    private var target: URL { home.appendingPathComponent("Library/Application Support/Notion/Cache") }

    private func guardWithTarget() -> PathGuard {
        PathGuard(allowedRoots: [], allowedTargets: [target], home: home)
    }

    @Test("The target folder itself may be removed")
    func targetItselfIsAllowed() {
        #expect(guardWithTarget().isAllowed(target))
    }

    @Test("Anything inside the target is allowed too")
    func insideTargetIsAllowed() {
        #expect(guardWithTarget().isAllowed(target.appendingPathComponent("data_0")))
    }

    @Test("A sibling of the target is refused")
    func siblingIsRefused() {
        let sibling = home.appendingPathComponent("Library/Application Support/Notion/Partitions")
        #expect(!guardWithTarget().isAllowed(sibling))
    }

    @Test("The target's parent is refused: only the named folder is reachable")
    func parentIsRefused() {
        #expect(!guardWithTarget().isAllowed(target.deletingLastPathComponent()))
    }

    @Test("A name that merely starts like the target is refused")
    func prefixCollisionIsRefused() {
        let lookalike = home.appendingPathComponent("Library/Application Support/Notion/Cache-old")
        #expect(!guardWithTarget().isAllowed(lookalike))
    }

    @Test("Roots keep their rule: the root itself still cannot be removed")
    func rootsStayProtected() {
        let root = home.appendingPathComponent("Library/Caches")
        let subject = PathGuard(allowedRoots: [root], allowedTargets: [target], home: home)
        #expect(!subject.isAllowed(root))
        #expect(subject.isAllowed(root.appendingPathComponent("com.example")))
        #expect(subject.isAllowed(target))
    }

    @Test("A protected path is refused even when declared as a target")
    func protectedBeatsTarget() {
        let documents = home.appendingPathComponent("Documents")
        let subject = PathGuard(allowedRoots: [], allowedTargets: [documents], home: home)
        #expect(!subject.isAllowed(documents), "the protected list wins over any target")
    }
}

