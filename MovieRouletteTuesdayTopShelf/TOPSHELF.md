# Apple TV Top Shelf

Top Shelf shows the **latest episode** (Matthew, 2026-10-28). The approved layout is mock 13: a wide banner with the poster on the left, a NEW EPISODE pill, `S4E37 · Oct 27, 2026`, the film title, the listener credit and runtime when the feed actually has them, and the show name.

A static image cannot change when a new episode is published. The extension publishes dynamic content. The asset-catalog image is only the fallback until a snapshot exists, and the slot App Store Connect requires.

## Deep link

Select on the shelf opens:

```text
mrt://episode/<guid>
```

Example: `mrt://episode/Buzzsprout-19913482`.

| Step | Where |
| --- | --- |
| URL is built | `DeepLink.episode(guid:).url`, also `TopShelfEpisode.deepLink` |
| Scheme is declared | `MovieRouletteTuesdayTV/Info.plist` (`mrt`) |
| The app receives it | `TVRootView.onOpenURL` → `open(_:)` |
| Episode page | `.episode` sets `pages = [.episode(guid)]`, which shows `TVEpisodeDetailView` |
| Feed not loaded yet | That page shows “Loading episode…” and calls `episodes.load()` |

`TVRootView` already handled `mrt://movie/…` and `mrt://episode/…` before this extension. Unit tests round-trip the shelf URL, including a guid that needs percent-encoding. `-MRTOpenEpisode <guid>` opens the same page for UI tests; it is a launch argument, not the URL the shelf uses.

The shelf does not invent a listener name. “Listener pick from Kevin” is the mock’s example. The shipped line uses that shape only when the show notes say “listener pick from Kevin” or “Kevin's listener pick”. Otherwise the line is the runtime (`1 hr 23 min`).

## App Group

`group.com.movieroulettetuesday.app` — the same identifier as the iOS widget. The Apple TV container is separate from the iPhone’s.

| File | Role |
| --- | --- |
| `topshelf-snapshot.json` | Latest episode (guid, title, season, date, runtime, art URL) |
| `topshelf-banner-1x.png` / `topshelf-banner-2x.png` | Rendered inset banner, 1920×720 and 3840×1440 |
| `topshelf-banner.guid` | Which episode those PNGs belong to |

The TV app writes the snapshot when episodes or the catalog load (`TopShelfBridge`) and calls `TVTopShelfContentProvider.topShelfContentDidChange()`. UI tests (`-MRTUITest`) skip that write. If the App Group container is missing, the write is a no-op and the static image stays up.

## Static and dynamic

**Static** (asset catalog, `App Icon & Top Shelf Image`):

- Top Shelf Image: 1920×720 and 3840×1440
- Top Shelf Image Wide: 2320×720 and 4640×1440 (Apple TV 4K; the 1920-wide art centered in the extra margin)
- Layered app icon: Small 400×240 (@2x 800×480) and Large 1280×768, Front / Middle / Back

The extension returns nil only when it has no snapshot and the RSS fetch fails. tvOS then shows the static image.

**Dynamic** (`com.apple.tv-top-shelf`, principal class `TopShelfContentProvider`):

1. Read the snapshot. If it is missing or older than six hours, re-read the public Buzzsprout RSS feed and save a new snapshot.
2. If a banner for that guid is already on disk, publish **inset** content (`TVTopShelfInsetContent`) pointing at the file.
3. Otherwise draw the banner (episode art when the download succeeds in time, otherwise a plain poster block) and publish that.
4. If the PNG cannot be written, publish one **sectioned** item (`TVTopShelfSectionedContent`) with the remote artwork URL, so the title still updates.
5. `displayAction` is the `mrt://episode/…` URL. There is no separate Play button; Listen stays on the episode page.

Inset images are 1920×720 @1x and 3840×1440 @2x, the same frame as the approved mock. Sectioned fallback uses a poster shape for a catalog `posterURL` and a square shape for episode or show art.

## Placeholder art

The layered icon and both Top Shelf images are **placeholders**. They say TODO / LATEST EPISODE / PLACEHOLDER ART. They are not the Passengers poster from the mock (that artwork is not in the repo). Replace them before submission. The Top Shelf images are fully opaque bitmaps (`actool` rejects any alpha on those slots). The back icon layer is fully opaque too. Front and Middle stay transparent so the parallax stack has depth.

## What a Mac still has to verify

This repo was checked with the Foundation tests (`TopShelfTests`: latest episode, deep link, copy, banner layout, inset vs sectioned, App Group files). It was not built with the tvOS SDK.

1. Open `MovieRouletteTuesday.xcodeproj`, scheme **MovieRouletteTuesdayTV**.
2. Signing & Capabilities: pick the team for **MovieRouletteTuesdayTV** and **MovieRouletteTuesdayTopShelf**. Confirm the App Group `group.com.movieroulettetuesday.app` registers for the tvOS app id. No App Store Connect, TestFlight, or listing work.
3. Build for an Apple TV simulator. The extension target is `MovieRouletteTuesdayTopShelf`, bundle id `com.movieroulettetuesday.app.topshelf`, embedded in the TV app.
4. If the tvOS SDK renamed a symbol, fix it in `TopShelfContentProvider.swift`. The calls this target expects:
   - `TVTopShelfContentProvider.loadTopShelfContent(completionHandler:)`
   - `TVTopShelfContentProvider.topShelfContentDidChange()`
   - `TVTopShelfItem(identifier:)` and `TVTopShelfSectionedItem(identifier:)`
   - `setImageURL(_:for:)` with `.screenScale1x` / `.screenScale2x`
   - `TVTopShelfAction(url:)`
   - `TVTopShelfInsetContent(items:)` and `TVTopShelfSectionedContent(sections:)`
   - `imageShape` `.poster` / `.square` on the sectioned item
5. On a simulator or Apple TV, focus the app in the top row of the Home Screen. The shelf should show the latest episode, not the static TODO image, after the extension can read the feed or the app has launched once.
6. Click the shelf. The app should open that episode (`mrt://episode/…`).
7. If `TVTopShelfInsetContent.imageSize` is not 1920×720, change `TopShelf.insetSize1x` / `insetSize2x`. The layout scales with those sizes.
8. Replace the placeholder icon and Top Shelf images, then archive once and confirm `actool` accepts the layered icon (opaque back layer).
