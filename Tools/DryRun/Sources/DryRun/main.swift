import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
import Cleanup

// Prints what every cleanup scanner would propose on this Mac, and what the deletion plan
// built from those proposals would contain.
//
// Nothing is deleted. `DeletionService.plan` is a dry run by construction (CLAUDE.md §4.6);
// `execute` is never called here, and this tool has no code path that could call it.

func bar(_ fraction: Double, width: Int = 24) -> String {
    let filled = Int((fraction * Double(width)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
}

func reasonLabel(_ reason: ScanItem.BlockedReason) -> String {
    switch reason {
    case .protectedPath: "protected"
    case .outsideScope: "out of scope"
    case .ownerRunning: "app running"
    case .needsFullDiskAccess: "needs disk access"
    case .needsHelper: "needs helper"
    case .excludedByUser: "excluded"
    case .nestedInAnotherItem: "inside another item"
    }
}

let scanners = CleanupScanner.all()
var grandTotal = ByteCount.zero
var grandBlocked = ByteCount.zero
var guards: [ScannerID: PathGuard] = [:]
var allItems: [ScanItem] = []

print("")
print("Burnish — cleanup dry run")
print("Nothing is deleted. This is the list the confirmation sheet would show.")
print(String(repeating: "─", count: 78))

for scanner in scanners {
    let items: [ScanItem]
    do {
        items = try await scanner.scan { _ in }
    } catch {
        print("\n\(scanner.rule.id)  — failed: \(error)")
        continue
    }

    let actionable = items.filter(\.isActionable)
    let blocked = items.filter { !$0.isActionable }
    let total = items.totalSize()
    grandTotal += actionable.totalSize()
    grandBlocked += blocked.totalSize()

    guards[scanner.id] = PathGuard(allowedRoots: scanner.allowedRoots)
    allItems += items

    print("")
    print("\(scanner.rule.id)")
    print("  roots      \(scanner.allowedRoots.count) declared, "
          + "\(scanner.allowedRoots.filter { FileManager.default.fileExists(atPath: $0.path) }.count) present")
    print("  found      \(items.count) items, \(total.formatted())")
    if !blocked.isEmpty {
        let reasons = Set(blocked.compactMap(\.blockedReason)).map(reasonLabel).sorted()
        print("  blocked    \(blocked.count) items, \(blocked.totalSize().formatted())"
              + "  (\(reasons.joined(separator: ", ")))")
    }

    for item in actionable.sorted(by: { $0.size > $1.size }).prefix(6) {
        let share = item.size.fraction(of: total)
        print("    \(bar(share))  \(item.size.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))"
              + "  \(item.displayName)")
    }
    if actionable.count > 6 {
        print("    … and \(actionable.count - 6) more")
    }
}

// Now build the plan the user would actually approve, through the real service.
let service = DeletionService(
    guards: guards,
    inspector: RunningApplicationInspector()
)
let plan = service.plan(for: allItems, mode: .trash)

print("")
print(String(repeating: "─", count: 78))
print("Plan that would be presented for approval:")
print("  mode               \(plan.mode) (reversible: \(!plan.mode.isIrreversible))")
print("  would move         \(plan.itemCount) items, \(plan.totalSize.formatted())")
print("  would skip         \(plan.skipped.count) items")
if !plan.skipped.isEmpty {
    let grouped = Dictionary(grouping: plan.skipped) { $0.blockedReason ?? .outsideScope }
    for (reason, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
        print("      \(reasonLabel(reason).padding(toLength: 18, withPad: " ", startingAt: 0))"
              + "\(items.count) items, \(items.totalSize().formatted())")
    }
}
print("  extra confirm      \(plan.requiresExtraConfirmation ? "required" : "not required")")
print("")
print("Nothing was deleted.")
print("")
