import SwiftUI
import AppKit
import CoreKit
import DesignSystem

/// The Protection screen — CLAUDE.md §6.4.
public struct ProtectionView: View {
    private enum Tab: Hashable { case scan, quarantine, system }

    @State private var model: ProtectionModel
    @State private var tab: Tab = .scan

    private var section: AppSection { .protection }

    public init(model: ProtectionModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(title: ProtStrings.title, subtitle: ProtStrings.subtitle, palette: section.palette)

            Picker(selection: $tab) {
                Text(ProtStrings.tabScan).tag(Tab.scan)
                Text(ProtStrings.tabQuarantine).tag(Tab.quarantine)
                Text(ProtStrings.tabSystem).tag(Tab.system)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 440, alignment: .leading)

            if let message = model.message { messageBar(message) }

            switch tab {
            case .scan: scanTab
            case .quarantine: quarantineTab
            case .system: systemTab
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    // MARK: Messages

    private func messageBar(_ message: ProtectionModel.Message) -> some View {
        let (prefix, name): (LocalizedStringResource, String) = switch message {
        case .quarantined(let name): (ProtStrings.messageQuarantined, name)
        case .restored(let name): (ProtStrings.messageRestored, name)
        case .refused(let name): (ProtStrings.messageRefused, name)
        case .failed(let text): (ProtStrings.messageFailed, text)
        }
        return Text("\(String(localized: prefix))\(name)").font(Typography.caption).foregroundStyle(.secondary)
    }

    // MARK: Scan

    @ViewBuilder
    private var scanTab: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: Spacing.large) {
                Spacer()
                EmptyState(symbol: "shield.lefthalf.filled", title: ProtStrings.title, message: ProtStrings.scanWhat)
                ScanButton(title: ProtStrings.scanStart, palette: section.textSafePalette, action: model.scan)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .scanning(let examined, let path):
            VStack(spacing: Spacing.large) {
                Spacer()
                GradientRing(progress: 0, palette: section.palette, lineWidth: 14, isIndeterminate: true)
                    .frame(width: 160, height: 160)
                    .overlay { Text("\(examined)").numericStyle(Typography.metric) }
                Text(ProtStrings.progress(examined)).font(Typography.caption).foregroundStyle(.secondary)
                Text(path).font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
                Button(role: .cancel, action: model.cancel) { Text(ProtStrings.scanCancel).frame(minWidth: 110) }
                    .controlSize(.large)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .finished:
            if model.findings.isEmpty {
                VStack(spacing: Spacing.large) {
                    Spacer()
                    EmptyState(symbol: "checkmark.shield", title: ProtStrings.scanClean, message: ProtStrings.scanCleanDetail)
                    Button(action: model.scan) { Text(ProtStrings.scanRescan) }.controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                findingsList
            }
        }
    }

    private var findingsList: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text(ProtStrings.found(model.findings.count)).font(Typography.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: model.scan) { Text(ProtStrings.scanRescan) }
            }
            ScrollView {
                LazyVStack(spacing: Spacing.small) {
                    ForEach(model.findings) { finding in findingCard(finding) }
                }
            }
        }
    }

    private func findingCard(_ finding: Finding) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(severityLabel(finding.severity)).font(Typography.caption.weight(.semibold)).foregroundStyle(severityColor(finding.severity))
                Text(finding.url.lastPathComponent).font(Typography.body).lineLimit(1)
                Spacer()
            }
            Text((finding.url.path as NSString).abbreviatingWithTildeInPath)
                .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            Text(ProtStrings.findingWhy).font(Typography.caption).foregroundStyle(.secondary)
            Text(reasonText(finding.reason)).font(Typography.caption).foregroundStyle(.secondary)
            HStack {
                Button { model.quarantine(finding) } label: { Text(ProtStrings.actionQuarantine) }
                Button { model.allow(finding) } label: { Text(ProtStrings.actionSafe) }
                Button { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) } label: { Text(ProtStrings.actionReveal) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: CornerRadius.medium).fill(.quaternary.opacity(0.5)) }
    }

    private func severityLabel(_ severity: Finding.Severity) -> LocalizedStringResource {
        switch severity {
        case .threat: ProtStrings.findingThreat
        case .suspicious: ProtStrings.findingSuspicious
        case .info: ProtStrings.findingInfo
        }
    }

    /// Red only for a real threat (CLAUDE.md §10.3); a suspicion is amber, information is neutral.
    private func severityColor(_ severity: Finding.Severity) -> Color {
        switch severity {
        case .threat: Semantic.danger.color
        case .suspicious: Semantic.warning.color
        case .info: Color.secondary
        }
    }

    private func reasonText(_ reason: Finding.Reason) -> String {
        switch reason {
        case .knownBadHash(let name): String(localized: ProtStrings.reasonKnownBadHash) + name
        case .ruleMatch(_, let description): description
        case .unsignedFromInternet: String(localized: ProtStrings.reasonUnsignedFromInternet)
        case .invalidSignature: String(localized: ProtStrings.reasonInvalidSignature)
        case .danglingLaunchItem(let label): String(localized: ProtStrings.reasonDanglingLaunchItem) + label
        case .hiddenLaunchItem(let label): String(localized: ProtStrings.reasonHiddenLaunchItem) + label
        }
    }

    // MARK: Quarantine

    private var quarantineTab: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(ProtStrings.quarantineNote).font(Typography.caption).foregroundStyle(.secondary)
            if model.quarantined.isEmpty {
                VStack { Spacer(); EmptyState(symbol: "tray", title: ProtStrings.quarantineEmpty, message: ProtStrings.quarantineNote); Spacer() }
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(model.quarantined) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(record.storedName).font(Typography.body).lineLimit(1)
                                    Text((record.originalPath as NSString).abbreviatingWithTildeInPath)
                                        .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                Button { model.restore(record) } label: { Text(ProtStrings.actionRestore) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: System state

    private var systemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                statusRow(ProtStrings.systemGatekeeper, model.status?.gatekeeperEnabled)
                statusRow(ProtStrings.systemSip, model.status?.sipEnabled)
                HStack {
                    Text(ProtStrings.systemXprotect).font(Typography.body)
                    Spacer()
                    Text(model.status?.xprotectVersion ?? String(localized: ProtStrings.systemUnknown)).font(Typography.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(ProtStrings.systemBlocklist).font(Typography.body)
                    Spacer()
                    Text(model.blocklistCount == 0
                         ? String(localized: ProtStrings.systemBlocklistNone)
                         : "v\(model.blocklistVersion) · \(model.blocklistCount)")
                        .font(Typography.caption).foregroundStyle(.secondary)
                }

                Divider()
                Text(ProtStrings.permissionsTitle).font(Typography.body.weight(.semibold))
                Text(ProtStrings.permissionsNote).font(Typography.caption).foregroundStyle(.secondary)
                if model.permissionsNeedFullDiskAccess {
                    Text(ProtStrings.permissionsNeedFDA).font(Typography.caption).foregroundStyle(Semantic.warning.color)
                }
                ForEach(TCCReader.Entry.Service.allCases, id: \.self) { service in permissionGroup(service) }
            }
        }
        .task { await model.refreshStatus() }
    }

    private func statusRow(_ title: LocalizedStringResource, _ value: Bool?) -> some View {
        HStack {
            Text(title).font(Typography.body)
            Spacer()
            Text(value == nil ? ProtStrings.systemUnknown : (value == true ? ProtStrings.systemOn : ProtStrings.systemOff))
                .font(Typography.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func permissionGroup(_ service: TCCReader.Entry.Service) -> some View {
        let clients = model.permissions.filter { $0.service == service }.map(\.client).sorted()
        if !clients.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(serviceName(service)).font(Typography.caption.weight(.semibold))
                    Spacer()
                    Button { model.openSettings(for: service) } label: { Text(ProtStrings.permissionsOpenSettings) }
                        .buttonStyle(.borderless).font(Typography.caption)
                }
                ForEach(clients, id: \.self) { Text($0).font(Typography.path).foregroundStyle(.secondary) }
            }
        }
    }

    private func serviceName(_ service: TCCReader.Entry.Service) -> LocalizedStringResource {
        switch service {
        case .camera: ProtStrings.serviceCamera
        case .microphone: ProtStrings.serviceMicrophone
        case .screenRecording: ProtStrings.serviceScreenRecording
        case .fullDiskAccess: ProtStrings.serviceFullDiskAccess
        case .accessibility: ProtStrings.serviceAccessibility
        case .inputMonitoring: ProtStrings.serviceInputMonitoring
        case .contacts: ProtStrings.serviceContacts
        case .photos: ProtStrings.servicePhotos
        case .location: ProtStrings.serviceLocation
        }
    }
}
