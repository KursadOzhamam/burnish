import SwiftUI
import AppKit
import CoreKit
import DesignSystem
import DeletionUI
import ScanEngine
import SafetyKit

/// The Applications screen — CLAUDE.md §6.6.
public struct ApplicationsView: View {
    private enum Tab: Hashable { case apps, orphans, extensions }

    @State private var model: ApplicationsModel
    @State private var tab: Tab = .apps

    private var section: AppSection { .applications }

    public init(model: ApplicationsModel = ApplicationsModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(title: AppsStrings.title, subtitle: AppsStrings.subtitle, palette: section.palette)

            if let report = model.report {
                DeletionResultView(report: report, section: section) { Task { await model.finish() } }
            } else if model.isDeleting {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker(selection: $tab) {
                    Text(AppsStrings.tabApps).tag(Tab.apps)
                    Text(AppsStrings.tabOrphans).tag(Tab.orphans)
                    Text(AppsStrings.tabExtensions).tag(Tab.extensions)
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440, alignment: .leading)

                switch tab {
                case .apps: appsTab
                case .orphans: orphansTab
                case .extensions: extensionsTab
                }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .task { if model.loadState == .idle { await model.load() } }
        .sheet(isPresented: Binding(get: { model.plan != nil }, set: { if !$0 { model.closeReview() } })) {
            ReviewSheet(model: model)
        }
        .sheet(item: Binding(
            get: { model.pendingPlan.map(IdentifiedPlan.init) },
            set: { if $0 == nil { model.dismissConfirmation() } }
        )) { wrapper in
            ConfirmationSheet(
                plan: wrapper.plan, section: section, canRecordHistory: model.canRecordHistory,
                onCancel: model.dismissConfirmation, onConfirm: { model.confirm(wrapper.plan) }
            )
        }
    }

    // MARK: Applications tab

    private var appsTab: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Two short rows rather than one long one: a single row of fixed-size controls is wider
            // than a narrow window and drags the whole layout (sidebar included) out of frame.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.medium) {
                    TextField(text: $model.searchText) { Text(AppsStrings.search) }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Picker(selection: $model.sort) {
                        Text(AppsStrings.sortName).tag(ApplicationsModel.Sort.name)
                        Text(AppsStrings.sortSize).tag(ApplicationsModel.Sort.size)
                        Text(AppsStrings.sortLastUsed).tag(ApplicationsModel.Sort.lastUsed)
                    } label: { Text(AppsStrings.sort) }
                    .fixedSize()
                    Spacer(minLength: 0)
                    Text(AppsStrings.count(model.visibleApps.count)).font(Typography.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: Spacing.medium) {
                    Toggle(isOn: Binding(get: { model.unusedForDays != nil }, set: { model.unusedForDays = $0 ? 90 : nil })) {
                        Text(AppsStrings.unused).lineLimit(1)
                    }
                    Toggle(isOn: $model.includeApple) { Text(AppsStrings.showApple).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .toggleStyle(.checkbox)
            }

            if model.loadState == .loading {
                HStack { ProgressView().controlSize(.small); Text(AppsStrings.loading).font(Typography.caption).foregroundStyle(.secondary) }
            }
            if model.visibleApps.isEmpty, model.loadState == .loaded {
                EmptyState(symbol: "square.grid.2x2", title: AppsStrings.empty, message: AppsStrings.empty)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xxs) {
                        ForEach(model.visibleApps) { app in appRow(app) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: Spacing.small) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).font(Typography.body).lineLimit(1)
                Group {
                    if let days = Self.days(since: app.lastUsed) {
                        Text(AppsStrings.lastUsed(days: days))
                    } else {
                        Text(AppsStrings.neverOpened)
                    }
                }
                .font(Typography.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if model.isRunning(app) {
                Text(AppsStrings.running).font(Typography.caption).foregroundStyle(.secondary)
            }
            Text(app.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
            if app.updateSource != .unknown {
                Button { model.openUpdates(for: app) } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help(Text(app.updateSource == .appStore ? AppsStrings.updateStore : AppsStrings.updateOwn))
                .accessibilityLabel(Text(app.updateSource == .appStore ? AppsStrings.updateStore : AppsStrings.updateOwn))
            }
            Button { Task { await model.review(app) } } label: { Text(AppsStrings.uninstall) }
                .disabled(app.isApple)
        }
    }

    // MARK: Leftovers tab

    private var orphansTab: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(AppsStrings.orphansSubtitle).font(Typography.caption).foregroundStyle(.secondary)
            if model.isScanningOrphans {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.orphans.isEmpty {
                VStack(spacing: Spacing.large) {
                    Spacer()
                    EmptyState(symbol: "tray", title: AppsStrings.orphansNone, message: AppsStrings.orphansSubtitle)
                    ScanButton(title: AppsStrings.orphansScan, palette: section.textSafePalette) { Task { await model.scanOrphans() } }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xxs) {
                        ForEach(model.orphans) { item in
                            Toggle(isOn: Binding(get: { model.orphanSelection.contains(item.id) }, set: { _ in model.toggleOrphan(item) })) {
                                HStack(spacing: Spacing.xs) {
                                    Text(item.displayName).font(Typography.body).lineLimit(1)
                                    Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                        .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                    Spacer()
                                    Text(item.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                HStack {
                    Text(AppsStrings.selected(count: model.selectedOrphans.count, size: model.selectedOrphans.totalSize().formatted()))
                        .font(Typography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await model.scanOrphans() } } label: { Text(AppsStrings.orphansScan) }
                    Button(action: model.prepareOrphanRemoval) { Text(AppsStrings.orphansTrash).frame(minWidth: 140) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.selectedOrphans.isEmpty)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Extensions tab

    private var extensionsTab: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(AppsStrings.extensionsSubtitle).font(Typography.caption).foregroundStyle(.secondary)
            Text(AppsStrings.updateNote).font(Typography.caption).foregroundStyle(.tertiary)
            if model.extensions.isEmpty {
                VStack(spacing: Spacing.large) {
                    Spacer()
                    EmptyState(symbol: "puzzlepiece.extension", title: AppsStrings.extensionsNone, message: AppsStrings.extensionsSubtitle)
                    ScanButton(title: AppsStrings.extensionsScan, palette: section.textSafePalette) { Task { await model.scanExtensions() } }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xxs) {
                        ForEach(model.extensions) { item in
                            Toggle(isOn: Binding(get: { model.extensionSelection.contains(item.id) }, set: { _ in model.toggleExtension(item) })) {
                                HStack(spacing: Spacing.xs) {
                                    Text(item.url.lastPathComponent).font(Typography.body).lineLimit(1)
                                    Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                        .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                    Spacer()
                                    Text(item.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                HStack {
                    Text(AppsStrings.selected(count: model.selectedExtensions.count, size: model.selectedExtensions.totalSize().formatted()))
                        .font(Typography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: model.prepareExtensionRemoval) { Text(AppsStrings.orphansTrash).frame(minWidth: 140) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.selectedExtensions.isEmpty)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private static func days(since date: Date?) -> Int? {
        date.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
    }
}

/// The removal preview for one application: what goes, and what stays unless ticked.
private struct ReviewSheet: View {
    let model: ApplicationsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(title: AppsStrings.reviewTitle, palette: AppSection.applications.palette)

            if model.isLoadingLeftovers {
                HStack { ProgressView().controlSize(.small); Text(AppsStrings.reviewLoading).font(Typography.caption) }
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let plan = model.plan {
                content(plan)
            }
        }
        .padding(Spacing.large)
        .frame(width: 600)
        .frame(maxHeight: 640)
    }

    @ViewBuilder
    private func content(_ plan: UninstallPlan) -> some View {
        row(plan.app, emphasised: true)

        if plan.app.blockedReason == .ownerRunning {
            HStack {
                Label { Text(AppsStrings.runningNote) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(Typography.caption).foregroundStyle(.secondary)
                Spacer()
                if let app = model.apps.first(where: { $0.url == plan.app.url }) {
                    Button { model.requestQuit(app) } label: { Text(AppsStrings.quit) }
                }
            }
        } else if plan.app.blockedReason == .protectedPath {
            Text(AppsStrings.apple).font(Typography.caption).foregroundStyle(.secondary)
        }

        Text(AppsStrings.reviewLeftovers).font(Typography.caption).foregroundStyle(.secondary)
        if plan.leftovers.isEmpty {
            Text(AppsStrings.reviewNone).font(Typography.caption).foregroundStyle(.tertiary)
        } else {
            ScrollView {
                VStack(spacing: Spacing.xxs) { ForEach(plan.leftovers) { row($0, emphasised: false) } }
            }
            .frame(maxHeight: 280)
            if plan.leftovers.contains(where: { $0.confidence == .low }) {
                Text(AppsStrings.reviewLowNote).font(Typography.caption).foregroundStyle(.tertiary)
            }
        }

        HStack {
            Text(AppsStrings.selected(count: model.selectedItems.count, size: model.selectedSize.formatted()))
                .font(Typography.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: model.resetOnly) { Text(AppsStrings.reset) }
            Button(action: model.closeReview) { Text(AppsStrings.reviewCancel) }.keyboardShortcut(.cancelAction)
            Button(action: model.prepareUninstall) { Text(AppsStrings.reviewTrash).frame(minWidth: 130) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selectedItems.isEmpty)
        }
    }

    private func row(_ item: ScanItem, emphasised: Bool) -> some View {
        Toggle(isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) })) {
            HStack(spacing: Spacing.xs) {
                Text(emphasised ? item.displayName : item.url.lastPathComponent)
                    .font(emphasised ? Typography.body.weight(.semibold) : Typography.body).lineLimit(1)
                if !emphasised {
                    Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
                Spacer()
                Text(item.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!item.isActionable)
    }
}

private struct IdentifiedPlan: Identifiable, Equatable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }
}
