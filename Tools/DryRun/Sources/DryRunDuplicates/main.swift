import Foundation
import CoreKit
import ScanEngine
import Files

// Read-only: lists duplicate groups the scanner would show. Deletes nothing.
let home = FileManager.default.homeDirectoryForCurrentUser
let roots = LargeFilesScanner.defaultRoots(home: home)
let started = Date()
let groups = try await DuplicateScanner(roots: roots).scan(progress: { _ in }, partial: { _ in })
let wasted = groups.reduce(Int64(0)) { $0 + $1.wasted }
print("Took \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(groups.count) groups, \(ByteCount(wasted).formatted()) in extra copies")
for group in groups.prefix(10) {
    print("  \(ByteCount(group.wasted).formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(group.children.count)x  \(group.displayName)")
    for copy in group.children {
        print("       \(copy.url.path.replacingOccurrences(of: home.path, with: "~"))")
    }
}
print("Nothing was deleted.")
