import Foundation
import CoreKit
import ScanEngine
import Applications

// Read-only: lists apps, the leftovers of one app, and orphaned folders. Deletes nothing.
let apps = try AppCatalogue().installedApps()
print("\(apps.count) apps; largest:")
for app in apps.sorted(by: { $0.size > $1.size }).prefix(5) {
    print("  \(app.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(app.name)  [\(app.bundleID ?? "?")]  last used: \(app.lastUsed.map { "\(Int(Date().timeIntervalSince($0) / 86_400)) d ago" } ?? "unknown")")
}

let target = CommandLine.arguments.dropFirst().first ?? "Notion"
if let app = apps.first(where: { $0.name == target }) {
    let others = Set(apps.compactMap(\.bundleID)).subtracting([app.bundleID ?? ""])
    let found = try LeftoverFinder().leftovers(of: app, otherBundleIDs: others)
    print("\nLeftovers of \(app.name): \(found.count), \(found.totalSize().formatted())")
    for item in found.prefix(10) {
        print("  \(String(describing: item.confidence).padding(toLength: 7, withPad: " ", startingAt: 0))\(item.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
    }
}

let orphans = try OrphanFinder().orphans(installed: apps)
print("\nOrphan folders: \(orphans.count), \(orphans.totalSize().formatted())")
for item in orphans.prefix(12) {
    print("  \(item.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
}
print("Nothing was deleted.")
