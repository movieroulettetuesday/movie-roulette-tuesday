# Movie catalog (`movies.json`)

The app's movie list is `MovieRouletteTuesday/Resources/movies.json`. The copy on
this repo's `main` branch is live: the app fetches

    https://raw.githubusercontent.com/movieroulettetuesday/movie-roulette-tuesday/main/MovieRouletteTuesday/Resources/movies.json

at launch and on pull-to-refresh (8 s timeout, background, plain GET with no user
data). A fetched list replaces the on-device copy **only if it passes validation**;
otherwise the app keeps its last good copy, or the copy bundled in the build. So a
change merged to `main` reaches existing installs with no App Store release, and a
broken edit is ignored instead of breaking the wheel.

## Validation (all must pass, or the update is ignored)

- Valid JSON that decodes into the schema below.
- `schemaVersion` is 1 or 2 (this build understands up to 2).
- At least one category and one movie.
- Fully consistent: unique movie and category ids; every id in a category's
  `movieIds` exists **and** that movie lists the category back in its `categories`
  (and the reverse); every category has at least one movie; `colorHex` is
  `#RRGGBB` or `#RRGGBBAA`.

`CatalogTests.testBundledCatalogIsConsistentAndReal` checks the same rules
(run the unit tests before merging).

## Top level

| Key | Type | Notes |
|---|---|---|
| `schemaVersion` | int | Currently `2`. |
| `show` | object | Show name, hosts, RSS/Apple/Spotify ids. Rarely changes. |
| `categories` | array | The wheel slices, in wheel order. |
| `movies` | array | Every movie. Order doesn't matter. |
| `_note` | string | Free-text comment; ignored by the app. |

Unknown keys are ignored, so adding a field is safe.

## Category

| Key | Type | Notes |
|---|---|---|
| `id` | string | Stable. Never rename. |
| `name` | string | Short label drawn on the wheel. |
| `fullName` | string? | Longer name for lists and stats. |
| `colorHex` | string | Slice color. |
| `weight` | number? | Relative slice size (`null` = 1). |
| `movieIds` | [string] | Movies in this slice. |

Current categories:

| id | name | fullName |
|---|---|---|
| `cat-horror` | Horror | Horror & Terror |
| `cat-cult` | Cult | Cult & Bizarre |
| `cat-criterion` | Criterion | Criterion & Classics |
| `cat-love` | Love Hurts | Love Hurts |
| `cat-scifi` | Sci-Fi | Sci-Fi & Fantasy |
| `cat-action` | Action | Action & Thrillers |
| `cat-dark-comedy` | Dark Comedy | Dark Comedy |
| `cat-listener` | Listeners | Listener Picks |
| `cat-prestige` | Prestige | Prestige Drama |
| `cat-escape` | Escape | War, Escape & Survival |

## Movie

| Key | Type | Notes |
|---|---|---|
| `id` | string | `title-slug-year`, e.g. `the-outsiders-1983`. **Stable forever:** spin history, personal ratings and the anonymous iCloud votes are keyed by it. Never rename or reuse one. |
| `title` | string | |
| `year` | int | Release year. |
| `genre` | string | One display genre, e.g. `Horror`, `Drama`. |
| `categories` | [string] | Category ids. Each must list this movie back in its `movieIds`. |
| `episodeIds` | [string] | Buzzsprout RSS `<guid>`s of the episodes that discussed it, e.g. `Buzzsprout-19913482`. This links the episode page to the movie. |
| `episodeTitle` | string? | RSS episode title, shown when offline. |
| `posterURL` | string? | Usually `null`; the app looks artwork up itself. |
| `isInfamous` | bool | Optional. Since 1.0.1 every movie can come up in the rare "Infamous jackpot" (weighted toward low listener ratings); `true` gives the movie the top jackpot weight. |
| `hostRating` | number? | Usually `null`. |

## Adding a new episode's movie

1. Find the episode's `<guid>` in https://rss.buzzsprout.com/2117292.rss
   (`Buzzsprout-NNNNNNNN`) and its title.
2. Add a movie object to `movies` (copy an existing one). Use a new `id`
   (`title-slug-year`), and put the guid in `episodeIds` and the episode title in
   `episodeTitle`. If the movie is already in the list (a repeat discussion), just
   append the guid to its existing `episodeIds` instead.
3. Add the movie's `id` to the `movieIds` of every category listed in its
   `categories`.
4. Run the unit tests (or at least check the JSON is valid), then merge to `main`.
   Apps pick it up on their next launch or pull-to-refresh, and the episode's
   page then shows its movie.

Removing a movie is allowed; history and ratings for its id stay on devices but
the movie no longer appears on the wheel.
