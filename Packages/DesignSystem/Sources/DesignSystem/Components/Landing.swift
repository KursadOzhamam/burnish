import SwiftUI

// The building blocks of the supplied design: a section page is a header, a hero card with a
// status ring, a list card and an info card, a footer and one floating action button. Every
// section is assembled from these, so they cannot drift apart.

// MARK: Card surface

/// White card with a hairline border and a very soft shadow.
public struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    let fill: KeyPath<ThemeColors, Color>
    let border: KeyPath<ThemeColors, Color>

    public func body(content: Content) -> some View {
        let t = scheme.theme
        content
            .background { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(t[keyPath: fill]) }
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(t[keyPath: border], lineWidth: 1) }
    }
}

extension View {
    /// The standard card look.
    public func cardSurface(radius: CGFloat = 16) -> some View {
        modifier(CardSurface(radius: radius, fill: \.card, border: \.cardBorder))
    }

    /// The tinted look of the hero card.
    public func heroSurface(radius: CGFloat = 20) -> some View {
        modifier(CardSurface(radius: radius, fill: \.hero, border: \.heroBorder))
    }
}

// MARK: Status ring

/// The big ring on the left of a hero card. Full ring with a symbol and a label when idle,
/// a progress arc while something is running or measured.
public struct StatusRing: View {
    @Environment(\.colorScheme) private var scheme

    private let progress: Double?
    private let symbol: String?
    private let title: String
    private let value: String?
    private let diameter: CGFloat

    /// - Parameters:
    ///   - progress: 0...1 to draw an arc, or nil for the idle full ring.
    ///   - value: a big figure shown instead of the symbol (a score, a size).
    public init(progress: Double? = nil, symbol: String? = nil, title: String, value: String? = nil, diameter: CGFloat = 156) {
        self.progress = progress
        self.symbol = symbol
        self.title = title
        self.value = value
        self.diameter = diameter
    }

    public var body: some View {
        let t = scheme.theme
        ZStack {
            Circle().stroke(t.accentSoft, lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress.map { max(0.001, min(1, $0)) } ?? 1)
                .stroke(t.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                if let value {
                    Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(t.ink)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(t.accent)
                }
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(t.ink)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value ?? ""))
    }
}

// MARK: Illustration tile

/// The rounded lavender tile on the right of a hero card: a large outline symbol, a small badge.
public struct IllustrationTile: View {
    @Environment(\.colorScheme) private var scheme
    private let symbol: String
    private let badge: String?

    public init(symbol: String, badge: String? = nil) {
        self.symbol = symbol
        self.badge = badge
    }

    public var body: some View {
        let t = scheme.theme
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark ? [Color(red: 0.24, green: 0.2, blue: 0.4), Color(red: 0.3, green: 0.24, blue: 0.5)]
                                            : [Color(red: 0.95, green: 0.93, blue: 0.99), Color(red: 0.84, green: 0.79, blue: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 130, height: 130)
                .overlay { Image(systemName: symbol).font(.system(size: 52, weight: .ultraLight)).foregroundStyle(t.accent.opacity(0.75)) }

            if let badge {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(t.card)
                    .frame(width: 40, height: 40)
                    .overlay { Image(systemName: badge).font(.system(size: 17)).foregroundStyle(t.accent) }
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .offset(x: 8, y: 8)
            }
        }
        .overlay(alignment: .topLeading) { Circle().fill(t.accent.opacity(0.35)).frame(width: 7, height: 7).offset(x: -16, y: 34) }
        .overlay(alignment: .topTrailing) { Circle().fill(t.accent.opacity(0.25)).frame(width: 5, height: 5).offset(x: 14, y: 14) }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }
}

// MARK: Hero card

