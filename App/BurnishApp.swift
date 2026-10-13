import SwiftUI
import CoreKit
import DesignSystem
import Licensing
import Performance

@main
struct BurnishApp: App {
    /// Phase 1 unlocks everything; real validation arrives in Phase 10 (CLAUDE.md §11, §14).
    @State private var entitlements: any EntitlementResolving = AlwaysProEntitlements()
    /// The menu bar item can be switched off in Settings (CLAUDE.md §6.8).
    @AppStorage("menubar.enabled") private var showsMenuBarItem = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.entitlements, entitlements)
                // §5.1: dark-first, with light fully supported — so no scheme is forced here.
                .frame(minWidth: 940, minHeight: 640 + 84)
        }
        // §5.1: transparent title bar with full-size content.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(performance: PerformanceModel())
        }

        // The binding is read-only on purpose. SwiftUI writes `isInserted` back whenever macOS hides
        // or shows the item (a crowded menu bar next to the notch does this), and writing that into
        // `AppStorage` re-evaluated the scene in an endless loop that pinned the main thread at 100%
        // and froze the window. Only the Settings switch changes it now.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarItem }, set: { _ in })) {
            MenuBarPanel()
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Entitlement injection

private struct EntitlementsKey: EnvironmentKey {
    static let defaultValue: any EntitlementResolving = AlwaysProEntitlements()
}

extension EnvironmentValues {
    /// Gates Pro features. Injected once so views never construct a resolver themselves.
    var entitlements: any EntitlementResolving {
        get { self[EntitlementsKey.self] }
        set { self[EntitlementsKey.self] = newValue }
    }
}
