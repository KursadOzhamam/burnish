import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Section palettes")
struct PaletteTests {
    @Test("Every section shares the one brand violet of the supplied design")
    func oneBrandIdentity() {
        let pairs = Set(AppSection.allCases.map(\.palette))
        #expect(pairs.count == 1)
        #expect(pairs.first == Brand.pair)
    }

    @Test("Every section has a non-empty SF Symbol for the sidebar")
    func symbolsArePresent() {
        for section in AppSection.allCases {
            #expect(!section.symbol.isEmpty)
        }
    }

    @Test("Gradients have two different stops, so none renders as a flat fill")
    func gradientsActuallyGradate() {
        for section in AppSection.allCases {
            #expect(section.palette.start != section.palette.end, "\(section) is flat")
            #expect(
                section.textSafePalette.start != section.textSafePalette.end,
                "\(section) text-safe pair is flat"
            )
        }
    }

    @Test("Raw values are stable, because settings and history persist them")
    func rawValuesAreStable() {
        #expect(AppSection.dashboard.rawValue == "dashboard")
        #expect(AppSection.smartScan.rawValue == "smartScan")
        #expect(AppSection.allCases.count == 8)
    }
}

/// The guardrail for CLAUDE.md §5.3's WCAG AA requirement.
///
/// These tests exist because the decorative palette does *not* meet AA — that is deliberate, and
/// the point is to prove the split holds. If someone later brightens a text-safe pair or points a
/// filled control at a decorative one, this suite fails instead of shipping unreadable text.
@Suite("Palette contrast")
struct PaletteContrastTests {
    @Test("Text-safe gradients clear WCAG AA at both stops",
          arguments: AppSection.allCases)
    func textSafeMeetsAA(section: AppSection) {
        let ratio = section.textSafePalette.minimumContrastRatio(against: Palette.onColor)
        #expect(
            ratio >= Palette.minimumContrast,
            "\(section) text-safe pair is \(String(format: "%.2f", ratio)):1, below AA"
        )
    }

    @Test("The accent is legible as text on the light and dark surfaces")
    func accentOnSurfaces() {
        #expect(Brand.accent.contrastRatio(against: RGB(hex: 0xFFFFFF)) >= 4.5)
        #expect(Brand.accentOnDark.contrastRatio(against: RGB(hex: 0x1C1E28)) >= 4.5)
    }

    @Test("Ink is legible on every surface in both appearances")
    func inkOnSurfaces() {
        #expect(RGB(hex: 0x23232F).contrastRatio(against: RGB(hex: 0xFFFFFF)) >= 7)
        #expect(RGB(hex: 0x6E6E7C).contrastRatio(against: RGB(hex: 0xFFFFFF)) >= 4.5)
        #expect(RGB(hex: 0xF3F3F8).contrastRatio(against: RGB(hex: 0x1C1E28)) >= 7)
        #expect(RGB(hex: 0xA3A5B4).contrastRatio(against: RGB(hex: 0x1C1E28)) >= 4.5)
    }

    @Test("Brand ink is legible on a light surface")
    func inkIsLegibleOnLight() {
        let ratio = Palette.ink.contrastRatio(against: RGB(hex: 0xFFFFFF))
        #expect(ratio >= Palette.minimumContrast)
    }

    @Test("Danger colour is reserved and legible — §10.3 limits it to real threats")
    func dangerIsLegible() {
        #expect(Semantic.danger.contrastRatio(against: Palette.onColor) >= 3.0)
    }
}
