import SwiftUI
import AppKit
import ServiceManagement
import CoreKit
import CoreKitMac
import Cleanup
import DesignSystem
import DeletionUI
import Performance
import SafetyKit

/// Settings — CLAUDE.md §6.9.
struct SettingsView: View {
    let performance: PerformanceModel

    @AppStorage("menubar.enabled") private var showsMenuBarItem = true
    @AppStorage("privacy.crashReports") private var crashReports = false
    @AppStorage("schedule.frequency") private var scheduleFrequency = "off"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var fullDiskAccess = FullDiskAccess.isGranted()
    @State private var preferences = ScannerPreferences()
    @State private var rules = CleanupCatalogue.all
    @State private var refresh = 0
    @State private var uninstall = UninstallBurnishModel()
    @State private var isConfirmingUninstall = false

    var body: some View {
        TabView {
            general.tabItem { Label { Text("settings.tab.general") } icon: { Image(systemName: "gearshape") } }
            scanning.tabItem { Label { Text("settings.tab.scanning") } icon: { Image(systemName: "magnifyingglass") } }
            permissions.tabItem { Label { Text("settings.tab.permissions") } icon: { Image(systemName: "lock.shield") } }
            privacy.tabItem { Label { Text("settings.tab.privacy") } icon: { Image(systemName: "hand.raised") } }
            removal.tabItem { Label { Text("settings.tab.uninstall") } icon: { Image(systemName: "trash") } }
        }
        .frame(width: 560, height: 420)
        .padding()
    }

    // MARK: General

    private var general: some View {
        Form {
            Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) { Text("settings.launchAtLogin") }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            Toggle(isOn: $showsMenuBarItem) { Text("settings.menuBar") }
            Picker(selection: $scheduleFrequency) {
                Text("settings.schedule.off").tag("off")
                Text("settings.schedule.daily").tag("daily")
                Text("settings.schedule.weekly").tag("weekly")
            } label: { Text("settings.schedule") }
            Text("settings.schedule.note").font(.caption).foregroundStyle(.secondary)
            Text("settings.language.note").font(.caption).foregroundStyle(.secondary)
            Text("settings.deletion.note").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        loginError = nil
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Scanning

    private var scanning: some View {
        Form {
            Text("settings.scanners.note").font(.caption).foregroundStyle(.secondary)
            ForEach(rules) { rule in
                Toggle(isOn: Binding(
                    get: { _ = refresh; return preferences.isEnabled(rule) },
                    set: { preferences.setEnabled($0, for: rule); refresh += 1 }
                )) { Text(CleanupScanner(rule: rule).title) }
            }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        Form {
            HStack {
                Text("settings.fullDiskAccess")
                Spacer()
                Text(fullDiskAccess == true ? "settings.granted" : (fullDiskAccess == false ? "settings.notGranted" : "settings.unknown"))
                    .foregroundStyle(.secondary)
                Button { open(FullDiskAccess.settingsURLString) } label: { Text("settings.openSettings") }
            }
            HStack {
                Text("settings.helper")
                Spacer()
                Text(helperText).foregroundStyle(.secondary)
                Button { Task { await performance.installHelper() } } label: { Text("settings.helperInstall") }
                    .disabled(performance.helperStatus == .enabled)
            }
        }
        .task { await performance.refreshHelper(); fullDiskAccess = FullDiskAccess.isGranted() }
    }

    private var helperText: LocalizedStringKey {
        switch performance.helperStatus {
        case .enabled: "settings.helper.enabled"
        case .requiresApproval: "settings.helper.approval"
        default: "settings.helper.off"
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: Privacy

    private var privacy: some View {
        Form {
            Toggle(isOn: $crashReports) { Text("settings.crashReports") }
            Text("settings.crashReports.note").font(.caption).foregroundStyle(.secondary)
            Text("settings.noData").font(.caption).foregroundStyle(.secondary)
            Button { copyDiagnostics() } label: { Text("settings.diagnostics") }
            Text("settings.diagnostics.note").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Version and state only: no file name, path or content (CLAUDE.md §10.7, §13.4). The user
    /// decides where it goes.
    private func copyDiagnostics() {
        let identity = AppIdentity.current
        let lines = [
            "\(identity.displayName) \(identity.version) (\(identity.build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Full Disk Access: \(String(describing: FullDiskAccess.isGranted()))",
            "Helper: \(String(describing: performance.helperStatus))",
            "Disabled scanners: \(rules.filter { !preferences.isEnabled($0) }.map { $0.id.rawValue }.joined(separator: ", "))"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: Remove Burnish

    private var removal: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("settings.uninstall.note").font(.caption).foregroundStyle(.secondary)
            switch uninstall.step {
            case .idle:
                Button { uninstall.prepare() } label: { Text("settings.uninstall.show") }
            case .ready:
                if uninstall.items.isEmpty {
                    Text("settings.uninstall.none").font(.caption)
                } else {
                    ForEach(uninstall.items) { item in
                        HStack {
                            Text((item.url.path as NSString).abbreviatingWithTildeInPath).font(.caption).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text(item.size.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(role: .destructive) { uninstall.requestConfirmation() } label: { Text("settings.uninstall.run") }
                    .disabled(uninstall.items.isEmpty)
            case .working:
                ProgressView()
            case .done(let failures):
                Text("settings.uninstall.done").font(.caption)
                if !failures.isEmpty { Text(failures.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                Button { uninstall.moveAppToTrash() } label: { Text("settings.uninstall.trashApp") }
            }
            Spacer()
        }
        .sheet(item: Binding(
            get: { uninstall.pendingPlan.map(PlanBox.init) },
            set: { if $0 == nil { uninstall.dismissConfirmation() } }
        )) { box in
            ConfirmationSheet(
                plan: box.plan, section: .dashboard, canRecordHistory: false,
                onCancel: uninstall.dismissConfirmation, onConfirm: { uninstall.confirm(box.plan) }
            )
        }
    }
}

private struct PlanBox: Identifiable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }
}
