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
import Licensing

/// Settings — CLAUDE.md §6.9.
struct SettingsView: View {
    let performance: PerformanceModel

    @Environment(\.entitlements) private var entitlements
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var language = AppLanguage.current
    /// The language that was in effect when the app started; a different choice needs a relaunch.
    @State private var launchLanguage = AppLanguage.current
    private let activation = LicenseActivation(store: KeychainLicenseStore())
    @State private var licensePayload: LicensePayload?
    @State private var licenseText = ""
    @State private var licenseFailure: LicenseActivation.Failure?
    @AppStorage("menubar.enabled") private var showsMenuBarItem = false
    @AppStorage("privacy.crashReports") private var crashReports = false
    @AppStorage("schedule.frequency") private var scheduleFrequency = "off"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var fullDiskAccess: Bool?
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
            license.tabItem { Label { Text("settings.tab.license") } icon: { Image(systemName: "key") } }
            about.tabItem { Label { Text("settings.tab.about") } icon: { Image(systemName: "info.circle") } }
            removal.tabItem { Label { Text("settings.tab.uninstall") } icon: { Image(systemName: "trash") } }
        }
        .frame(width: 620, height: 480)
        .padding()
    }

    // MARK: General

    private var general: some View {
        Form {
            Picker(selection: Binding(get: { language }, set: { language = $0; $0.apply() })) {
                ForEach(AppLanguage.allCases) { option in option.label.tag(option) }
            } label: { Text("settings.language") }
            if language != launchLanguage {
                HStack {
                    Text("settings.language.restartNote").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { AppRelauncher.relaunch() } label: { Text("settings.language.restart") }
                }
            }
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in option.label.tag(option.rawValue) }
            } label: { Text("settings.appearance") }
            .pickerStyle(.segmented)
            Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) { Text("settings.launchAtLogin") }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            Toggle(isOn: $showsMenuBarItem) { Text("settings.menuBar") }
            Picker(selection: $scheduleFrequency) {
                Text("settings.schedule.off").tag("off")
                Text("settings.schedule.daily").tag("daily")
                Text("settings.schedule.weekly").tag("weekly")
            } label: { Text("settings.schedule") }
            Text("settings.schedule.note").font(.caption).foregroundStyle(.secondary)
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

    // MARK: Licence

    /// CLAUDE.md §11: a one-time licence checked offline, a 14-day trial, and safety features that
    /// are free in every state. There are no accounts and no subscription.
    private var license: some View {
        Form {
            Section {
                HStack(spacing: Spacing.small) {
                    Image(systemName: entitlements.state.unlocksPro ? "checkmark.seal.fill" : "seal")
                        .font(.title2)
                        .foregroundStyle(entitlements.state.unlocksPro ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        licenseStateTitle.font(.headline)
                        Text("settings.license.model").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("settings.license.status") }

            Section {
                if let payload = licensePayload {
                    LabeledContent { Text(verbatim: payload.email) } label: { Text("settings.license.email") }
                    LabeledContent {
                        Text(payload.updatesUntil, format: .dateTime.day().month(.wide).year())
                    } label: { Text("settings.license.updatesUntil") }
                    LabeledContent { Text(verbatim: "\(payload.deviceLimit)") } label: { Text("settings.license.devices") }
                    Button(role: .destructive) {
                        activation.deactivate()
                        licensePayload = nil
                    } label: { Text("settings.license.deactivate") }
                } else {
                    TextField(text: $licenseText, prompt: Text("settings.license.placeholder"), axis: .vertical) {
                        Text("settings.license.key")
                    }
                        .labelsHidden()
                        .lineLimit(2...4)
                        .font(.system(.caption, design: .monospaced))
                    HStack {
                        if let licenseFailure {
                            failureText(licenseFailure).font(.caption).foregroundStyle(Semantic.warning.color)
                        }
                        Spacer()
                        Button { activateLicense() } label: { Text("settings.license.activate") }
                            .disabled(licenseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !activation.isConfigured {
                        Text("settings.license.notConfigured").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("settings.license.key") }

            Section {
                Grid(alignment: .leading, horizontalSpacing: Spacing.large, verticalSpacing: 4) {
                    GridRow {
                        Text("settings.license.free").font(.subheadline.weight(.semibold))
                        Text("settings.license.pro").font(.subheadline.weight(.semibold))
                    }
                    ForEach(0..<max(Feature.free.count, Feature.pro.count), id: \.self) { row in
                        GridRow(alignment: .top) {
                            featureCell(row < Feature.free.count ? Feature.free[row] : nil)
                            featureCell(row < Feature.pro.count ? Feature.pro[row] : nil)
                        }
                    }
                }
                Text("settings.license.safetyFree").font(.caption).foregroundStyle(.secondary)
            } header: { Text("settings.license.plans") }
        }
        .formStyle(.grouped)
        .onAppear { licensePayload = activation.current() }
    }

    private var licenseStateTitle: Text {
        if licensePayload == nil, case .licensed(let until) = entitlements.state, until == .distantFuture {
            // Phase 1 resolver: everything unlocked while the product is in development (§14).
            return Text("settings.license.state.development")
        }
        switch entitlements.state {
        case .trial(let days): return Text("settings.license.state.trial \(days)")
        case .licensed: return Text("settings.license.state.licensed")
        case .trialExpired: return Text("settings.license.state.trialExpired")
        case .updatesLapsed: return Text("settings.license.state.updatesLapsed")
        }
    }

    @ViewBuilder
    private func featureCell(_ feature: Feature?) -> some View {
        if let feature {
            // Built as a plain String first: an interpolated literal would become the format key
            // "license.feature.%@" and never match the catalog.
            let key = "license.feature." + feature.rawValue
            Label {
                Text(LocalizedStringKey(key)).font(.caption)
            } icon: {
                Image(systemName: "checkmark").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private func failureText(_ failure: LicenseActivation.Failure) -> Text {
        switch failure {
        case .notConfigured: Text("settings.license.error.notConfigured")
        case .empty, .malformed: Text("settings.license.error.malformed")
        case .badSignature: Text("settings.license.error.badSignature")
        case .wrongProduct: Text("settings.license.error.wrongProduct")
        }
    }

    private func activateLicense() {
        switch activation.activate(licenseText) {
        case .success(let payload):
            licensePayload = payload
            licenseText = ""
            licenseFailure = nil
        case .failure(let failure):
            licenseFailure = failure
        }
    }

    // MARK: About

    private var about: some View {
        let identity = AppIdentity.current
        return VStack(spacing: Spacing.medium) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(verbatim: identity.displayName).font(.title.bold())
            Text("settings.about.version \(identity.version) \(identity.build)")
                .font(.callout).foregroundStyle(.secondary)
            Text(verbatim: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                .font(.caption).foregroundStyle(.tertiary)
            Text("settings.about.tagline")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                Button {
                    NotificationCenter.default.post(name: .burnishShowHistory, object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Text("settings.about.history") }
                Button { copyDiagnostics() } label: { Text("settings.diagnostics") }
            }
            Spacer()
        }
        .padding(.top, Spacing.large)
        .frame(maxWidth: .infinity)
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
