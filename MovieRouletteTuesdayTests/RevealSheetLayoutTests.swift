import XCTest
import SwiftUI
import UIKit
@testable import MovieRouletteTuesday
import MRTCore
import MRTShared

/// Reveal sheet layout at the iPhone's 0.65 detent (1.0.1): with the catalog's longest
/// titles (and their equally long "Discussed on …" lines) Spin again, Share and Movie page
/// must stay fully on screen. Presents the real sheet (SwiftUI `.sheet`, the reveal's own
/// detents) in an iPhone 18 Pro sized compact window and checks where its scroll content ends.
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
        let sheetTop: CGFloat
        let actionsBottom: CGFloat   // bottom of the Share / Movie page row, window coordinates
        let visibleBottom: CGFloat   // bottom of the sheet's scroll view above the home indicator
    }

    private func present(_ c: (String, String, Int, String, Int, Int), jackpot: Bool) throws -> Presented {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                  "unit tests run hosted in the app")
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)   // iPhone 18 Pro, points
        let (reveal, episodes) = reveal(c, jackpot: jackpot)
        let root = Color.clear.sheet(isPresented: .constant(true)) {
            RevealSheet(reveal: reveal, catalog: nil, episodesByGUID: episodes, onSpinAgain: {})
                .environment(PersonalRatingsStore(fileStore: nil))
                .environment(SpinHistoryStore(fileStore: nil))
                .environment(CommunityService.preview())
        }
        let host = UIHostingController(rootView: root)
        host.traitOverrides.horizontalSizeClass = .compact   // iPhone sheet (detents) on the iPad suite too
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<80 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let sheet = host.presentedViewController, !sheet.isBeingPresented,
               Self.scrollView(in: sheet.view) != nil { break }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // settle (share image, detent)
        let sheet = try XCTUnwrap(host.presentedViewController, "reveal sheet presented")
        sheet.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(Self.scrollView(in: sheet.view), "reveal content scroll view")
        // The action row is the last thing in the scroll content, above its .padding(24).
        let contentBottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: nil).y
        let scrollFrame = scroll.convert(scroll.bounds, to: nil)
        return Presented(window: window,
                         sheetTop: sheet.view.convert(sheet.view.bounds, to: nil).minY,
                         actionsBottom: contentBottom - 24,
                         visibleBottom: min(scrollFrame.maxY, 874) - scroll.safeAreaInsets.bottom)
    }

    /// The largest scroll view under `root` (the sheet's ScrollView).
    private static func scrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ v: UIView) {
            if let s = v as? UIScrollView, s.contentSize.height > (best?.contentSize.height ?? 0) { best = s }
            v.subviews.forEach(visit)
        }
        visit(root)
        return best
    }

    private func assertButtonsOnScreen(jackpot: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        for c in Self.longTitles {
            let p = try present(c, jackpot: jackpot)
            defer { p.window.rootViewController?.dismiss(animated: false); p.window.isHidden = true }
            let tag = "\(c.1) (jackpot \(jackpot))"
            print("MRT-LAYOUT \(tag) sheetTop=\(p.sheetTop) actionsBottom=\(p.actionsBottom) visibleBottom=\(p.visibleBottom)")
            // Still the partial detent, not the large one.
            XCTAssertGreaterThan(p.sheetTop, 874 * 0.25, "sheet at the 0.65 detent: \(tag)", file: file, line: line)
            XCTAssertLessThanOrEqual(p.actionsBottom, p.visibleBottom,
                                     "Spin again, Share and Movie page fully on screen at 0.65: \(tag)", file: file, line: line)
        }
    }

    func testLongTitlesKeepActionsOnScreenAtPartialDetent() throws {
        try assertButtonsOnScreen(jackpot: false)
    }

    func testLongTitlesKeepActionsOnScreenAtPartialDetentJackpot() throws {
        try assertButtonsOnScreen(jackpot: true)
    }
}
