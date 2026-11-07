# iPhone Duo — next-build release gate

Ship the iPhone/iPad archive only after every item below has been checked on a Mac with Xcode. A Linux checkout cannot run this gate: it has no iOS SDK and no iPhone Duo simulator.

Deployment target stays iOS 17.0. That is not the SDK the archive was built with.

## Archive SDK

- Archive **MovieRouletteTuesday** with the **iOS 27.1 SDK or later** (Xcode 27.1 or later).
- On the archived app, confirm `DTSDKName` / the platform SDK is `iphoneos27.1` or newer. An iOS 26-or-earlier archive stays in the compatibility window (centered on the inner display, content left of the outer camera) and does not get vertical bars.
- `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` and `ReservedRegion` are iOS 27.1 APIs (also iPadOS 27.1 and tvOS 27.1). The wheel calls `reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)` inside `#available(iOS 27.1, *)`. Building this call needs that SDK. On iOS 17 through 27.0 the call is skipped and the wheel stays centered.

## Unit tests (Mac)

Run the app test target. These do not need the Duo simulator:

- `testNoActiveHingeLeavesTheWheelWhereItWas`
- `testVerticalHingeMovesTheHubOntoTheLargerSide`
- `testEqualPanesPreferThePositiveSide`
- `testHorizontalHingeMovesVertically`
- `testFoldAndUnfoldIsJustTheCurrentDivisionList`
- `testHubClearsWhenTheWheelCannotStayInTheSlot`
- `testBookAndTabletopBandsBothClear`
- `testABandThatMissesTheHubDoesNotMoveTheWheel`

Existing iPhone and iPad layout tests in `AdaptiveLayoutTests` must still pass.

## Duo simulator

Xcode 27.1 or later, iPhone Duo simulator. An installed SDK and Duo runtime (27.2 on the Mac used for this gate) satisfy the archive-SDK line above. They do not by themselves prove the poses. `simctl` has no fold controls. Device Hub can drive the simulator window only when that Mac has granted assistive access; without it, fold and unfold have to be done in the Simulator UI and checked there. iPhone stays portrait-only; do not treat a missing landscape layout as a failure. Repeat the iPad poses (portrait and landscape) on an iPad simulator so the split view and side-by-side wheel are unchanged when no hinge is reported.

Poses: **closed**, **fully open**, **partially folded**.

- [ ] Partially folded, spin in progress: the hub (Spin, and Stop while it spins) is off the hinge. Unfolding recenters the wheel. The spin still lands on the slice it was going to land on.
- [ ] Fully open, and closed: the wheel is centered. No leftover shift from the previous pose.
- [ ] Fold and unfold while a movie is open, and while an episode is open. The compact stack and the regular-width split keep the same movie or episode (`MoviesView` / `EpisodesView` size-class path).
- [ ] Stats: one column in compact width; two columns from 640pt regular width; three from 1100pt.
- [ ] Movie page, including Where to Watch chips, on the outer display and the open inner display.
- [ ] Episodes list and an episode page (Listen links) on both displays.
- [ ] Sheets on the outer display, where bars are vertical: House Rules **Done**, Settings **Done**, Spin History **Clear** and **Done**, Suggest a Movie **Cancel** and **Send**. Each shows an icon. While a suggestion is sending, the trailing control reads **Sending** with the paper-plane icon and is disabled (not a bare spinner).
- [ ] Reveal sheet: partial detent then large on a compact presenter; large on a regular presenter. iPhone portrait and iPad portrait/landscape still match the pre-Duo sheet behavior when the OS reports no division region.

## Clear rating, now on this branch

`main` `18282834d20bf19537b41ba832ed69c5d3db90d0` (clear-rating, PR 15) is merged here. No Duo file overlapped that work. The Clear rating control stays the content button from that PR: title and VoiceOver label `Clear rating`, identifier `clear-rating`, half-step buttons `rating-step-1` through `rating-step-10`. It is not a toolbar item.

On this SHA, also run `MovieRouletteTuesdayUITests/ClearRatingUITests` on the installed simulator runtime. PR 15's sample destination says `OS=27.0`; use the runtime `xcrun simctl list devices available` shows (27.2 where that is what is installed).

## Out of scope for this build

- No iPhone landscape change.
- tvOS has no fold hardware. Do not port the `reservedRegions` query onto tvOS. The clearance math in `RouletteCore/AdaptiveLayout.swift` is shared and returns zero when there are no division rects, which is the tvOS result. Toolbar titles-with-icons are on the iOS sheets; if a later tvOS pass shares those sheets, give Done, Clear, Cancel, and Send the same icon labels, including the Sending label.
- Android is a separate repository.
