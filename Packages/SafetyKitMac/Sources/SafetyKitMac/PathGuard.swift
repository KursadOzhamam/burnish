import Foundation
import ScanEngine
import SafetyKit

/// Decides whether a path may be removed.
///
/// Implements the allowlist (CLAUDE.md §4.2), the protected list (§4.3) and symlink resolution
/// (§4.4). Every check runs against the **resolved** path, so a symlink cannot be used to step
/// outside a scanner's root.
///
/// The order matters and is deliberate: resolve first, then test containment, then test
/// protection. Testing before resolving is exactly the mistake §4.4 exists to prevent.
public struct PathGuard: Sendable {
    /// The roots this guard permits, already standardized. Everything *inside* a root may be
    /// removed; the root itself may not.
    public let allowedRoots: [URL]

    /// Folders that may be removed whole.
    ///
    /// A scanner whose finding is one specific folder (an application's cache directory) names
    /// that folder as a target. The target and what is inside it are allowed, nothing beside it
    /// is, and unlike a root it may be deleted itself. Kept separate so the "never remove a
    /// scanner's own root" rule below stays absolute for roots.
    public let allowedTargets: [URL]

    private let home: URL

    /// - Parameters:
    ///   - allowedRoots: the scanner's declared roots. A path outside all of them is refused.
    ///   - home: the user's home directory, used to resolve the home-relative protected list.
    public init(
        allowedRoots: [URL],
        allowedTargets: [URL] = [],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        self.allowedTargets = allowedTargets.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        // Resolved too: on macOS the home directory itself can sit behind a firmlink, and an
        // unresolved home would silently fail to match the protected list.
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Throws if `url` may not be removed; returns the resolved path if it may.
    ///
    /// Callers must use the returned URL for the actual removal — using the original would
    /// reintroduce the symlink hole this method closes.
    @discardableResult
    public func validate(_ url: URL) throws -> URL {
        let original = url.standardizedFileURL
        let resolved = original.resolvingSymlinksInPath().standardizedFileURL

        // §4.4: a symlink that resolves outside the allowlist is an escape, reported as such so
        // the result screen can say what happened rather than just "skipped".
        if resolved.path != original.path, !isWithinAllowedRoots(resolved) {
            throw SafetyError.symlinkEscape(from: original.path, to: resolved.path)
        }

        guard let root = containingRoot(of: resolved) else {
            throw SafetyError.outsideAllowlist(
                path: resolved.path,
                root: (allowedRoots + allowedTargets).first?.path ?? "(none)"
            )
        }

        if let violated = protectedMatch(for: resolved) {
            throw SafetyError.protectedPath(violated)
        }

        // Refuse to delete a scanner's own root: a bug in a scanner must not wipe the folder
        // it was pointed at. A declared target is the one exception, because removing that exact
        // folder is the whole point of it.
        let isTarget = allowedTargets.contains { $0.path == resolved.path }
        if resolved.path == root.path, !isTarget {
            throw SafetyError.protectedPath(root.path)
        }

        return resolved
    }

    /// Non-throwing form for filtering lists.
    public func isAllowed(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }

    // MARK: Containment

    private func isWithinAllowedRoots(_ url: URL) -> Bool {
        containingRoot(of: url) != nil
    }

    private func containingRoot(of url: URL) -> URL? {
        (allowedRoots + allowedTargets).first { Self.path(url.path, isWithin: $0.path) }
    }

    /// True when `path` is `root` or lies beneath it.
    ///
    /// Compares canonical path components rather than string prefixes, so `/Users/foo-backup`
    /// is not treated as being inside `/Users/foo`.
    static func path(_ path: String, isWithin root: String) -> Bool {
        let pathComponents = canonicalComponents(of: path)
        let rootComponents = canonicalComponents(of: root)
        guard pathComponents.count >= rootComponents.count else { return false }
        return Array(pathComponents.prefix(rootComponents.count)) == rootComponents
    }

    /// Path components in one canonical form.
    ///
    /// `standardizedFileURL` cannot be trusted to normalize the `/private` firmlinks
    /// consistently: it rewrites `/private/var/db` to `/var/db`, but leaves
    /// `/private/var/db/something` alone. Comparing one against the other therefore fails, and
    /// a protected root would silently stop protecting anything beneath it.
    ///
    /// Both sides are expanded to the `/private` form here so the comparison is symmetric.
    static func canonicalComponents(of path: String) -> [String] {
        var components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        // macOS firmlinks these three into /private.
        let firmlinked: Set<String> = ["var", "tmp", "etc"]
        if components.count >= 2, firmlinked.contains(components[1]) {
            components.insert("private", at: 1)
        }
        return components
    }

    // MARK: Protection

    /// Returns the protected root that `url` violates, or nil when it violates none.
    func protectedMatch(for url: URL) -> String? {
        let path = url.standardizedFileURL.path

        for root in ProtectedPaths.systemRoots where Self.path(path, isWithin: root) {
            return root
        }

        for rule in ProtectedPaths.partiallyProtectedRoots
        where Self.path(path, isWithin: rule.root) && !Self.path(path, isWithin: rule.exception) {
            return rule.root
        }

        for relative in ProtectedPaths.homeRelative {
            let absolute = home.appendingPathComponent(relative).path
            if Self.path(path, isWithin: absolute) { return absolute }
        }

        let components = url.pathComponents
        for component in components {
            if ProtectedPaths.protectedComponents.contains(component) { return component }
            let ext = (component as NSString).pathExtension
            if !ext.isEmpty, ProtectedPaths.protectedPackageExtensions.contains(ext.lowercased()) {
                return component
            }
        }

        return nil
    }
}