public struct HeroCard<Leading: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var scheme

    private let heading: LocalizedStringResource
    private let message: LocalizedStringResource
    private let note: LocalizedStringResource?
    private let leading: Leading
    private let trailing: Trailing

    public init(
        heading: LocalizedStringResource, message: LocalizedStringResource, note: LocalizedStringResource? = nil,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.heading = heading
        self.message = message
        self.note = note
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        let t = scheme.theme
        HStack(spacing: 28) {
            leading
            Rectangle().fill(t.heroBorder).frame(width: 1, height: 130)
            VStack(alignment: .leading, spacing: 8) {
                Text(heading).font(.system(size: 21, weight: .semibold)).foregroundStyle(t.ink)
                Text(message).font(.system(size: 13)).foregroundStyle(t.inkSecondary).fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label { Text(note).font(.system(size: 12)) } icon: { Image(systemName: "info.circle").font(.system(size: 11)) }
                        .foregroundStyle(t.inkSecondary).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .heroSurface()
    }
}

// MARK: List card

public struct FeatureRow: Identifiable {
    public let id = UUID()
    public let symbol: String
    public let title: LocalizedStringResource
    public let detail: LocalizedStringResource
    public let status: LocalizedStringResource?
    public let highlightsStatus: Bool
    public let action: (() -> Void)?

    public init(
        symbol: String, title: LocalizedStringResource, detail: LocalizedStringResource,
        status: LocalizedStringResource? = nil, highlightsStatus: Bool = false, action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.status = status
        self.highlightsStatus = highlightsStatus
        self.action = action
    }
}

/// The card listing a section's capabilities, one row each, with a status on the right.
public struct FeatureListCard<Accessory: View>: View {
    @Environment(\.colorScheme) private var scheme

    private let heading: LocalizedStringResource
    private let trailingHeading: LocalizedStringResource?
    private let rows: [FeatureRow]
    private let accessory: (FeatureRow) -> Accessory

    public init(
        heading: LocalizedStringResource, trailingHeading: LocalizedStringResource? = nil, rows: [FeatureRow],
        @ViewBuilder accessory: @escaping (FeatureRow) -> Accessory
    ) {
        self.heading = heading
        self.trailingHeading = trailingHeading
        self.rows = rows
        self.accessory = accessory
    }

    public var body: some View {
        let t = scheme.theme
        VStack(spacing: 0) {
            HStack {
                Text(heading).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink)
                Spacer()
                if let trailingHeading { Text(trailingHeading).font(.system(size: 11)).foregroundStyle(t.inkTertiary) }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)

            ForEach(rows) { row in
                Divider().overlay(t.divider)
                rowView(row, t)
            }
        }
        .padding(.bottom, 4)
        .cardSurface()
    }

    @ViewBuilder
    private func rowView(_ row: FeatureRow, _ t: ThemeColors) -> some View {
        let content = HStack(spacing: 14) {
            Image(systemName: row.symbol).font(.system(size: 15)).foregroundStyle(t.inkSecondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 13, weight: .medium)).foregroundStyle(t.ink)
                Text(row.detail).font(.system(size: 11)).foregroundStyle(t.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory(row)
            if let status = row.status {
                Text(status).font(.system(size: 11, weight: row.highlightsStatus ? .medium : .regular))
                    .foregroundStyle(row.highlightsStatus ? t.accent : t.inkTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .contentShape(Rectangle())

        if let action = row.action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

extension FeatureListCard where Accessory == EmptyView {
    public init(heading: LocalizedStringResource, trailingHeading: LocalizedStringResource? = nil, rows: [FeatureRow]) {
        self.init(heading: heading, trailingHeading: trailingHeading, rows: rows) { _ in EmptyView() }
    }
}

// MARK: Info card

public struct InfoCard<Extra: View>: View {
    @Environment(\.colorScheme) private var scheme

    private let symbol: String
    private let heading: LocalizedStringResource
    private let message: LocalizedStringResource
    private let note: LocalizedStringResource?
    private let buttonTitle: LocalizedStringResource?
    private let buttonSymbol: String
    private let action: (() -> Void)?
    private let extra: Extra

    public init(
        symbol: String, heading: LocalizedStringResource, message: LocalizedStringResource, note: LocalizedStringResource? = nil,
        buttonTitle: LocalizedStringResource? = nil, buttonSymbol: String = "arrow.up.right", action: (() -> Void)? = nil,
        @ViewBuilder extra: () -> Extra
    ) {
        self.symbol = symbol
        self.heading = heading
        self.message = message
        self.note = note
        self.buttonTitle = buttonTitle
        self.buttonSymbol = buttonSymbol
        self.action = action
        self.extra = extra()
    }

    public var body: some View {
        let t = scheme.theme
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(heading).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink) }
                icon: { Image(systemName: symbol).foregroundStyle(t.accent) }
            extra
            Text(message).font(.system(size: 12)).foregroundStyle(t.inkSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(t.inkTertiary).fixedSize(horizontal: false, vertical: true)
            }
            if let buttonTitle, let action {
                Button(action: action) {
                    Label { Text(buttonTitle).font(.system(size: 12, weight: .medium)) } icon: { Image(systemName: buttonSymbol).font(.system(size: 10)) }
                        .foregroundStyle(t.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card) }
                        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.cardBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .cardSurface()
    }
}

extension InfoCard where Extra == EmptyView {
    public init(
        symbol: String, heading: LocalizedStringResource, message: LocalizedStringResource, note: LocalizedStringResource? = nil,
        buttonTitle: LocalizedStringResource? = nil, buttonSymbol: String = "arrow.up.right", action: (() -> Void)? = nil
    ) {
        self.init(symbol: symbol, heading: heading, message: message, note: note, buttonTitle: buttonTitle,
                  buttonSymbol: buttonSymbol, action: action) { EmptyView() }
    }
}

// MARK: Metric card

/// A small card for one live reading, as on the overview and Performance pages.
public struct MetricCard<Visual: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let symbol: String
    private let title: LocalizedStringResource
    private let value: String
    private let detail: LocalizedStringResource?
    private let visual: Visual

    public init(
        symbol: String, title: LocalizedStringResource, value: String, detail: LocalizedStringResource? = nil,
        @ViewBuilder visual: () -> Visual
    ) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.detail = detail
        self.visual = visual()
    }

    public var body: some View {
        let t = scheme.theme
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(title).font(.system(size: 11)).foregroundStyle(t.inkSecondary) }
                icon: { Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(t.inkSecondary) }
            Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.6)
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(t.inkTertiary) }
            visual
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .cardSurface()
    }
}

