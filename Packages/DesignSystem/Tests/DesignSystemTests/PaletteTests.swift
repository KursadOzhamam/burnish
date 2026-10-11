import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Section palettes")
struct PaletteTests {
    @Test("Every section has its own gradient — §5.3 gives each area a distinct identity")
    func gradientsAreDistinct() {
        let pairs = AppSection.allCases.map(\.palette)
        #expect(Set(pairs).count == AppSection.allCases.count)
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

    @Test("Text-safe pairs keep the hue family of their decorative pair")
    func textSafeStaysOnBrand() {
        // A darkened variant must not be brighter than the vivid one it derives from.
        for section in AppSection.allCases {
            #expect(section.textSafePalette.start.luminance <= section.palette.start.luminance + 0.001)
            #expect(section.textSafePalette.end.luminance <= section.palette.end.luminance + 0.001)
        }
    }

    @Test("The decorative palette is documented as failing AA, not accidentally passing")
    func decorativePaletteIsKnownToFailAA() {
        // Recorded so the split stays intentional: if every decorative pair ever did pass AA,
        // textSafePalette would be redundant and should be removed rather than left to rot.
        let failing = AppSection.allCases.filter {
            $0.palette.minimumContrastRatio(against: Palette.onColor) < Palette.minimumContrast
        }
        #expect(failing.count == 6, "expected 6 decorative pairs below AA, found \(failing.count)")
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
