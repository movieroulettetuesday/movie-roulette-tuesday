# CloudKit schema (Movie Roulette Tuesday)

**Container:** `iCloud.com.movieroulettetuesday.app`
**Database:** Public
**File:** `MovieRouletteTuesday.ckdb` (importable CloudKit Schema Language)

## Record types

### `PollVote`
| Field    | Type   | Notes |
|----------|--------|-------|
| `pollId` | String | **QUERYABLE**. Stable poll id, e.g. `Buzzsprout-19913482.good-bad`. |
| `option` | String | Option id (`good` / `bad` / `yes` / `host-1` / …). |

Record name: `vote-<pollId>-<sha256(userRecordName + pollId)>`.

### `ListenerRating`
| Field     | Type  | Notes |
|-----------|-------|-------|
| `movieId` | String | **QUERYABLE**. Catalog movie id. |
| `stars`   | Int64  | 1…5 whole stars. Still written (rounded, 3.5 → 4) so older app versions keep working. |
| `halfStars` | Int64 | 1…10 half-stars (added Oct 2026, build 5+). Readers use `halfStars`, else `stars × 2` for records from older builds. No backfill needed. |

Record name: `rating-<movieId>-<sha256(userRecordName + "rating:" + movieId)>`.

### `Suggestion` (added Oct 2026)
| Field        | Type   | Notes |
|--------------|--------|-------|
| `title`      | String | Movie title (≤120 chars). |
| `category`   | String | Optional category name ("" when none). |
| `note`       | String | Optional "why" (≤280 chars). |
| `creditName` | String | Optional "credit me as" (≤60 chars). |
| `appVersion` | String | e.g. `1.0 (5)`. |

Record name: `suggestion-<UUID>` (always a new record). Grants: **CREATE to `_icloud` only** — no `_world`/`_icloud` READ, so listeners can't read each other's suggestions. `___createTime` is SORTABLE + QUERYABLE so the Console can list them newest first. The app also limits itself to one suggestion per 10 minutes per device.

**Reading suggestions:** CloudKit Console → container → **Production** → Records → Public Database → type `Suggestion` → query, sort by created date.

## Queries the app runs (all read-only, `_world` READ, no sign-in)

| Query | Index used | Since |
|-------|------------|-------|
| `PollVote WHERE pollId == <id>` | `pollId` QUERYABLE | 1.0 |
| `ListenerRating WHERE movieId == <id>` (movie page) | `movieId` QUERYABLE | 1.0 |
| `ListenerRating WHERE movieId IN <≤100 catalog ids>` (launch bulk read for the infamous jackpot weighting; ~2 queries for 180 movies, cursor-paged 200/page, desiredKeys `movieId`,`halfStars`,`stars`) | `movieId` QUERYABLE (same index) | 1.0.1 |

No query uses `NSPredicate(value: true)` (that would need `___recordID` QUERYABLE in Production) or any sort, so 1.0.1 needs **no schema change and no new index**.

## Public-database grants (already in the `.ckdb`)

- `GRANT READ TO "_world"` — anyone can read results (no iCloud sign-in required).
- `GRANT CREATE TO "_icloud"` — signed-in iCloud users can create their one vote/rating.
- `GRANT WRITE TO "_creator"` — that user can overwrite their own record when re-voting.

## Deploy steps (one-time, before App Store)

1. Open [CloudKit Console](https://icloud.developer.apple.com) → your team → container `iCloud.com.movieroulettetuesday.app`.
2. **Development → Schema → Import Schema** → choose `CloudKit/MovieRouletteTuesday.ckdb`.
   Or create the record types by hand and mark `pollId` / `movieId` QUERYABLE.
   For `Suggestion`, check the type's Security Roles: only `Authenticated` (`_icloud`) **Create**; make sure **World** has no Read.
3. **Deploy Schema Changes → Promote to Production**.
4. Until the schema exists the app still runs: polls and ratings simply show empty results / “couldn't load”.

## Privacy

Records store only the poll/movie id and the chosen option or star count; a `Suggestion` stores only what the listener typed (title, optional category, note and credit name). The iCloud user record ID is hashed into the record name and never written to a field. Reading the public database does not require iCloud sign-in; writing does.
