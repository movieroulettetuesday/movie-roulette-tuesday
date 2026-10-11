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
| `stars`   | Int64  | 1…5. |

Record name: `rating-<movieId>-<sha256(userRecordName + "rating:" + movieId)>`.

## Public-database grants (already in the `.ckdb`)

- `GRANT READ TO "_world"` — anyone can read results (no iCloud sign-in required).
- `GRANT CREATE TO "_icloud"` — signed-in iCloud users can create their one vote/rating.
- `GRANT WRITE TO "_creator"` — that user can overwrite their own record when re-voting.

## Deploy steps (one-time, before App Store)

1. Open [CloudKit Console](https://icloud.developer.apple.com) → your team → container `iCloud.com.movieroulettetuesday.app`.
2. **Development → Schema → Import Schema** → choose `CloudKit/MovieRouletteTuesday.ckdb`.
   Or create the two record types by hand and mark `pollId` / `movieId` QUERYABLE.
3. **Deploy Schema Changes → Promote to Production**.
4. Until the schema exists the app still runs: polls and ratings simply show empty results / “couldn't load”.

## Privacy

Records store only the poll/movie id and the chosen option or star count. The iCloud user record ID is hashed into the record name and never written to a field. Reading the public database does not require iCloud sign-in; writing does.
