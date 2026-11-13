# Changelog

All notable changes to Movie Roulette Tuesday are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
iPhone and iPad ship from `main`. Apple TV ships from `feature/tvos` and is tagged separately (`v1.0-tvos`, `v1.0.2-tvos`).

## [Unreleased] — 1.1

iPhone and iPad work is on `main` (merged 2026-11-13). It has not been version-bumped or tagged; Release holds tags. Matching Apple TV work is on `feature/tvos` and is also unreleased.

### Added

- App Intents, Spotlight, and Siri Spin handoff: Spin, Open Movie, Latest Episode, Show/Add Watchlist, Mark Watched, Where to Watch, and Open on a Provider. Alternate names “Movie Roulette Tuesday” and “Movie Roulette” are registered. Spotlight records are public catalog fields only (no ratings or watchlist).
- On-device “What should I watch?” using Apple’s Foundation Models when they are available, with a short why; a graceful no-op on devices where the model is unavailable. Siri’s What Should I Watch intent offers Spin and never auto-spins. There is no cloud or network language-model path.
- Apple TV (on `feature/tvos`): App Intents, Spin handoff, and “What should I watch?” offers Spin. Intents live in the TV app (not the Top Shelf extension). No Spotlight or IndexedEntity on tvOS. Foundation Models APIs are unavailable on tvOS 27.2, so the in-app suggestion button is omitted on TV.

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

[Unreleased]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/compare/v1.0-rc1...v1.0.1
[1.0]: https://github.com/movieroulettetuesday/movie-roulette-tuesday/releases/tag/v1.0-tvos
