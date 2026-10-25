import SwiftUI
import AppKit
import DesignSystem

/// Draws the page's round primary action across the window's bottom edge, as in the supplied design:
/// part of the circle sits on the window, the rest hangs below it.
///
/// A view can never draw outside its window, so the circle lives in a small borderless, transparent
/// child window. A child window moves with its parent; size changes are followed explicitly. The main
/// window itself stays an ordinary opaque window, so there is no transparent margin around it.
struct FloatingActionHost: NSViewRepresentable {
    let action: FloatingAction?

    /// Room around the 156 pt circle for its glow.
    static let panelSize = CGSize(width: 260, height: 240)
    /// How far the circle's centre sits above the window's bottom edge.
    static let centreAboveEdge: CGFloat = 22

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.show(action)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Reports when the representable joins or leaves a window.
    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var parent: NSWindow?
        private var panel: NSPanel?
        private var hosting: NSHostingView<AnyView>?
        private var observers: [NSObjectProtocol] = []
        private var action: FloatingAction?

        func attach(to window: NSWindow?) {
            guard window !== parent else { return }
            detach()
            guard let window else { return }
            parent = window

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: FloatingActionHost.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: AnyView(EmptyView()))
            hosting.frame = NSRect(origin: .zero, size: FloatingActionHost.panelSize)
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting

            let centre = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(centre.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reposition() }
                })
            }
            // A full-screen or minimised window has no bottom edge to hang from.
            for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didMiniaturizeNotification] {
                observers.append(centre.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setVisible(false) }
                })
            }
            for name in [NSWindow.didExitFullScreenNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(centre.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.show(self?.action) }
                })
            }
            show(action)
        }

        func show(_ action: FloatingAction?) {
            self.action = action
            guard let hosting else { return }
            if let action {
                hosting.rootView = AnyView(
                    FloatingActionButton(title: action.title, action: action.perform)
                        .frame(width: FloatingActionHost.panelSize.width, height: FloatingActionHost.panelSize.height)
                )
                let usable = !(parent?.styleMask.contains(.fullScreen) ?? true) && !(parent?.isMiniaturized ?? true)
                setVisible(usable)
            } else {
                setVisible(false)
            }
        }

        private func setVisible(_ visible: Bool) {
            guard let panel, let parent else { return }
            if visible {
                reposition()
                if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
                // `show` runs on every view update (live metrics refresh each second). Ordering a
                // child window front also brings its parent forward, so doing it every time pulled the
                // main window over the Settings window a moment after Settings opened. Only when the
                // panel is not already on screen.
                if !panel.isVisible { panel.orderFront(nil) }
            } else {
                if panel.parent != nil { parent.removeChildWindow(panel) }
                panel.orderOut(nil)
            }
        }

        private func reposition() {
            guard let panel, let parent else { return }
            let size = FloatingActionHost.panelSize
            let frame = parent.frame
            // The detail column is what the button belongs to, so centre it there, not on the window.
            let sidebarWidth = parent.contentView.map { Self.sidebarWidth(in: $0) } ?? 0
            let centreX = frame.minX + sidebarWidth + (frame.width - sidebarWidth) / 2
            let centreY = frame.minY + FloatingActionHost.centreAboveEdge
            panel.setFrame(
                NSRect(x: centreX - size.width / 2, y: centreY - size.height / 2, width: size.width, height: size.height),
                display: true
            )
        }

        /// Width of the split view's first column, 0 when it is collapsed or not found.
        private static func sidebarWidth(in view: NSView) -> CGFloat {
            if let split = view as? NSSplitView, let first = split.arrangedSubviews.first {
                return split.isSubviewCollapsed(first) ? 0 : first.frame.width
            }
            for child in view.subviews {
                let width = sidebarWidth(in: child)
                if width > 0 { return width }
            }
            return 0
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let panel {
                parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            hosting = nil
            parent = nil
        }
    }
}

/// Puts the main window in the middle of its screen when it first appears, every launch.
///
/// macOS otherwise reopens it wherever its saved frame or the default cascade put it, which on a
/// laptop is often the bottom-left corner with part of the window off screen. A window larger than
/// the visible area is shrunk to fit, so the sidebar and the round action are always reachable.
struct CenterWindowOnLaunch: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CenteringView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class CenteringView: NSView {
        private var didCenter = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didCenter, let window else { return }
            didCenter = true
            // After the current pass, so a restored frame applied during this one does not win.
            DispatchQueue.main.async { Self.center(window) }
        }

        static func center(_ window: NSWindow) {
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let width = min(window.frame.width, visible.width)
            let height = min(window.frame.height, visible.height)
            let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
            window.setFrame(frame.integral, display: true)
        }
    }
}
