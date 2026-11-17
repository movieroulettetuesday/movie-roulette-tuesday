#if DEBUG
import SwiftUI
import UIKit

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

    /// `-MRTRevealMovie <id>`: presents the wheel reveal sheet for that catalog
    /// movie after the catalog loads (UI tests of long titles at large text).
    /// Original case kept.
    static var revealMovieID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MRTRevealMovie"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// `-MRTHubPressed`: draws the hub spin button in its pressed state (screenshots).
    static var hubPressed: Bool { ProcessInfo.processInfo.arguments.contains("-MRTHubPressed") }

    /// `-MRTSplashHold <sec>`: holds the opening on its launch-screen frame first
    /// (compare against the storyboard). `-MRTSplashReduceMotion`: forces the
    /// Reduce Motion crossfade. `-MRTNoSplash`: skips the opening entirely.
    static var splashHold: Double { value(for: "-MRTSplashHold").flatMap(Double.init) ?? 0 }
    static var splashReduceMotion: Bool { ProcessInfo.processInfo.arguments.contains("-MRTSplashReduceMotion") }
    static var noSplash: Bool { ProcessInfo.processInfo.arguments.contains("-MRTNoSplash") }

    /// `-MRTSuggestionGate available|unavailable|notReady` forces the step-2
    /// availability gate so UI tests don't need Apple Intelligence.
    static var suggestionStatus: SuggestionModelStatus? {
        switch value(for: "-MRTSuggestionGate") {
        case "available": return .available
        case "unavailable": return .unavailable
        case "notready": return .temporarilyUnavailable
        default: return nil
        }
    }

    /// `-MRTNLSearchGate available|unavailable|notready` forces the NL search
    /// availability gate so UI tests don't need Apple Intelligence.
    static var nlSearchStatus: SuggestionModelStatus? {
        switch value(for: "-MRTNLSearchGate") {
        case "available": return .available
        case "unavailable": return .unavailable
        case "notready": return .temporarilyUnavailable
        default: return nil
        }
    }

    /// `MRT_NL_STUBS` in the launch environment: a JSON object mapping a
    /// question to its parsed filter (shared-schema keys). Stands in for the
    /// on-device model in UI tests; an unknown question parses to nothing.
    static var nlSearchStub: StubNLSearchParser? {
        guard let json = ProcessInfo.processInfo.environment["MRT_NL_STUBS"], !json.isEmpty,
              let table = try? JSONDecoder().decode([String: NLSearchFilter].self, from: Data(json.utf8))
        else { return nil }
        return StubNLSearchParser(table)
    }

    /// UI-test stand-in for the on-device model (no Apple Intelligence needed).
    /// `MRT_SUGGESTION_MOVIE <id>` (or `-MRTSuggestionMovie <id>`) puts that
    /// movie first in the list and answers pick 1; `MRT_SUGGESTION_VIBE` is the
    /// vibe it answers (default "cult"). `MRT_SUGGESTION_FORCE timeout|invalid`
    /// makes it never answer in time, or answer a number outside the list, so
    /// the app's own pick shows. The facts always come from the app's real lists.
    /// `MRT_SUGGESTION_TIMEOUT_MS <ms>` replaces the 2.5 s cap for that launch, so
    /// a UI test can hold the loading card (with `timeout`) long enough to check it.
    static var suggestionStubbed: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MRT_SUGGESTION_MOVIE"].map { !$0.isEmpty } == true
            || env["MRT_SUGGESTION_FORCE"].map { !$0.isEmpty } == true
            || ProcessInfo.processInfo.arguments.contains("-MRTSuggestionMovie")
    }

    @MainActor
    static func suggestionStub(rows: [PickMovie]) -> DebugSuggestionStub? {
        guard suggestionStubbed else { return nil }
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        let id = env["MRT_SUGGESTION_MOVIE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? argumentValue(for: "-MRTSuggestionMovie", in: args, joiningUntilNextFlag: false)
        let vibe = env["MRT_SUGGESTION_VIBE"].flatMap { $0.isEmpty ? nil : $0 } ?? PickVibe.cult.rawValue
        let force = env["MRT_SUGGESTION_FORCE"].flatMap { $0.isEmpty ? nil : $0.lowercased() }
        if let ms = env["MRT_SUGGESTION_TIMEOUT_MS"].flatMap(Int.init), ms > 0 {
            SuggestionGenerator.timeout = .milliseconds(ms)
        }
        return DebugSuggestionStub(movie: id.flatMap { id in rows.first { $0.id == id } }, vibe: vibe, force: force)
    }

    /// Raw (not lowercased) launch-argument value. When `joiningUntilNextFlag`
    /// is true, consecutive tokens up to the next `-` flag are joined — XCTest
    /// has been seen to split a why-string on spaces and apostrophes.
    private static func argumentValue(for flag: String, in args: [String], joiningUntilNextFlag: Bool) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        if !joiningUntilNextFlag { return args[i + 1] }
        var parts: [String] = []
        var index = i + 1
        while index < args.endIndex {
            let token = args[index]
            if token.hasPrefix("-"), !token.hasPrefix("- "), token.count > 1,
               token.dropFirst().first?.isLetter == true,
               token != "-" {
                break
            }
            parts.append(token)
            index += 1
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

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

/// DEBUG-only ratings fixture for UI tests. `-MRTUITest` deletes the on-device
/// ratings file. `-MRTSeedRating <movieId> <halfStars>` writes 1...10 (never 0).
/// `-MRTSeedWatchlist <movieId>` sets Want to watch after that, so a rating on
/// the same id is kept and the status becomes the watchlist. Leave both flags
/// off on a later launch to read what Clear rating saved.
enum UITestRatingSeed {
    static func applyIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        let ratingsArgs = values(after: "-MRTSeedRating", in: args)
        let watchlist = values(after: "-MRTSeedWatchlist", in: args)
        let reset = args.contains("-MRTUITest")
        guard reset || !ratingsArgs.isEmpty || !watchlist.isEmpty else { return }
        guard let file = try? PersonalRatingsFileStore.applicationSupport() else { return }
        if reset {
            try? FileManager.default.removeItem(at: file.fileURL)
        }
        var ratings = (try? file.load()) ?? PersonalRatings()
        var index = 0
        while index + 1 < ratingsArgs.count {
            let movieId = ratingsArgs[index]
            if let half = Int(ratingsArgs[index + 1]), HalfStars.clamped(half) != nil {
                ratings.setHalfStars(half, for: movieId, now: Date(timeIntervalSinceReferenceDate: 0))
            }
            index += 2
        }
        let seededAt = Date(timeIntervalSinceReferenceDate: 1)
        for movieId in watchlist {
            ratings.setStatus(.wantToWatch, for: movieId, now: seededAt)
        }
        try? file.save(ratings)
    }

    private static func values(after flag: String, in args: [String]) -> [String] {
        guard let start = args.firstIndex(of: flag) else { return [] }
        var out: [String] = []
        var index = args.index(after: start)
        while index < args.endIndex, !args[index].hasPrefix("-") {
            out.append(args[index])
            index = args.index(after: index)
        }
        return out
    }
}
#endif

#if DEBUG
struct DebugSuggestionStub: SuggestionResponding {
    var movie: PickMovie?
    var vibe: String
    var force: String?

    func candidates(from list: [PickMovie]) -> [PickMovie] {
        guard let movie else { return list }
        return Array(([movie] + list.filter { $0.id != movie.id }).prefix(PickCandidates.cap))
    }

    func pick(prompt: String) async throws -> RawPick {
        switch force {
        case "timeout":
            try await Task.sleep(for: .seconds(30))
            return RawPick(pick: 1, vibe: vibe)
        case "invalid":
            return RawPick(pick: 99, vibe: vibe)
        default:
            return RawPick(pick: 1, vibe: vibe)
        }
    }
}
#endif
