import XCTest
import SwiftUI
import UIKit
@testable import MovieRouletteTuesday

/// Reveal sheet layout at the iPhone's 0.65 detent (1.0.1): with the catalog's longest
/// titles (and their equally long "Discussed on …" lines) Spin again, Share and Movie page
/// must stay fully on screen — scrolling only when the content doesn't fit.
/// Presents the real sheet (SwiftUI `.sheet`, the reveal's own detents) in a sized
/// compact or regular window.
@MainActor
final class RevealSheetLayoutTests: XCTestCase {
    /// (id, title, year, genre, season, episode) from movies.json / the feed.
    private static let longTitles: [(String, String, Int, String, Int, Int)] = [
        ("the-unbearable-weight-of-massive-talent-2022", "The Unbearable Weight of Massive Talent", 2022, "Comedy", 1, 2),
        ("master-and-commander-the-far-side-of-the-world-2003", "Master and Commander: The Far Side of the World", 2003, "Drama", 4, 12),
        ("the-adventures-of-buckaroo-banzai-across-the-8th-dimension-1984",
         "The Adventures of Buckaroo Banzai Across the 8th Dimension", 1984, "Sci-Fi", 5, 1),
    ]

    private func reveal(_ c: (String, String, Int, String, Int, Int), jackpot: Bool)
        -> (RouletteViewModel.Reveal, [String: PodcastEpisode]) {
        let guid = "Buzzsprout-test-\(c.0)"
        let movie = Movie(id: c.0, title: c.1, year: c.2, genre: c.3, categories: ["cat-cult-classics"],
                          episodeIds: [guid], episodeTitle: c.1)
        let episode = PodcastEpisode(guid: guid, title: c.1, season: c.4, episode: c.5)
        let reveal = RouletteViewModel.Reveal(
            id: UUID(), movie: movie,
            category: RouletteCategory(id: "cat-cult", name: "Dark Comedy", colorHex: "#2A9D8F"),
            spinCount: 1, isJackpot: jackpot)
        return (reveal, [guid: episode])
    }

    private struct Presented {
        let window: UIWindow
        let sheet: UIViewController
        let sheetTop: CGFloat
        /// Bottom of the action row (content height minus the 24 pt padding), window coordinates.
        /// nil when ViewThatFits chose the non-scrolling branch (content fits).
        let actionsBottom: CGFloat?
        let visibleBottom: CGFloat
        let hasOverflowScroll: Bool
        let contentHeight: CGFloat
        let scrollBoundsHeight: CGFloat
    }

