#if DEBUG
import SwiftUI
import UIKit
import MRTCore

/// DEBUG-only launch arguments for simulator smoke tests (compiled out of
/// Release): `-MRTOrientation landscape|portrait` asks the window scene for
/// that orientation, `-MRTStartTab roulette|episodes|movies|stats` picks the
/// first tab, `-MRTScrollMovies` scrolls the Movies list (memory check),
/// `-MRTOpenMovie <id>` opens a movie page, `-MRTShowHistory` opens Spin History,
/// `-MRTShowRules` opens House Rules; see below for the splash / hub flags.
@MainActor
enum DebugLaunch {
    static func value(for flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1].lowercased()
    }

    static var startTab: ContentView.Tab? {
        switch value(for: "-MRTStartTab") {
        case "roulette": return .roulette
        case "episodes": return .episodes
        case "movies": return .movies
        case "stats": return .stats
        default: return nil
        }
    }

    /// `-MRTOpenMovie <id>`: opens that movie like an mrt://movie/<id> link
    /// (screenshots without the system "Open in…" prompt). Original case kept.
    static var openMovieID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MRTOpenMovie"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// `-MRTShowHistory`: opens the Spin History sheet on launch (screenshots, UI tests).
    static var showsHistory: Bool { ProcessInfo.processInfo.arguments.contains("-MRTShowHistory") }

    /// `-MRTShowRules`: opens the House Rules sheet on launch (screenshots).
    static var showsRules: Bool { ProcessInfo.processInfo.arguments.contains("-MRTShowRules") }

    /// `-MRTHubPressed`: draws the hub spin button in its pressed state (screenshots).
    static var hubPressed: Bool { ProcessInfo.processInfo.arguments.contains("-MRTHubPressed") }

    /// `-MRTSplashHold <sec>`: holds the opening on its launch-screen frame first
    /// (compare against the storyboard). `-MRTSplashReduceMotion`: forces the
    /// Reduce Motion crossfade. `-MRTNoSplash`: skips the opening entirely.
    static var splashHold: Double { value(for: "-MRTSplashHold").flatMap(Double.init) ?? 0 }
    static var splashReduceMotion: Bool { ProcessInfo.processInfo.arguments.contains("-MRTSplashReduceMotion") }
    static var noSplash: Bool { ProcessInfo.processInfo.arguments.contains("-MRTNoSplash") }

    static func applyRequestedOrientation() {
        let mask: UIInterfaceOrientationMask
        switch value(for: "-MRTOrientation") {
        case "landscape": mask = .landscapeRight
        case "portrait": mask = .portrait
        default: return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            FileHandle.standardError.write(Data("MRT-ORIENTATION error: \(error.localizedDescription)\n".utf8))
        }
    }
}

/// `-MRTScrollMovies`: once the Movies list has rows, scrolls it top->bottom->top
/// three times in small steps (every row's thumbnail loads, then scrolls away),
/// logging `MRT-SCROLL` lines to stderr so a script can sample memory.
@MainActor
enum DebugScroll {
    private static var started = false

    static func runIfRequested(proxy: ScrollViewProxy, ids: () -> [String]) async {
        guard ProcessInfo.processInfo.arguments.contains("-MRTScrollMovies"), !started else { return }
        started = true
        var rows = ids()
        for _ in 0..<200 where rows.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            rows = ids()
        }
        // Give the feed (artwork URLs) a moment to arrive from cache/network.
        try? await Task.sleep(for: .seconds(4))
        rows = ids()
        log("MRT-SCROLL start rows=\(rows.count)")
        let passes = 3
        for pass in 0..<passes {
            let order = pass.isMultiple(of: 2) ? rows : rows.reversed()
            for index in stride(from: 0, to: order.count, by: 3) {
                if Task.isCancelled { return }
                proxy.scrollTo(order[index], anchor: .top)
                try? await Task.sleep(for: .milliseconds(90))
            }
            if let last = order.last { proxy.scrollTo(last, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(500))
            log("MRT-SCROLL pass \(pass + 1)")
        }
        log("MRT-SCROLL done rows=\(rows.count) passes=\(passes)")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
