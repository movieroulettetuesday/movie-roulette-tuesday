# Changelog

All notable changes to Movie Roulette Tuesday are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
iPhone and iPad ship from `main`. Apple TV ships from `feature/tvos` and is tagged separately (`v1.0-tvos`, `v1.0.2-tvos`, `v1.1-tvos`).

## [Unreleased]

## [1.1] - 2026-11-19

App Store release. iPhone and iPad, marketing version 1.1, build 17, live 2026-11-19, tip `3221c86d` on `release/1.1-b17` (version bump on top of `main` `8da770ff`), tag [`v1.1`](https://github.com/movieroulettetuesday/movie-roulette-tuesday/releases/tag/v1.1). Apple TV, marketing version 1.1, build 14, live 2026-11-19, tip `b89c4deb` on `release/tvos-1.1-b14` (version bump on top of `feature/tvos` `3d317819`), tag [`v1.1-tvos`](https://github.com/movieroulettetuesday/movie-roulette-tuesday/releases/tag/v1.1-tvos).

### iPhone and iPad (build 17)

#### Added

- Pick for Me on the Roulette tab (PR #37, replacing the “What should I watch?” button from PR #23). It chooses one movie you haven’t watched, favoring your watchlist and your services, and tells you why. It’s on purpose, not random. The short reason is made from fixed vibe lines plus facts the app writes (watchlist, ratings, where it’s streaming). It needs Apple Intelligence; the button is hidden when Apple Intelligence isn’t available or is turned off. If the model is only temporarily not ready, the button stays visible and says so. On timeout or invalid model output, the app shows its own top-ranked pick with those factual reasons, and does not spin. Siri phrases: “Pick a movie for me in …” and “What should I watch in …”. When a pick can’t be made, Siri offers Spin and never auto-spins.
- Search on Movies and Episodes by title, year, episode number (like S4E39), genre, or streaming service (PR #32). Episodes now has a search field; results are ranked. Find Movie is a Siri App Shortcut; Find Episode is a Shortcuts action only (no Siri phrase).
- Natural-language search on iOS 26+ with Apple Intelligence (PR #34): a question typed in the Movies or Episodes search field (“free 80s horror I haven’t watched”) becomes removable filter chips that combine with the toolbar filters. A question that names the other list moves the query and chips there. On-device model only; elsewhere, or when the model is unavailable, search is keyword search as before. After a list switch on iPhone, the moved query is shown in the destination search field (PR #35). Not on Apple TV.
- App Intents, Spotlight, and Siri Spin handoff (PR #22): Spin opens the app and plays that result; also Open Movie, Latest Episode, Show/Add Watchlist, Mark Watched, Where to Watch, and Open on a Provider. Alternate names “Movie Roulette Tuesday” and “Movie Roulette” are registered. Spotlight records are public catalog fields only (no ratings or watchlist).
- House Rules rewritten to explain Spin and Pick for Me, search, Siri and Shortcuts (every phrase), and the Home Screen widget (PR #37).

#### Changed

- Spin and Stop hit area is at least 44 pt on a small wheel; the visual hub size is unchanged (PR #29).
- After a spin, the result sheet scrolls only when the content does not fit, so Share and Movie page stay reachable (PR #30).
- The built-in catalog is 184 movies, including The Day of the Beast (1995, S4E40), plus a 16 November 2026 streaming refresh (`99f6d40`, `a0433b78`).

#### Fixed

- App Intents metadata no longer includes the word “Apple”, so App Store Connect accepts the build (ASC 90626, PR #36). In Siri and Shortcuts, the streaming option “Apple TV” now shows as “TV app” and the hidden intent is “Listen in Podcasts”. In-app and spoken “Apple Podcasts” text is unchanged.

#### Removed

- The unused `settings.rareOutcomes` key (PR #27). Rare outcomes were already always on; a leftover stored value is ignored. No visible change.

#### Tests

- Unit tests for offline, timeout, slow, and recovery paths for RSS, catalog, and CloudKit ratings (PR #31).

### Apple TV (build 14)

#### Added

- A Search tab for movies and episodes by title, year, episode number (like S4E39), genre, or streaming service, using the same matcher as iOS (PR #33). The Movies tab keeps its filters and sort; its custom text field is retired. Find Movie is a Siri App Shortcut; Find Episode is a Shortcuts action only.
- App Intents and Siri Spin handoff (PR #24): Spin opens the app and plays that result; also Open Movie, Latest Episode, watchlist, Where to Watch, and Open on a Provider. Intents live in the TV app, not the Top Shelf extension. No Spotlight on tvOS. Registered Spin phrases are “Spin …” and “Spin the wheel in …”.
- Siri “Pick for Me” (PR #38, behavior from PR #24): phrases “Pick a movie for me in …” and “What should I watch in …”. The intent always offers Spin and never auto-spins or calls the on-device model (“Picks aren’t available on this TV.”). There is no in-app Pick for Me button. The “What should we watch with …” Spin phrase was dropped.

#### Changed

- The built-in catalog is 184 movies, matching iPhone and iPad, including The Day of the Beast (1995, S4E40) and the 16 November 2026 streaming refresh (PR #40).
- App Intents metadata no longer includes the word “Apple” (PR #38, port of PR #36). In Siri and Shortcuts, “Apple TV” shows as “TV app” and the hidden intent is “Listen in Podcasts”. In-app and spoken “Apple Podcasts” text is unchanged.

#### Removed

- The unused `settings.rareOutcomes` key (PR #28). Rare outcomes stay always on. No visible change.


## [1.0.2] - 2026-11-12

App Store release. iPhone and iPad, marketing version 1.0.2, build 12, live 2026-11-12, tip `f0db463a` on `main`, tag `v1.0.2`. Apple TV, marketing version 1.0.2, build 13, live 2026-11-11, tip `dc7b069b` on `feature/tvos`, tag `v1.0.2-tvos`.

### iPhone and iPad (build 12)

#### Added

- Clear a star rating back to unrated, without changing watched status. The cleared rating stays cleared after a relaunch or a sync.
- iPhone Duo (foldable) support: the roulette wheel stays clear of the fold, and sheet buttons (Done, Clear, Cancel, Send) show icons.

#### Changed

- Half-star ratings are easier to tap precisely.
- The built-in catalog is 183 movies, with refreshed streaming providers.

#### Fixed

- Cancelling a Where to Watch “Open” prompt now stays in the app.

### Apple TV (build 13)

#### Added

- Clear a star rating, reachable with the remote from the star row. The cleared rating stays cleared after a relaunch or a sync.

#### Changed

- Half-star ratings are easier to pick with the remote.
- Your Rating sits directly under Where to Watch; pressing Down from the providers moves to the stars.
- The built-in catalog is 183 movies, with refreshed streaming providers.

#### Fixed

- Paramount+ no longer appears as duplicate tiles when TMDB lists several Paramount+ tiers.
- Cancelling a Where to Watch “Open” prompt now stays in the app.

## [1.0.1] - 2026-11-03

App Store release for iPhone and iPad: marketing version 1.0.1, build 11, live 2026-11-03, tip `e810568` on the 1.0.1 line (later merged into `main`), tag `v1.0.1`. This is the first live iOS App Store build; see [1.0] for the earlier candidate.

### Fixed

- Tapping a new-episode notification no longer crashes the app. The work now finishes on the main thread and opens that episode’s page.
- An empty or non-RSS feed response (HTTP 200 with no episodes) no longer overwrites the cached episode list. The saved episodes stay as they were until a good refresh.
- Movie suggestion emails no longer read “Why: From: …” when the note is left blank. The credit has its own `From:` line.
- Stats ties (`most spun` movie and category, and breakdown order) now sort by count descending, then by id or genre ascending, so the order is stable across launches.
- Long reveal-sheet titles no longer push the Share and Movie page buttons off the iPhone sheet (titles wrap to two lines on iPhone and three on iPad). A remaining tight-clearance case is tracked separately.
- The Infamous Jackpot gold banner stays brand gold in iPhone light mode, so the title stays readable.

### Changed

- The Infamous Jackpot picks from the whole catalog, weighted by listener ratings (unrated movies get a middle weight). The Infamous badge, the old flag, and the normal-spin boost are gone; a leftover catalog `isInfamous` key is ignored.
- The gold Infamous Jackpot banner is the reveal sheet’s navigation title.
- Listener ratings download in bulk at launch (CloudKit `movieId IN` queries, cached locally, refreshed at most every five minutes). No schema or privacy change.
- Where to Watch tiles open the streaming service in its app when that app is installed, or on the web otherwise.
- The built-in catalog was updated (181 movies at this release).

## [1.0] - 2026-11-03

Apple TV 1.0, build 12, live 2026-11-03, tip `033a33d` on `feature/tvos`, tag `v1.0-tvos`. iPhone and iPad 1.0, build 10 (16 October 2026), was the iOS 1.0 release candidate (tip `c7c9672`); it was not the live App Store build (see [1.0.1]). The iOS 1.0 feature set below is from that candidate and the TestFlight builds that led to it.

### Apple TV (build 12)

#### Added

- First Apple TV release of Movie Roulette Tuesday, on the same App Store record as iPhone and iPad: wheel, movies, episodes, ratings, and Where to Watch, with a Top Shelf extension.
- Plain four-digit movie years on the Movie Page (build 12).

### iPhone and iPad (build 10)

#### Added

- Official companion app for Movie Roulette Tuesday: The Podcast, with the wheel, movies, episodes, polls, ratings, a watchlist, spin history, and stats.
- Remote catalog updates, so new episode movies can appear without an app update.
- Where to Watch via TMDB, with My Services in Settings and an “On my services” filter on the Movies tab (Where to Watch is always visible from build 8).
- Half-star ratings.
- In-app Suggest a Movie form, plus send-by-email when Mail is available.
- Episodes grouped by season, year, or all.
- Selectable title and description text on the Movie Page.
- Stop a spin early from the center hub button (stopping from a wheel tap was removed in build 9).
- Polls and anonymous listener ratings (CloudKit). The Host Rating section is hidden behind a feature flag.
- Privacy details required by Apple, and a Version line in Credits & About.
- The tagline “Dinner, discussion, and the wheel.”

#### Changed

- Larger Dynamic Type sizes no longer clip the Roulette header, Episodes rows, and Movies chips.
- Suggest a Movie is one form with Send, plus “Send by email instead.”
- The Rare outcomes setting was removed; rare outcomes are always on.
- Episode About sections show the full show notes.
- The Spotify Listen button opens the podcast directly.
- After a spin, the movie page’s episode link opens that episode.

#### Fixed

- Episode totals on the Episodes and Movies tabs match.
- The category under a movie’s title matches the Categories list.
- Episode descriptions no longer start with the “Send us Fan Mail” text.
- Times Spun no longer shows 0 on the Movie Page after a spin.
- The About screen correctly identifies the official companion app from the hosts.

[Unreleased]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.1...HEAD
[1.1]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0.2...v1.1
[1.0.2]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0-rc1...v1.0.1
[1.0]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/releases/tag/v1.0-tvos
