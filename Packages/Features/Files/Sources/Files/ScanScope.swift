import Foundation
import Observation

/// Which folders the Files screens search, and which they leave alone (CLAUDE.md §6.9).
///
/// One scope is shared by large files, duplicates and similar pictures, so the choice is made
/// once. The user can switch the default folders off, add their own (including other volumes),
/// and exclude folders inside them. Choices persist in `UserDefaults`.
@Observable
@MainActor
public final class ScanScope {
    public private(set) var candidates: [URL]
    public private(set) var disabled: Set<String>
    public private(set) var excluded: [URL]

    private let defaults: UserDefaults?
    private let defaultRoots: [URL]

    private enum Key {
        static let added = "files.scope.added"
        static let disabled = "files.scope.disabled"
        static let excluded = "files.scope.excluded"
    }

    /// - Parameters:
    ///   - defaultRoots: the folders offered out of the box.
    ///   - defaults: where choices persist; nil keeps them in memory only.
    public init(
        defaultRoots: [URL] = LargeFilesScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser),
        defaults: UserDefaults? = nil
    ) {
        self.defaults = defaults
        self.defaultRoots = defaultRoots.map(Self.normalized)
        let added = (defaults?.stringArray(forKey: Key.added) ?? []).map { URL(fileURLWithPath: $0) }
        var all = self.defaultRoots
        for url in added where !all.contains(where: { $0.path == url.path }) { all.append(url) }
        candidates = all
        disabled = Set(defaults?.stringArray(forKey: Key.disabled) ?? [])
        excluded = (defaults?.stringArray(forKey: Key.excluded) ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// A fixed scope that searches exactly `roots`. Used by tests and one-off tools.
    public convenience init(roots: [URL]) {
        self.init(defaultRoots: roots, defaults: nil)
    }

    /// The same location without a trailing slash. Not `standardizedFileURL`: that rewrites
    /// `/private/tmp` to `/tmp`, so a path the user picked would no longer compare equal to itself.
    private static func normalized(_ url: URL) -> URL { URL(fileURLWithPath: url.path) }

    // MARK: Reading

    /// The folders to search: enabled candidates that still exist.
    public var roots: [URL] {
        candidates.filter { !disabled.contains($0.path) && FileManager.default.fileExists(atPath: $0.path) }
    }

    public func isEnabled(_ url: URL) -> Bool { !disabled.contains(url.path) }

    public func isDefault(_ url: URL) -> Bool { defaultRoots.contains { $0.path == url.path } }

    /// Paths the scanners must not enter.
    public var excludedPaths: [String] { excluded.map(\.path) }

    // MARK: Changing

    public func setEnabled(_ isOn: Bool, for url: URL) {
        if isOn { disabled.remove(url.path) } else { disabled.insert(url.path) }
        save()
    }

    /// Adds a folder to search. A folder already listed is just switched back on.
    public func add(_ url: URL) {
        let standardized = Self.normalized(url)
        if !candidates.contains(where: { $0.path == standardized.path }) { candidates.append(standardized) }
        disabled.remove(standardized.path)
        save()
    }

    /// Removes a folder the user added. The built-in ones can only be switched off.
    public func remove(_ url: URL) {
        guard !isDefault(url) else { return }
        candidates.removeAll { $0.path == url.path }
        disabled.remove(url.path)
        save()
    }

    public func exclude(_ url: URL) {
        let standardized = Self.normalized(url)
        guard !excluded.contains(where: { $0.path == standardized.path }) else { return }
        excluded.append(standardized)
        save()
    }

    public func include(_ url: URL) {
        excluded.removeAll { $0.path == url.path }
        save()
    }

    private func save() {
        guard let defaults else { return }
        defaults.set(candidates.filter { !isDefault($0) }.map(\.path), forKey: Key.added)
        defaults.set(Array(disabled), forKey: Key.disabled)
        defaults.set(excluded.map(\.path), forKey: Key.excluded)
    }

    // MARK: Volumes

    /// Mounted volumes the user could add: external and network disks, not the system volume.
    public static func mountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.volumeIsRootFileSystem != true && values?.volumeIsBrowsable != false
        }
    }
}

/// Whether `url` is, or is inside, one of the excluded paths.
func isExcluded(_ url: URL, by paths: [String]) -> Bool {
    let path = url.path
    return paths.contains { path == $0 || path.hasPrefix($0 + "/") }
}
