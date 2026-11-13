import XCTest
@testable import MovieRouletteTuesday

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
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://spin"))), .spin)
        XCTAssertEqual(DeepLink(url: DeepLink.spin.url), .spin)
        XCTAssertEqual(DeepLink(url: DeepLink.episodes.url), .episodes)
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://spin/extra"))))
        // Round trip, including ids that need escaping.
        for id in ["the-room-2003", "weird id/with?chars"] {
            XCTAssertEqual(DeepLink(url: DeepLink.movie(id: id).url), .movie(id: id))
        }
    }

    func testNoActiveHingeLeavesTheWheelWhereItWas() {
        let slot = LayoutRect(x: 0, y: 0, width: 402, height: 700)
        let hub = RouletteLayout.hubFrame(slotWidth: 402, slotHeight: 700, diameter: 382, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 402, slotHeight: 700, diameter: 382, hintHeight: 18)
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: []),
            .zero
        )
        let missing = LayoutRect(x: .nan, y: 0, width: 40, height: 700)
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [missing]),
            .zero
        )
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: LayoutRect(x: 0, y: 0, width: 0, height: 700), divisions: [slot]),
            .zero
        )
    }

    func testVerticalHingeMovesTheHubOntoTheLargerSide() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        // Right of center, overlapping the hub, with more room on the left.
        let band = LayoutRect(x: 420, y: -10, width: 30, height: 1_200)
        XCTAssertTrue(hub.intersects(band))
        let shift = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band])
        XCTAssertEqual(shift.y, 0, accuracy: 0.001)
        XCTAssertEqual(shift.x, band.minX - hub.maxX, accuracy: 0.001)
        XCTAssertLessThan(shift.x, 0)
        let moved = hub.offsetBy(dx: shift.x, dy: shift.y)
        XCTAssertFalse(moved.intersects(band))
        XCTAssertGreaterThanOrEqual(moved.minX, slot.minX - 0.5)
        XCTAssertLessThanOrEqual(moved.maxX, slot.maxX + 0.5)
        let wheelMoved = wheel.offsetBy(dx: shift.x, dy: shift.y)
        XCTAssertGreaterThanOrEqual(wheelMoved.minX, slot.minX - 0.5)
        XCTAssertLessThanOrEqual(wheelMoved.maxX, slot.maxX + 0.5)
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: moved, wheel: wheelMoved, slot: slot, divisions: [band]),
            .zero,
            "a later layout pass must not walk the wheel again"
        )
    }

    func testEqualPanesPreferThePositiveSide() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let band = LayoutRect(x: 390, y: 0, width: 20, height: 1_000)
        let left = band.minX - slot.minX
        let right = slot.maxX - band.maxX
        XCTAssertEqual(left, right, accuracy: 0.001)
        XCTAssertTrue(hub.intersects(band))
        let shift = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band])
        XCTAssertEqual(shift.x, band.maxX - hub.minX, accuracy: 0.001)
        XCTAssertEqual(shift.y, 0, accuracy: 0.001)
        XCTAssertFalse(hub.offsetBy(dx: shift.x, dy: 0).intersects(band))
    }

    func testHorizontalHingeMovesVertically() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let band = LayoutRect(x: 0, y: hub.y + hub.height / 2, width: 800, height: 28)
        XCTAssertTrue(hub.intersects(band))
        XCTAssertGreaterThan(band.minY - slot.minY, slot.maxY - band.maxY)
        let shift = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band])
        XCTAssertEqual(shift.x, 0, accuracy: 0.001)
        XCTAssertEqual(shift.y, band.minY - hub.maxY, accuracy: 0.001)
        XCTAssertFalse(hub.offsetBy(dx: 0, dy: shift.y).intersects(band))
    }

    func testFoldAndUnfoldIsJustTheCurrentDivisionList() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let open = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [])
        XCTAssertEqual(open, .zero)
        // Wide enough to cover the hub both before and after the slot grows.
        let band = LayoutRect(x: 380, y: 0, width: 200, height: 1_000)
        let folded = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band])
        XCTAssertNotEqual(folded, .zero)
        XCTAssertFalse(hub.offsetBy(dx: folded.x, dy: folded.y).intersects(band))
        let wider = LayoutRect(x: 0, y: 0, width: 1_100, height: 900)
        let widerHub = RouletteLayout.hubFrame(slotWidth: 1_100, slotHeight: 900, diameter: 500, hintHeight: 18)
        let widerWheel = RouletteLayout.wheelFrame(slotWidth: 1_100, slotHeight: 900, diameter: 500, hintHeight: 18)
        XCTAssertTrue(widerHub.intersects(band))
        let resized = RouletteLayout.hingeClearanceOffset(hub: widerHub, wheel: widerWheel, slot: wider, divisions: [band])
        XCTAssertNotEqual(resized, folded)
        XCTAssertFalse(widerHub.offsetBy(dx: resized.x, dy: resized.y).intersects(band))
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: []),
            .zero
        )
    }

    func testHubClearsWhenTheWheelCannotStayInTheSlot() {
        let slot = LayoutRect(x: 0, y: 0, width: 402, height: 700)
        let diameter = 382.0
        let hub = RouletteLayout.hubFrame(slotWidth: 402, slotHeight: 700, diameter: diameter, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 402, slotHeight: 700, diameter: diameter, hintHeight: 18)
        let band = LayoutRect(x: (402 - 36) / 2, y: 0, width: 36, height: 700)
        XCTAssertTrue(hub.intersects(band))
        let shift = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band])
        let movedHub = hub.offsetBy(dx: shift.x, dy: shift.y)
        let movedWheel = wheel.offsetBy(dx: shift.x, dy: shift.y)
        XCTAssertFalse(movedHub.intersects(band))
        XCTAssertGreaterThanOrEqual(movedHub.minX, slot.minX - 0.5)
        XCTAssertLessThanOrEqual(movedHub.maxX, slot.maxX + 0.5)
        XCTAssertGreaterThan(movedWheel.maxX, slot.maxX)
    }

    func testBookAndTabletopBandsBothClear() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let vertical = LayoutRect(x: 420, y: 0, width: 30, height: 1_000)
        let horizontal = LayoutRect(x: 0, y: hub.y + hub.height / 2, width: 800, height: 28)
        XCTAssertTrue(hub.intersects(vertical))
        XCTAssertTrue(hub.intersects(horizontal))
        let shift = RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [horizontal, vertical])
        let moved = hub.offsetBy(dx: shift.x, dy: shift.y)
        XCTAssertEqual(shift.x, vertical.minX - hub.maxX, accuracy: 0.001)
        XCTAssertEqual(shift.y, horizontal.minY - hub.maxY, accuracy: 0.001)
        XCTAssertFalse(moved.intersects(vertical))
        XCTAssertFalse(moved.intersects(horizontal))
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: moved, wheel: wheel.offsetBy(dx: shift.x, dy: shift.y), slot: slot, divisions: [vertical, horizontal]),
            .zero
        )
    }

    func testABandThatMissesTheHubDoesNotMoveTheWheel() {
        let slot = LayoutRect(x: 0, y: 0, width: 800, height: 1_000)
        let hub = RouletteLayout.hubFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let wheel = RouletteLayout.wheelFrame(slotWidth: 800, slotHeight: 1_000, diameter: 400, hintHeight: 18)
        let band = LayoutRect(x: wheel.minX - 4, y: 0, width: 12, height: 1_000)
        XCTAssertTrue(wheel.intersects(band))
        XCTAssertFalse(hub.intersects(band))
        XCTAssertEqual(
            RouletteLayout.hingeClearanceOffset(hub: hub, wheel: wheel, slot: slot, divisions: [band]),
            .zero
        )
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

    func testHubHitAreaIsAtLeast44AtMinimumDiameter() {
        let minD = RouletteLayout.minimumDiameter
        XCTAssertEqual(minD, 120, "backlog item 4 is based on this constant")
        let visual = RouletteLayout.hubVisualDiameter(forWheelDiameter: minD)
        XCTAssertEqual(visual, minD * RouletteLayout.hubDiameterFraction, accuracy: 0.001)
        XCTAssertEqual(visual, 27.6, accuracy: 0.001)
        XCTAssertLessThan(visual, 44, "the visual disc is allowed to shrink; the hit area is not")
        let hit = RouletteLayout.hubHitSize(forWheelDiameter: minD)
        XCTAssertEqual(hit, 44, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(hit, RouletteLayout.minimumHubHitSize)

        // Just under the 44 pt visual threshold (~191.3 pt wheel): still clamped.
        let under = 44.0 / RouletteLayout.hubDiameterFraction - 1
        XCTAssertLessThan(RouletteLayout.hubVisualDiameter(forWheelDiameter: under), 44)
        XCTAssertEqual(RouletteLayout.hubHitSize(forWheelDiameter: under), 44, accuracy: 0.001)

        // At and above the threshold the hit area matches the visual disc.
        let at = 44.0 / RouletteLayout.hubDiameterFraction
        XCTAssertEqual(RouletteLayout.hubVisualDiameter(forWheelDiameter: at), 44, accuracy: 0.001)
        XCTAssertEqual(RouletteLayout.hubHitSize(forWheelDiameter: at), 44, accuracy: 0.001)
        let comfortable = 382.0 // iPhone 18 Pro portrait
        XCTAssertEqual(RouletteLayout.hubHitSize(forWheelDiameter: comfortable),
                       RouletteLayout.hubVisualDiameter(forWheelDiameter: comfortable), accuracy: 0.001)
        XCTAssertGreaterThan(RouletteLayout.hubHitSize(forWheelDiameter: comfortable), 44)

        // Degenerate diameters don't go below the minimum hit size.
        for bad in [Double.nan, -40, 0, .infinity] {
            XCTAssertEqual(RouletteLayout.hubHitSize(forWheelDiameter: bad), 44, accuracy: 0.001)
        }
    }
}
