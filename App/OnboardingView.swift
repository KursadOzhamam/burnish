import SwiftUI
import AppKit
import CoreKitMac
import DesignSystem

/// The first-launch welcome — CLAUDE.md §14, phase 10.
///
/// Three short steps: what Burnish promises, the one permission that saves a lot of prompts, and
/// where to start. Nothing is required: every step can be skipped, and the app works without the
/// permission (§7).
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var fullDiskAccess = FullDiskAccess.isGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            switch page {
            case 0: promises
            case 1: access
            default: start
            }
            Spacer(minLength: 0)
            HStack {
                Button(action: onFinish) { Text("onboarding.skip") }.buttonStyle(.borderless)
                Spacer()
                if page > 0 { Button { page -= 1 } label: { Text("onboarding.back") } }
                Button {
                    if page < 2 { page += 1 } else { onFinish() }
                } label: { Text(page < 2 ? "onboarding.next" : "onboarding.finish").frame(minWidth: 90) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 560, height: 420)
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("onboarding.title").font(Typography.title)
            promise("trash.slash", "onboarding.promise.trash")
            promise("eye", "onboarding.promise.preview")
            promise("hand.raised", "onboarding.promise.honest")
            promise("lock", "onboarding.promise.private")
        }
    }

    private func promise(_ symbol: String, _ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(key).font(Typography.body)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("onboarding.access.title").font(Typography.title)
            Text("onboarding.access.body").font(Typography.body).foregroundStyle(.secondary)
            if fullDiskAccess == true {
                Label { Text("onboarding.access.granted") } icon: { Image(systemName: "checkmark.circle.fill") }
            } else {
                Button {
                    if let url = URL(string: FullDiskAccess.settingsURLString) { NSWorkspace.shared.open(url) }
                } label: { Text("onboarding.access.open") }
                Text("onboarding.access.optional").font(Typography.caption).foregroundStyle(.tertiary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess = FullDiskAccess.isGranted()
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("onboarding.start.title").font(Typography.title)
            Text("onboarding.start.body").font(Typography.body).foregroundStyle(.secondary)
        }
    }
}
