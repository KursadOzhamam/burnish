import Foundation
import CoreKit
import ScanEngine
import Files

// Read-only: lists the largest files the scanner would show. Deletes nothing.
let home = FileManager.default.homeDirectoryForCurrentUser
let roots = LargeFilesScanner.defaultRoots(home: home)
print("Searching: \(roots.map(\.lastPathComponent).joined(separator: ", "))")

let scanner = LargeFilesScanner(roots: roots, limit: 15)
let started = Date()
let items = try await scanner.scan(progress: { _ in }, partial: { _ in })
print("Took \(String(format: "%.1f", Date().timeIntervalSince(started))) s, \(items.count) files")
for item in items {
    let age = item.lastUsed.map { Int(Date().timeIntervalSince($0) / 86_400) }
    print("  \(item.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))"
          + "\(age.map { "\($0) d".padding(toLength: 8, withPad: " ", startingAt: 0) } ?? "?       ")"
          + item.url.path.replacingOccurrences(of: home.path, with: "~"))
}
print("Preselected: \(items.defaultSelection().count). Nothing was deleted.")
