import XCTest
import SwiftUI
import UIKit
@testable import MovieRouletteTuesday
import MRTCore
import MRTShared

/// Infamous Jackpot reveal title (1.0.1, option C): the gold banner is the navigation
/// bar's principal item instead of a system-colored inline title. The sheet forces dark
/// on its content only, so in light appearance the old title was black on #0E1214.
@MainActor
final class RevealSheetTitleTests: XCTestCase {
    private static let gold = HexColor("#F2C14E")!   // Brand.jackpotGold
    private static let ink = HexColor("#1D2B2E")!    // Brand.ink

    private func reveal(jackpot: Bool) -> RouletteViewModel.Reveal {
        .init(id: UUID(),
              movie: Movie(id: "the-room-2003", title: "The Room", year: 2003, genre: "Drama",
                           categories: ["cat-cult-classics"], episodeIds: []),
              category: RouletteCategory(id: "cat-cult", name: "Cult", colorHex: "#7B2CBF"),
              spinCount: 1, isJackpot: jackpot)
    }

    private struct Hosted {
        let window: UIWindow
        let bar: UINavigationBar
        let item: UINavigationItem
    }

    private func host(jackpot: Bool, style: UIUserInterfaceStyle) throws -> Hosted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                  "unit tests run hosted in the app")
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = style
        let sheet = RevealSheet(reveal: reveal(jackpot: jackpot), catalog: nil, onSpinAgain: {})
            .environment(PersonalRatingsStore(fileStore: nil))
            .environment(SpinHistoryStore(fileStore: nil))
            .environment(CommunityService.preview())
        window.rootViewController = UIHostingController(rootView: sheet)
        window.isHidden = false
        var bar: UINavigationBar?
        var nav: UINavigationController?
        for _ in 0..<40 where bar == nil || nav?.topViewController == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
            bar = Self.first(UINavigationBar.self, in: window)
            nav = Self.navigationController(in: window.rootViewController)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        window.layoutIfNeeded()
        let item = try XCTUnwrap(nav?.topViewController?.navigationItem, "NavigationStack hosts a UINavigationController")
        return Hosted(window: window, bar: try XCTUnwrap(bar, "navigation bar"), item: item)
    }

    private static func first<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let v = view as? T { return v }
        for sub in view.subviews { if let v = first(type, in: sub) { return v } }
        return nil
    }

    private static func navigationController(in vc: UIViewController?) -> UINavigationController? {
        guard let vc else { return nil }
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children { if let nav = navigationController(in: child) { return nav } }
        return nil
    }

    /// Pixels in the navigation bar close to `color` (1x render of the bar's window rect).
    private func pixels(near color: HexColor, in hosted: Hosted, tolerance: Double = 0.08) -> Int {
        let rect = hosted.bar.convert(hosted.bar.bounds, to: hosted.window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: rect, format: format).image { _ in
            hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return 0 }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var n = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
            if abs(r - color.red) < tolerance, abs(g - color.green) < tolerance, abs(b - color.blue) < tolerance { n += 1 }
        }
        return n
    }

    func testJackpotBannerIsTheNavigationBarTitleInLightAndDark() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let hosted = try host(jackpot: true, style: style)
            defer { hosted.window.isHidden = true }
            // Back button and VoiceOver still say "Infamous Jackpot".
            XCTAssertEqual(hosted.item.title, "Infamous Jackpot", "\(style.rawValue)")
            // The principal toolbar item replaces the system-colored title text.
            XCTAssertNotNil(hosted.item.titleView, "principal item hosts the banner (style \(style.rawValue))")
            // The gold capsule is drawn inside the bar (about 150 x 36 pt, so thousands of 1x pixels).
            let gold = pixels(near: Self.gold, in: hosted)
            XCTAssertGreaterThan(gold, 1500, "gold banner visible in the nav bar (style \(style.rawValue))")
        }
    }

    func testJackpotBannerTextIsReadable() {
        // Ink on gold, independent of the bar's scheme (WCAG AA for text).
        XCTAssertGreaterThanOrEqual(contrastRatio(Self.ink, Self.gold), 4.5)
    }

    func testRegularRevealKeepsPlainTitle() throws {
        let hosted = try host(jackpot: false, style: .light)
        defer { hosted.window.isHidden = true }
        XCTAssertEqual(hosted.item.title, "Tonight’s Movie")
        XCTAssertLessThan(pixels(near: Self.gold, in: hosted), 200, "no jackpot banner on a regular reveal")
    }
}
