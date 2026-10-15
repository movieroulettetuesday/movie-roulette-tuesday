# Movie Roulette Tuesday

iOS companion for [Movie Roulette Tuesday: The Podcast](https://podcasts.apple.com/us/podcast/movie-roulette-tuesday-the-podcast/id1666123849) — spin the wheel, browse every episode and film, track your spins and ratings on device, and vote in anonymous listener polls.

Unzip, open `MovieRouletteTuesday.xcodeproj`, select an iPhone simulator, Run.

## One-time Xcode / CloudKit setup

The project uses automatic signing. To build under your own Apple Developer team, change the Team once:

1. **Signing Team (both targets).** Project → Signing & Capabilities → pick your Team for **MovieRouletteTuesday** and **MovieRouletteTuesdayWidgetExtension**. The App Group `group.com.movieroulettetuesday.app` is already in both entitlements; Xcode registers it for your team. Until that's done the widget still works but only shows Spin of the Day (no latest episode / last spin).
2. **iCloud container.** The app target already has the CloudKit entitlements (`iCloud.com.movieroulettetuesday.app`). If Xcode asks you to enable the iCloud container under Signing & Capabilities → iCloud → CloudKit, accept. The widget does **not** need iCloud.
3. **CloudKit schema (before App Store).** Open [CloudKit Console](https://icloud.developer.apple.com) → your team → container `iCloud.com.movieroulettetuesday.app` → Development → Schema → **Import** `CloudKit/MovieRouletteTuesday.ckdb` (or create record types `PollVote` and `ListenerRating` by hand; mark `pollId` and `movieId` **Queryable**). Then **Deploy Schema Changes → Promote to Production**. Until the schema exists the app still runs — polls and listener ratings simply show empty / “couldn't load”. Details in `CloudKit/SCHEMA.md`.

## Privacy

This app collects no personal data. No accounts, no analytics, no third-party services, zero hosting cost.

- **On device only:** spin history, your ratings, watchlist, settings, “last viewed Episodes” timestamp.
- **Anonymous iCloud (optional):** poll votes, listener star ratings and in-app movie suggestions go to the CloudKit **public** database. Records store only a poll/movie id and an option or star count (a suggestion stores the title, optional category and note, and an optional credit name you type). Your iCloud user record ID is hashed into the record name so re-voting overwrites instead of duplicating — it is never written to a field. Reading results does not require iCloud sign-in; writing does (you'll see “Sign in to iCloud in Settings to vote”).
- **Public reads only (no user data sent):** the RSS feed (Episodes tab and the optional new-episode check), Apple's iTunes Lookup API (`itunes.apple.com/lookup?id=1666123849&entity=podcastEpisode`, to link the exact Apple Podcasts episode; only the show's public ID is sent; cached in Caches), and the Listen / Follow the Show links, which open in the other app or the browser.
- **New-episode alert (off by default):** a `BGAppRefreshTask` re-reads the public RSS feed and posts a *local* notification. No push server, no device token. Notification permission is requested only when you turn it on; the "last seen" marker stays in UserDefaults.
- **Suggest a movie:** one sheet. **Send** saves an anonymous `Suggestion` record to the CloudKit public database (create-only; needs iCloud). **Send by email instead** builds an email in Mail (or your mail app via `mailto:`) to theMrtPodcast@gmail.com; the app never sends it, you do. No mail app? It copies the address.
- **Siri / Shortcuts:** "Spin Movie Roulette" runs in the app process and writes only to the on-device spin history.

## Features

- **v4:** episode **Listen** card (Apple Podcasts exact episode via GUID lookup with show fallback, Spotify episode search, Overcast show, Buzzsprout episode); **Suggest a movie** (Movies tab row + Settings); **Spin Movie Roulette** App Intent with App Shortcuts phrases and a result snippet (Spin Again / Open in App); **New-episode alert** (Settings, opt-in; tap opens `mrt://episode/<guid>`); **Follow the Show** (8 official links in Settings).

- **Roulette** — tap the glowing hub (or anywhere on the wheel) to spin; VoiceOver Magic Tap spins too. A short opening animation plays on cold launch only (tap to skip; Reduce Motion crossfades; deep links/widget taps skip it). 10 categories and the real episode-by-episode movie list (`movies.json` with Buzzsprout guids; the copy on GitHub `main` is fetched at launch and on pull-to-refresh, validated, and cached, with the bundled copy as fallback; see [CATALOG.md](CATALOG.md)). Spin sound is a real recorded wheel spin (`wheel-spin.m4a`, played once per spin off the main thread); the wheel's motion is timed to the clip so each click lands as a slice passes the pointer and the wheel stops on the final thunk; haptics on each crossing. Outcomes stay uniformly random. Rare outcomes (always on, ~1% Re-spin forced!, ~1% Infamous jackpot when any movie is `isInfamous`). Shareable branded result card. Settings gear for Appearance / Spin sound / Haptics / New-episode alert / My services / Auto-share ratings + the privacy note. Only the hub's ■ stops a spin early.
- **Episodes** — live Buzzsprout RSS (`https://rss.buzzsprout.com/2117292.rss`). Tab badge for episodes published since you last viewed the tab (never badges the whole back catalog on first launch). Per-episode anonymous listener poll (Good/Bad, Recommend, or Who won the argument? with Rachael / Karl / Matt). Optional overrides in bundled `polls.json`.
- **Movies** — search/sort/filter (category, watchlist, watched, rated by me, haven't spun yet). Per-movie Your Take (1–5 stars + Want to Watch / Watched) and anonymous Listener Rating.
- **Stats** — this-device spin overview + Your Ratings (count, average, top-rated by you; you-vs-hosts only where `hostRating` exists).
- **Widget** — Spin of the Day (+ latest episode / last spin once the App Group is signed).

## Project layout

- `MovieRouletteTuesday/` — app (SwiftUI, iOS 17+, no third-party deps). Pure logic lives in `RouletteCore/` (also compiles on Linux for unit tests).
- `MovieRouletteTuesdayWidget/` — WidgetKit extension (App Group).
- `MovieRouletteTuesdayTests/` — XCTest.
- `CloudKit/` — `.ckdb` schema + `SCHEMA.md`.
- Project files: add new source files through Xcode (File → New / Add Files) so they join the right targets (app, widget, tests).

## Simulate without iCloud

Scheme → Run → Arguments → add `-MRTMockCommunity`. Uses an in-memory community store (also what SwiftUI previews use).

## Replacing an existing copy with a new zip
Quit Xcode, replace the whole folder, reopen, then **Product ▸ Clean Build Folder** (⇧⌘K) once before building.
New zips are stamped with their build time so Xcode notices the changes, but a clean build is the safest way to avoid stale objects in DerivedData.
