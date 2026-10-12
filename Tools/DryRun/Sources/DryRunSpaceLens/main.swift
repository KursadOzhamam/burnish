import Foundation
import CoreKit
import ScanEngine
import Files

// Read-only: measures a folder tree the way Space Lens would and prints the top of it.
let home = FileManager.default.homeDirectoryForCurrentUser
let root = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) } ?? home
let started = Date()
let items = try await SpaceLensScanner(root: root).scan(progress: { _ in }, partial: { _ in })
let tree = items[0]
print("Root \(root.path): \(tree.totalSize.formatted()), measured in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")

func nodeCount(_ item: ScanItem) -> Int { 1 + item.children.map(nodeCount).reduce(0, +) }
print("Nodes in memory: \(nodeCount(tree))")

func show(_ item: ScanItem, depth: Int) {
    for child in item.children.prefix(depth == 0 ? 8 : 4) {
        let name = child.displayName.isEmpty ? "(other)" : child.displayName
        print("\(String(repeating: "  ", count: depth + 1))\(child.totalSize.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(name)")
        if depth < 1 { show(child, depth: depth + 1) }
    }
}
show(tree, depth: 0)
print("Nothing was deleted.")
