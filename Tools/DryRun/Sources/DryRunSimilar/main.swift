import Foundation
import CoreKit
import ScanEngine
import Files

// Read-only: lists groups of look-alike pictures the scanner would show. Deletes nothing.
let home = FileManager.default.homeDirectoryForCurrentUser
let roots = LargeFilesScanner.defaultRoots(home: home)
let started = Date()
let groups = try await SimilarImagesScanner(roots: roots).scan(progress: { _ in }, partial: { _ in })
print("Took \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(groups.count) groups")
for group in groups.prefix(8) {
    print("  \(ByteCount(group.wasted).formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(group.children.count) pictures")
    for copy in group.children.prefix(4) {
        print("       \(copy.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(copy.url.path.replacingOccurrences(of: home.path, with: "~"))")
    }
}
print("Nothing was deleted.")
