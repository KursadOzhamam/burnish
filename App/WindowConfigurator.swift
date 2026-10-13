import SwiftUI
import AppKit

/// Makes the window itself transparent, so the app can draw its own rounded container and let the
/// primary button hang out past it (the supplied design). The window keeps its title bar buttons
/// and its shadow follows the opaque container.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.invalidateShadow()
    }
}
