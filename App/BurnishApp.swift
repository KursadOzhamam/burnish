import SwiftUI
import CoreKit
import DesignSystem
import Licensing

@main
struct BurnishApp: App {
    /// Phase 1 unlocks everything; real validation arrives in Phase 10 (CLAUDE.md §11, §14).
    @State private var entitlements: any EntitlementResolving = AlwaysProEntitlements()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.entitlements, entitlements)
                // §5.1: dark-first, with light fully supported — so no scheme is forced here.
                .frame(minWidth: 940, minHeight: 640)
        }
        // §5.1: transparent title bar with full-size content.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
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
