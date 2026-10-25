import SwiftUI
import AppKit

/// The interface language (CLAUDE.md §6.9). Burnish ships Turkish and English String Catalogs.
///
/// macOS reads an app's language once at launch from the `AppleLanguages` default in the app's own
/// domain, so a change takes effect after a relaunch, and "system" simply removes the override.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    private static let key = "AppleLanguages"

    /// The choice in effect, read from the app's own defaults domain.
    static var current: AppLanguage {
        guard let first = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key]
            .flatMap({ $0 as? [String] })?.first else { return .system }
        if first.hasPrefix("tr") { return .turkish }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }

    var label: Text {
        switch self {
        case .system: Text("settings.language.system")
        // Each language is named in itself, so it can be found whatever the current language is.
        case .turkish: Text(verbatim: "Türkçe")
        case .english: Text(verbatim: "English")
        }
    }
}

/// Light, dark or follow the system (CLAUDE.md §5.1: dark first, light fully supported).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "appearance"

    /// Nil lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: Text {
        switch self {
        case .system: Text("settings.appearance.system")
        case .light: Text("settings.appearance.light")
        case .dark: Text("settings.appearance.dark")
        }
    }
}

enum AppRelauncher {
    /// Starts a fresh copy of the app, then quits this one, so a new language is picked up.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

extension Notification.Name {
    /// Asks the main window to show the operation history (CLAUDE.md §6.9).
    static let burnishShowHistory = Notification.Name("burnish.showHistory")
}
