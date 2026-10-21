import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class AdaptiveLayoutTests: XCTestCase {
    private func fits(_ d: Double, slotHeight h: Double, hintHeight: Double = 0,
                      file: StaticString = #filePath, line: UInt = #line) {
        let hint = hintHeight > 0 ? hintHeight + RouletteLayout.hintSpacing : 0
        let needed = RouletteLayout.wheelFrameHeight(forDiameter: d) + RouletteLayout.shadowAllowance + RouletteLayout.topGap + hint
        XCTAssertLessThanOrEqual(needed, h + 0.001, "wheel + pointer + shadow must fit the slot", file: file, line: line)
    }

    func testIPhonePortraitFillsWidthWithSideMargins() {
        // iPhone 17/18 Pro: 402 pt wide, tall slot -> width-limited, 10 pt margins (~95%).
        let d = RouletteLayout.wheelDiameter(slotWidth: 402, slotHeight: 520, arrangement: .stacked, isRegularWidth: false)
        XCTAssertEqual(d, 382, accuracy: 0.001)
        XCTAssertGreaterThan(d / 402, 0.94)
        XCTAssertEqual(RouletteLayout.make(width: 402, height: 760, isRegularWidth: false).arrangement, .stacked)
        // Pro Max class.
        XCTAssertEqual(RouletteLayout.wheelDiameter(slotWidth: 440, slotHeight: 600, arrangement: .stacked, isRegularWidth: false), 420, accuracy: 0.001)
    }

    func testShortSlotsCapByHeight() {
        // iPhone SE / mini or large Dynamic Type: the header and hint leave a short slot.
        for h in [250.0, 300, 340] {
            let d = RouletteLayout.wheelDiameter(slotWidth: 375, slotHeight: h, arrangement: .stacked, isRegularWidth: false)
            XCTAssertLessThan(d, 375 - 2 * RouletteLayout.compactSideMargin)
            fits(d, slotHeight: h)
        }
        // A shrinking slot never grows the wheel.
        var last = Double.infinity
        for h in stride(from: 600.0, through: 200, by: -20) {
            let d = RouletteLayout.wheelDiameter(slotWidth: 402, slotHeight: h, arrangement: .stacked, isRegularWidth: false)
            XCTAssertLessThanOrEqual(d, last); last = d
        }
    }

    func testHintUnderTheWheelIsReserved() {
        // B2: "Tap to spin" sits under the wheel inside the slot; its height
        // (+ spacing) comes off the slot, so a short slot shrinks the wheel...
        // (Height-limited slot; the pointer shrinks a little with the wheel, so
        // slightly less than the full 32 pt comes off the diameter.)
        let noHint = RouletteLayout.wheelDiameter(slotWidth: 375, slotHeight: 340, arrangement: .stacked, isRegularWidth: false)
        let hint = RouletteLayout.wheelDiameter(slotWidth: 375, slotHeight: 340, arrangement: .stacked,
                                               isRegularWidth: false, hintHeight: 18)
        XCTAssertEqual(noHint - hint, 18 + RouletteLayout.hintSpacing, accuracy: 2.5)
        fits(hint, slotHeight: 340, hintHeight: 18)
        // ...a tall one doesn't, and accessibility-size hints (2 lines) still fit.
        XCTAssertEqual(RouletteLayout.wheelDiameter(slotWidth: 402, slotHeight: 600, arrangement: .stacked,
                                                    isRegularWidth: false, hintHeight: 18), 382, accuracy: 0.001)
        let ax = RouletteLayout.wheelDiameter(slotWidth: 375, slotHeight: 330, arrangement: .stacked,
                                             isRegularWidth: false, hintHeight: 70)
        fits(ax, slotHeight: 330, hintHeight: 70)
        // Degenerate hint heights are ignored rather than poisoning the size.
        for bad in [Double.nan, -40, .infinity] {
            let d = RouletteLayout.wheelDiameter(slotWidth: 402, slotHeight: 600, arrangement: .stacked,
                                                isRegularWidth: false, hintHeight: bad)
            XCTAssertTrue(d.isFinite); XCTAssertGreaterThanOrEqual(d, RouletteLayout.minimumDiameter)
        }
    }

    func testPointerScalesWithWheel() {
        let old = RouletteLayout.pointerSize(forDiameter: 289)
        XCTAssertEqual(old.width, 28, accuracy: 0.6)
        let big = RouletteLayout.pointerSize(forDiameter: 366)
        XCTAssertEqual(big.width, 366 * 0.085, accuracy: 0.001)
        XCTAssertEqual(big.height / big.width, 34.0 / 28.0, accuracy: 0.001)
        XCTAssertEqual(RouletteLayout.pointerSize(forDiameter: 2_000).width, 56)
    }

    func testIPadPortraitIsStackedAndGrows() {
        XCTAssertEqual(RouletteLayout.make(width: 1_032, height: 1_250, isRegularWidth: true).arrangement, .stacked)
        let d = RouletteLayout.wheelDiameter(slotWidth: 1_032, slotHeight: 1_000, arrangement: .stacked, isRegularWidth: true)
        XCTAssertEqual(d, RouletteLayout.regularStackedCap)   // 84% of 1032 = 867 -> capped
        let mini = RouletteLayout.wheelDiameter(slotWidth: 744, slotHeight: 800, arrangement: .stacked, isRegularWidth: true)
        XCTAssertEqual(mini, 744 * 0.84, accuracy: 0.001)
        fits(mini, slotHeight: 800)
    }

    func testIPadLandscapeIsSideBySideAndFillsPane() {
        XCTAssertEqual(RouletteLayout.make(width: 1_376, height: 900, isRegularWidth: true).arrangement, .sideBySide)
        XCTAssertEqual(RouletteLayout.sideBySideControlsWidth(forWidth: 1_376), 360)
        // Pane 1376 - 80 - 40 - 360 = 896 wide, ~870 tall -> height-limited.
        let d = RouletteLayout.wheelDiameter(slotWidth: 896, slotHeight: 870, arrangement: .sideBySide, isRegularWidth: true)
        XCTAssertGreaterThan(d, 780)
        fits(d, slotHeight: 870)
        // Wide but short pane: height decides.
        let short = RouletteLayout.wheelDiameter(slotWidth: 700, slotHeight: 500, arrangement: .sideBySide, isRegularWidth: true)
        fits(short, slotHeight: 500)
        XCTAssertLessThan(short, 470)
    }

    func testNarrowIPadWindowsFallBackToIPhoneLayout() {
        // Slide Over / 1/3 Split View report compact width.
        XCTAssertEqual(RouletteLayout.make(width: 320, height: 1_000, isRegularWidth: false).arrangement, .stacked)
        let slideOver = RouletteLayout.wheelDiameter(slotWidth: 320, slotHeight: 800, arrangement: .stacked, isRegularWidth: false)
        XCTAssertEqual(slideOver, 300, accuracy: 0.001)
        // Compact but very wide (big Split View half) is capped.
        XCTAssertEqual(RouletteLayout.wheelDiameter(slotWidth: 700, slotHeight: 1_200, arrangement: .stacked, isRegularWidth: false), RouletteLayout.compactCap)
        // Regular but not wide enough for two columns.
        XCTAssertEqual(RouletteLayout.make(width: 690, height: 500, isRegularWidth: true).arrangement, .stacked)
        // Never side by side in compact width, however wide.
        XCTAssertEqual(RouletteLayout.make(width: 1_400, height: 600, isRegularWidth: false).arrangement, .stacked)
        // Narrowest side-by-side window keeps a usable controls column.
        XCTAssertEqual(RouletteLayout.sideBySideControlsWidth(forWidth: 700), 240)
    }

    func testDegenerateSizesNeverProduceBadDiameters() {
        let sizes: [(Double, Double)] = [(0, 0), (-10, 50), (.nan, 400), (.infinity, .infinity), (100, 100), (400, .nan)]
        for (w, h) in sizes {
            _ = RouletteLayout.make(width: w, height: h, isRegularWidth: true)
            for arrangement in [RouletteLayout.Arrangement.stacked, .sideBySide] {
                for regular in [false, true] {
                    let d = RouletteLayout.wheelDiameter(slotWidth: w, slotHeight: h, arrangement: arrangement, isRegularWidth: regular)
                    XCTAssertTrue(d.isFinite)
                    XCTAssertGreaterThanOrEqual(d, RouletteLayout.minimumDiameter)
                    XCTAssertLessThanOrEqual(d, RouletteLayout.sideBySideCap)
                }
            }
        }
    }

    func testStatsColumns() {
        XCTAssertEqual(StatsGridLayout.columnCount(forWidth: 1_366, isRegularWidth: false), 1)
        XCTAssertEqual(StatsGridLayout.columnCount(forWidth: 600, isRegularWidth: true), 1)
        XCTAssertEqual(StatsGridLayout.columnCount(forWidth: 820, isRegularWidth: true), 2)
        XCTAssertEqual(StatsGridLayout.columnCount(forWidth: 1_366, isRegularWidth: true), 3)
        XCTAssertEqual(StatsGridLayout.columnCount(forWidth: .nan, isRegularWidth: true), 1)
    }

    func testConfettiScale() {
        XCTAssertEqual(ConfettiScale.particleCount(forWidth: 393), 60)
        XCTAssertEqual(ConfettiScale.particleCount(forWidth: 860), 120)
        XCTAssertEqual(ConfettiScale.particleCount(forWidth: 5_000), 150)
        XCTAssertEqual(ConfettiScale.particleCount(forWidth: 0), 60)
        XCTAssertEqual(ConfettiScale.pieceScale(forWidth: 393), 1)
        XCTAssertEqual(ConfettiScale.pieceScale(forWidth: 5_000), 1.6)
    }

    func testDeepLinks() throws {
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/the-room-2003"))), .movie(id: "the-room-2003"))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "MRT://Movie/the-room-2003"))), .movie(id: "the-room-2003"))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt:///movie/x"))), .movie(id: "x"))
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/"))))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://episode/abc"))), .episode(guid: "abc"))
        XCTAssertEqual(DeepLink(url: DeepLink.episode(guid: "Buzzsprout-19913482").url), .episode(guid: "Buzzsprout-19913482"))
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://stats/abc"))))
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/a/b"))))
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "https://movie/abc"))))
        // Round trip, including ids that need escaping.
        for id in ["the-room-2003", "weird id/with?chars"] {
            XCTAssertEqual(DeepLink(url: DeepLink.movie(id: id).url), .movie(id: id))
        }
    }

    /// TestFlight bug: the movie page reached from the wheel's reveal sheet had a
    /// dead Episodes row. Every entry point that can push an episode must link it.
    func testMoviePageEpisodeLinksSameOnEveryPath() {
        XCTAssertTrue(MoviePageContext.wheelReveal.linksEpisodes, "wheel reveal -> Movie Page")
        XCTAssertTrue(MoviePageContext.moviesTab.linksEpisodes, "Movies tab")
        XCTAssertTrue(MoviePageContext.spinHistory.linksEpisodes, "Spin History")
        XCTAssertEqual(MoviePageContext.wheelReveal.linksEpisodes, MoviePageContext.moviesTab.linksEpisodes)
        XCTAssertFalse(MoviePageContext.episodeDetail.linksEpisodes, "film card inside an episode page")
        XCTAssertEqual(MoviePageContext.allCases.filter(\.linksEpisodes).count, 3)
    }
}
