import SwiftUI
import AppKit
import CoreKit
import DesignSystem
import SystemMonitor

extension Notification.Name {
    /// Asks the main window to open Smart Scan and start it.
    static let burnishStartSmartScan = Notification.Name("burnish.startSmartScan")
}

/// The small panel in the menu bar — CLAUDE.md §6.8.
///
/// Readings are streamed only while the panel is on screen (§8): `.task` starts when it opens
/// and is cancelled when it closes, so a menu bar item costs nothing while closed.
struct MenuBarPanel: View {
    @State private var snapshot: SystemSnapshot?
    private let monitor = LiveSystemMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let snapshot {
                row("menubar.cpu", value: snapshot.cpu.total.formatted(.percent.precision(.fractionLength(0))))
                row("menubar.memory", value: snapshot.memory.usedFraction.formatted(.percent.precision(.fractionLength(0))))
                row("menubar.disk", value: "\(snapshot.disk.free.formatted())")
                if let battery = snapshot.battery {
                    row("menubar.battery", value: battery.charge.formatted(.percent.precision(.fractionLength(0))))
                }
                row("menubar.network", value: "↓ \(snapshot.network.download.formatted())/s  ↑ \(snapshot.network.upload.formatted())/s")
            } else {
                ProgressView().controlSize(.small)
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: .burnishStartSmartScan, object: nil)
            } label: { Text("menubar.smartScan") }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            } label: { Text("menubar.open") }

            Button { NSApp.terminate(nil) } label: { Text("menubar.quit") }
        }
        .padding(Spacing.medium)
        .frame(width: 280)
        .task {
            for await reading in monitor.stream(interval: .seconds(1)) {
                if Task.isCancelled { break }
                snapshot = reading
            }
        }
    }

    private func row(_ key: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(key).font(Typography.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).numericStyle(Typography.caption)
        }
    }
}