extension MetricCard where Visual == EmptyView {
    public init(symbol: String, title: LocalizedStringResource, value: String, detail: LocalizedStringResource? = nil) {
        self.init(symbol: symbol, title: title, value: value, detail: detail) { EmptyView() }
    }
}

/// A thin progress bar in the brand violet.
public struct BrandBar: View {
    @Environment(\.colorScheme) private var scheme
    private let fraction: Double

    public init(fraction: Double) { self.fraction = min(1, max(0, fraction)) }

    public var body: some View {
        let t = scheme.theme
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(t.track)
                Capsule().fill(t.accent).frame(width: max(4, proxy.size.width * fraction))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: Floating action

/// A page's primary round action, handed up to the window so it can be drawn *over the window's
/// bottom edge*, as in the design: the circle hangs out past the container, which a button inside
/// the page can never do.
public struct FloatingAction: Equatable, @unchecked Sendable {
    public let id = UUID()
    public let title: LocalizedStringResource
    /// Always run on the main actor, from a button press.
    public let perform: () -> Void

    public static func == (lhs: FloatingAction, rhs: FloatingAction) -> Bool { lhs.id == rhs.id }

    public init(title: LocalizedStringResource, perform: @escaping () -> Void) {
        self.title = title
        self.perform = perform
    }
}

public struct FloatingActionKey: PreferenceKey {
    public static let defaultValue: FloatingAction? = nil
    public static func reduce(value: inout FloatingAction?, nextValue: () -> FloatingAction?) {
        value = nextValue() ?? value
    }
}

private struct HostsFloatingActionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the window draws the floating action itself (see `FloatingActionKey`).
    public var hostsFloatingAction: Bool {
        get { self[HostsFloatingActionKey.self] }
        set { self[HostsFloatingActionKey.self] = newValue }
    }
}

/// The round primary action floating at the bottom of a page.
public struct FloatingActionButton: View {
    @Environment(\.colorScheme) private var scheme
    private let title: LocalizedStringResource
    private let action: () -> Void

    public init(title: LocalizedStringResource, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .frame(width: 156, height: 156)
                .background { Circle().fill(LinearGradient(colors: [Brand.accent.color, Brand.accentEnd.color], startPoint: .top, endPoint: .bottom)) }
                .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                // A static glow: animating a blur every frame is expensive (measured earlier).
                .shadow(color: Brand.accent.color.opacity(scheme == .dark ? 0.55 : 0.4), radius: 22, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(Strings.scanButtonHint))
    }
}

// MARK: Footer

public struct PageFooter: View {
    @Environment(\.colorScheme) private var scheme
    private let lastScan: String
    private let note: LocalizedStringResource
    private let machine: String
    private let system: String

    public init(lastScan: String, note: LocalizedStringResource, machine: String, system: String) {
        self.lastScan = lastScan
        self.note = note
        self.machine = machine
        self.system = system
    }

    public var body: some View {
        let t = scheme.theme
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lastScan).font(.system(size: 12, weight: .medium)).foregroundStyle(t.ink)
                Text(note).font(.system(size: 11)).foregroundStyle(t.inkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(machine).font(.system(size: 12, weight: .medium)).foregroundStyle(t.ink)
                Text(system).font(.system(size: 11)).foregroundStyle(t.inkSecondary)
            }
        }
    }
}

// MARK: Page

/// The common frame of a section page: title, hero, content, footer, floating action.
public struct SectionPage<Hero: View, Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.hostsFloatingAction) private var hostsFloatingAction

    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource
    private let hero: Hero
    private let content: Content
    private let footer: PageFooter?
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        title: LocalizedStringResource, subtitle: LocalizedStringResource, footer: PageFooter? = nil,
        actionTitle: LocalizedStringResource? = nil, action: (() -> Void)? = nil,
        @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.actionTitle = actionTitle
        self.action = action
        self.hero = hero()
        self.content = content()
    }

    public var body: some View {
        let t = scheme.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 30, weight: .light)).foregroundStyle(t.ink)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(t.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                hero
                content
                if let footer { footer.padding(.top, 14) }
                // Room for the floating button, which overlaps the end of the page.
                if action != nil { Color.clear.frame(height: 150) }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // Under the title bar too, so the page is one surface from edge to edge.
        .background(t.background.ignoresSafeArea())
        .preference(key: FloatingActionKey.self, value: actionTitle.flatMap { title in action.map { FloatingAction(title: title, perform: $0) } })
        .overlay(alignment: .bottom) {
            if !hostsFloatingAction, let actionTitle, let action {
                // In the design the circle straddles the bottom edge of the window: about a third of it hangs
                // past the edge. A window clips it there, which is the same picture.
                FloatingActionButton(title: actionTitle, action: action).offset(y: 50)
            }
        }
    }
}
