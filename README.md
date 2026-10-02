# Iris v1

Native SwiftUI/WebKit browser for Max's Vision Pro. `project.yml` is the source of truth; generated Xcode projects are ignored.

## Build and install

1. Install Xcode 27 and its visionOS 27 SDK/simulator.
2. Replace `YOUR_TEAM_ID` in `project.yml` → `settings.base.DEVELOPMENT_TEAM` with your Apple developer team ID.
3. Run `brew install xcodegen` if needed, then `xcodegen generate`.
4. Open `Iris.xcodeproj`, select your paired headset and run Iris. Signing is automatic; bundle ID is `com.max.iris`.

Run `Scripts/check-phase.sh final` to regenerate, build and test on the Apple Vision Pro simulator. Use `IRIS_LIVE_FILTERS=1 Scripts/check-phase.sh live` for the optional full seven-list network/conversion/WebKit compilation check. Normal unit tests make no live filter downloads.

This Mac now has Xcode 27.0, Swift 6.4 and the visionOS 27.0 SDK/runtime. Device and simulator SDK builds pass without build warnings, and all 26 tests pass on visionOS 27, including the live filter check. The test script selects the latest installed simulator OS. The paired headset runs visionOS 27.0.1; signing and headset acceptance checks remain. See `VALIDATION.md`. Homebrew could not be installed without administrator access, so this session generated the project with the official XcodeGen 2.46.0 release at `/tmp/iris-tools/xcodegen/bin/xcodegen` (`IRIS_XCODEGEN` can select that executable).

## Controls

The star's primary action saves/removes the current site. Its menu saves an offline copy. Saved Sites offers search and context-menu actions for rename, offline open and deletion. Archives capture loaded page resources, not an entire website or its streaming videos.

The shield disables ad/tracker rules for the current registrable domain, including its subdomains. Settings controls global blocking, saved popup/redirect exceptions, filter updates and website data clearing. Disabling the shield leaves the popup/redirect guard active.

Watch requires a tap. Settings → **Use website native fullscreen** chooses the native path (default); switch it off to compare the AVPlayer handoff. Handoff uses a direct MP4/MOV/M4V/HLS URL or an HLS request observed in the same video frame, without stream extraction. Closing the player transfers its position back to that video. Native fullscreen may require using the video's own on-page control if the website/browser requires a DOM user gesture.

## Implementation notes and limits

- Phase 0 was skipped as requested. Both Phase 3 paths are built; no headset fullscreen/environment result is assumed.
- WebKit exceptions do not apply across rule lists. The per-site shield removes/reattaches compiled lists before navigation instead of using a separate ineffective `iris-allow` list. Source-list exception rules are included in each conversion shard.
- Converter 4.3.0's Safari autodetection defaults to Safari 13 on visionOS. Iris explicitly requests its Safari 26 format and uses a conservative 49,000-rule shard ceiling. The exact visionOS 27 ceiling is unverified.
- WebKit's public `createWebArchiveData` callback is bridged to async Swift; no nonexistent async overload is used.
- Known limits remain from PLAN.md §7: uBO scriptlets/extended CSS are deferred, YouTube ads and anti-adblock pages can get through, MSE without observed HLS and DRM do not hand off, and sources requiring a Referer header may fail.
- The isolated gesture probe records trusted link destinations before page click handlers run. A separate page-world popup bridge reports blocked attempts and never authorizes navigation. Same-site navigation, submitted forms and the specified sign-in hosts retain the plan's exceptions.
- Four-window ownership/release is tested; real smoothness, gaze/pinch, player environments and offline operation with Wi-Fi off require headset testing.

Filter URLs, licenses and API references are recorded in `THIRD_PARTY.md`. The approved frosted glacier icon and its source layers live in `Design/Icon/`. Run `swift Scripts/generate-icon.swift` from the repository root to prepare two 1024×1024 visionOS layers and a circular preview; it preserves the generated artwork rather than recreating the old eye icon.