    private func present(_ c: (String, String, Int, String, Int, Int), jackpot: Bool,
                         windowSize: CGSize = CGSize(width: 402, height: 874),
                         contentSize: UIContentSizeCategory? = nil,
                         regularWidth: Bool = false,
                         scrollToBottom: Bool = false) throws -> Presented {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                  "unit tests run hosted in the app")
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: windowSize)
        let (reveal, episodes) = reveal(c, jackpot: jackpot)
        let root = Color.clear.sheet(isPresented: .constant(true)) {
            RevealSheet(reveal: reveal, catalog: nil, episodesByGUID: episodes,
                        onSpinAgain: {}, presenterIsRegularWidth: regularWidth)
                .environment(PersonalRatingsStore(fileStore: nil))
                .environment(SpinHistoryStore(fileStore: nil))
                .environment(CommunityService.preview())
        }
        let host = UIHostingController(rootView: root)
        host.traitOverrides.horizontalSizeClass = regularWidth ? .regular : .compact
        if let contentSize {
            host.traitOverrides.preferredContentSizeCategory = contentSize
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<80 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let sheet = host.presentedViewController, !sheet.isBeingPresented { break }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // settle (share image, detent)
        let sheet = try XCTUnwrap(host.presentedViewController, "reveal sheet presented")
        sheet.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        sheet.view.layoutIfNeeded()

        let sheetFrame = sheet.view.convert(sheet.view.bounds, to: nil)
        let visibleBottom = sheetFrame.maxY - sheet.view.safeAreaInsets.bottom

        let scroll = Self.overflowScrollView(in: sheet.view)
        var actionsBottom: CGFloat?
        var contentHeight: CGFloat = 0
        var scrollBoundsHeight: CGFloat = 0
        var overflow = false
        if let scroll {
            contentHeight = scroll.contentSize.height
            scrollBoundsHeight = scroll.bounds.height
            overflow = contentHeight > scrollBoundsHeight + 1
            if overflow, scrollToBottom {
                let bottom = CGRect(x: 0, y: max(0, contentHeight - 8),
                                    width: max(scroll.bounds.width, 1), height: 8)
                scroll.scrollRectToVisible(bottom.insetBy(dx: 0, dy: -24), animated: false)
                sheet.view.layoutIfNeeded()
            }
            // The action row is the last thing in the scroll content, above its .padding(24).
            actionsBottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: nil).y - 24
        }
        return Presented(window: window, sheet: sheet,
                         sheetTop: sheetFrame.minY,
                         actionsBottom: actionsBottom,
                         visibleBottom: visibleBottom,
                         hasOverflowScroll: overflow,
                         contentHeight: contentHeight,
                         scrollBoundsHeight: scrollBoundsHeight)
    }

    /// A scroll view whose content is taller than its bounds — the ViewThatFits
    /// fallback. Navigation-bar collapse scrolls (content ≈ bounds) are ignored.
    private static func overflowScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ v: UIView) {
            if let s = v as? UIScrollView, s.contentSize.height > (best?.contentSize.height ?? 0) {
                best = s
            }
            v.subviews.forEach(visit)
        }
        visit(root)
        return best
    }

    private func assertButtonsOnScreen(jackpot: Bool,
                                       windowSize: CGSize = CGSize(width: 402, height: 874),
                                       contentSize: UIContentSizeCategory? = nil,
                                       regularWidth: Bool = false,
                                       allowScroll: Bool = false,
                                       expectPartialDetent: Bool = true,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        for c in Self.longTitles {
            let p = try present(c, jackpot: jackpot, windowSize: windowSize,
                                contentSize: contentSize, regularWidth: regularWidth,
                                scrollToBottom: allowScroll)
            defer { p.window.rootViewController?.dismiss(animated: false); p.window.isHidden = true }
            let tag = "\(c.1) (jackpot \(jackpot), size \(windowSize), AX \(contentSize?.rawValue ?? "default"))"
            print("MRT-LAYOUT \(tag) sheetTop=\(p.sheetTop) actionsBottom=\(String(describing: p.actionsBottom)) visibleBottom=\(p.visibleBottom) overflow=\(p.hasOverflowScroll) contentH=\(p.contentHeight) scrollH=\(p.scrollBoundsHeight)")
            if expectPartialDetent {
                XCTAssertGreaterThan(p.sheetTop, windowSize.height * 0.25, "sheet at the 0.65 detent: \(tag)", file: file, line: line)
            }
            if p.hasOverflowScroll {
                XCTAssertTrue(allowScroll, "content overflowed but this size is expected to fit without scrolling: \(tag)", file: file, line: line)
                let actions = try XCTUnwrap(p.actionsBottom, "overflow scroll has a measurable content bottom: \(tag)", file: file, line: line)
                XCTAssertLessThanOrEqual(actions, p.visibleBottom + 1.5,
                                         "Share and Movie page fully on screen after scroll: \(tag)", file: file, line: line)
            }
            // Non-overflow: ViewThatFits chose the non-scrolling branch, so the
            // content fits the detent and the action row is on screen by construction.
        }
    }

    func testLongTitlesKeepActionsOnScreenAtPartialDetent() throws {
        try assertButtonsOnScreen(jackpot: false)
    }

    func testLongTitlesKeepActionsOnScreenAtPartialDetentJackpot() throws {
        try assertButtonsOnScreen(jackpot: true)
    }

    /// Longest titles at accessibility XXXL on the smallest current iPhone (SE, 375×667).
    /// Content may overflow the 0.65 detent; the sheet must scroll so the action row fits.
    func testLongTitleButtonsFitOrScrollAtAccessibilityXXXLOnSE() throws {
        try assertButtonsOnScreen(jackpot: false,
                                  windowSize: CGSize(width: 375, height: 667),
                                  contentSize: .accessibilityExtraExtraExtraLarge,
                                  allowScroll: true)
        try assertButtonsOnScreen(jackpot: true,
                                  windowSize: CGSize(width: 375, height: 667),
                                  contentSize: .accessibilityExtraExtraExtraLarge,
                                  allowScroll: true)
    }

    /// iPhone 18 Pro at the Large (non-accessibility) Dynamic Type size: still a partial detent.
    func testLongTitleButtonsOnIPhone18ProAtLargeText() throws {
        try assertButtonsOnScreen(jackpot: false,
                                  windowSize: CGSize(width: 402, height: 874),
                                  contentSize: .extraLarge,
                                  allowScroll: true)
    }

    /// iPad large sheet: buttons on screen with three-line titles.
    func testLongTitleButtonsOnIPadLargeSheet() throws {
        try assertButtonsOnScreen(jackpot: false,
                                  windowSize: CGSize(width: 1024, height: 1366),
                                  regularWidth: true,
                                  allowScroll: true,
                                  expectPartialDetent: false)
    }
}
