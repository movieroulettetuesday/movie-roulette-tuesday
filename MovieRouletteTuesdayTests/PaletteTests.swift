import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class PaletteTests: XCTestCase {
    func testKnownIdsUseThemePaletteNotCatalogColor() {
        XCTAssertEqual(CategoryPalette.hex(forCategoryId: "cat-horror", catalogHex: "#C1121F"), "#C25B5E")
        XCTAssertEqual(CategoryPalette.hex(forCategoryId: "cat-scifi"), "#4D97C2")
        let horror = RouletteCategory(id: "cat-horror", name: "Horror", colorHex: "#C1121F")
        XCTAssertEqual(horror.displayHex, "#C25B5E")
        XCTAssertEqual(Set(CategoryPalette.known.values).count, CategoryPalette.known.count, "palette colors are distinct")
    }

    func testUnknownIdMutesItsCatalogColor() {
        let hex = CategoryPalette.hex(forCategoryId: "cat-new-theme", catalogHex: "#FF0000")
        let parsed = try! XCTUnwrap(HexColor(hex))
        XCTAssertLessThanOrEqual(parsed.hsb.saturation, 0.5 + 0.01)
        XCTAssertGreaterThanOrEqual(parsed.hsb.brightness, 0.58 - 0.01)
        XCTAssertLessThanOrEqual(parsed.hsb.brightness, 0.8 + 0.01)
        XCTAssertEqual(parsed.hsb.hue, 0, accuracy: 0.01, "keeps the catalog hue")
        XCTAssertEqual(hex, CategoryPalette.hex(forCategoryId: "cat-new-theme", catalogHex: "#FF0000"), "deterministic")
        // Very dark catalog color is lifted into the band.
        let dark = try! XCTUnwrap(HexColor(CategoryPalette.hex(forCategoryId: "x", catalogHex: "#101010")))
        XCTAssertGreaterThanOrEqual(dark.hsb.brightness, 0.57)
    }

    func testUnknownIdWithoutUsableHexGetsStablePick() {
        let a = CategoryPalette.hex(forCategoryId: "cat-mystery", catalogHex: "not-a-color")
        XCTAssertTrue(CategoryPalette.fallback.contains(a))
        XCTAssertEqual(a, CategoryPalette.hex(forCategoryId: "cat-mystery", catalogHex: nil))
        XCTAssertEqual(CategoryPalette.stableIndex("cat-mystery", count: 10), CategoryPalette.stableIndex("cat-mystery", count: 10))
        let spread = Set((0..<40).map { CategoryPalette.hex(forCategoryId: "unknown-\($0)") })
        XCTAssertGreaterThan(spread.count, 4, "ids spread across the fallback palette")
        XCTAssertEqual(CategoryPalette.stableIndex("", count: 0), 0)
    }

    /// Wheel labels are bold and at least 14 pt: WCAG "large text" needs 3:1.
    /// Labels use white, or black at 85% (as `Color.labelColor` draws them).
    func testAutoLabelInkHasContrastOnEveryPaletteColor() {
        for hex in CategoryPalette.fallback + Array(CategoryPalette.known.values) {
            let bg = try! XCTUnwrap(HexColor(hex))
            let ink: HexColor = bg.prefersDarkText
                ? HexColor(red: bg.red * 0.15, green: bg.green * 0.15, blue: bg.blue * 0.15)
                : HexColor(red: 1, green: 1, blue: 1)
            XCTAssertGreaterThanOrEqual(contrastRatio(ink, bg), 3.0, "label on \(hex)")
        }
    }

    /// Every palette slice takes the black (85%) label, so the wheel's labels
    /// read as one consistent ink. Prestige was the lone white label at
    /// #7B7090 (black 4.56:1 vs white 4.60:1); #9086A1 gives black 6.11:1.
    func testEveryPaletteColorTakesDarkLabelText() {
        for hex in CategoryPalette.fallback + Array(CategoryPalette.known.values) {
            let bg = try! XCTUnwrap(HexColor(hex))
            XCTAssertTrue(bg.prefersDarkText, "\(hex) would get a white label")
        }
        XCTAssertEqual(CategoryPalette.hex(forCategoryId: "cat-prestige"), "#9086A1")
        let prestige = try! XCTUnwrap(HexColor("#9086A1"))
        XCTAssertGreaterThanOrEqual(contrastRatio(HexColor(red: 0, green: 0, blue: 0), prestige), 6.0)
        XCTAssertEqual(Set(CategoryPalette.fallback), Set(CategoryPalette.known.values), "fallback picks match the theme palette")
    }

    func testRadialStopsGoLightToDark() {
        for hex in CategoryPalette.fallback {
            let stops = CategoryPalette.radialStops(hex).compactMap(HexColor.init)
            XCTAssertEqual(stops.count, 3)
            XCTAssertGreaterThan(stops[0].relativeLuminance, stops[1].relativeLuminance)
            XCTAssertGreaterThan(stops[1].relativeLuminance, stops[2].relativeLuminance)
        }
        XCTAssertEqual(CategoryPalette.radialStops("bad"), ["bad", "bad", "bad"])
    }

    func testHSBRoundTrip() {
        for hex in ["#3A9CA6", "#F7C08A", "#000000", "#FFFFFF", "#C25B5E", "#808080"] {
            let c = try! XCTUnwrap(HexColor(hex))
            let hsb = c.hsb
            XCTAssertEqual(HexColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness).hexString, hex)
        }
        XCTAssertEqual(HexColor(hue: .nan, saturation: 2, brightness: -1).hexString, "#000000")
    }

    func testThemeTextContrast() {
        let white = HexColor(red: 1, green: 1, blue: 1)
        // SPIN label (bold title3 = large text) on the gradient's middle stop.
        XCTAssertGreaterThanOrEqual(contrastRatio(white, HexColor(CleanProColors.spinLabelStop)!), 3.0)
        // Small headings on the backgrounds: 4.5:1.
        for bg in CleanProColors.backgroundLight {
            XCTAssertGreaterThanOrEqual(contrastRatio(HexColor(CleanProColors.headingLight)!, HexColor(bg)!), 4.5)
        }
        for bg in CleanProColors.backgroundDark {
            XCTAssertGreaterThanOrEqual(contrastRatio(HexColor(CleanProColors.headingDark)!, HexColor(bg)!), 4.5)
        }
    }
}
