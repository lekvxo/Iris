# Validation — October 1, 2026

Setup and P1.1–P1.6, P2A.1–P2A.6, P2.1–P2.4, P3.1–P3.6, P4.1–P4.4 and P5.1–P5.4 were committed individually. Phase 0 and post-v1 P2.5 were skipped as requested/in scope.

All requested phases built and ran their tests before proceeding. Initial phase checks used Xcode 26.6 / Swift 6.3.3 / visionOS 26.5 before the toolchain upgrade. The committed project remains targeted at visionOS 27, Swift language mode 6.

Follow-up validation: Xcode 27.0 (27A266a), Swift 6.4, visionOS 27.0 SDK and simulator runtime 27.0 (24M362) are installed and selected. Generic device and simulator SDK builds passed without compiler/build warnings. All 26 tests passed with zero failures and zero skips on the visionOS 27 Apple Vision Pro simulator, including the full seven-source download/conversion/WebKit compilation check. Result: `build/Logs/Test/Test-Iris-2026.10.01_21-49-34--0700.xcresult`. The paired headset reports visionOS 27.0.1 (24M372), with Developer Mode enabled.

The first runtime installation became unavailable and failed verification; replacing it through Xcode Components restored it. The cosmetic-blocking fixture now mounts beside the SwiftUI root view and allows 45 seconds for cold WebKit startup. Its original 15-second limit failed on visionOS 27; the isolated corrected test passed in 18.47 seconds, and the complete suite passed with the same blocking/removal assertions. Swift 6.4's new capture warning was fixed by explicitly assigning the weak model capture.

| Phase | Passing tests at acceptance |
| --- | ---: |
| 1 | 2 |
| 2A | 11 |
| 2B | 15 |
| 3 | 19 |
| 4 | 22 |
| 5 / final | 25 local + 1 live filter check |

Current full suite: `IRIS_XCODEGEN=/tmp/iris-tools/xcodegen/bin/xcodegen IRIS_LIVE_FILTERS=1 Scripts/check-phase.sh xcode27-final`. Omit `IRIS_LIVE_FILTERS=1` for normal offline test runs. No deployment-target override is needed. The script regenerates `project.yml` after the temporary live-test configuration.

Final result: build succeeded with no compiler/build warnings; 25 local tests passed with zero failures, plus the successful live filter check. The initial visionOS 26.5 live network check downloaded all seven filter sources, converted 155,281 compatible rules into eight shards in 2.52 seconds, and compiled them in WebKit in 6.48 seconds on this Mac's simulator. The visionOS 27 live check also passed, including cached identifier lookups. These timings are not headset performance measurements.

Verified behavior includes URL/search routing and encoding; Public Suffix List wildcard, exception, private suffix and international-domain handling; navigation policy and real WebKit delegate registration; page-world inability to forge gesture messages; scripted popup reporting and cross-site jump cancellation; WebKit cosmetic blocking and rule removal; media/DRM/MSE classification and playing-frame selection; cookie scope; SwiftData reopen/rename/delete; atomic archive storage and path validation; guarded webarchive replay; release of four web views and their coordinators/models. A production simulator launch loaded Google, displayed the ornament, and persisted all eight compiled filter shards before browsing.

## UI review fixes — October 1, 2026

A UI review after the phases found the issues below. Each fix was built and tested on the visionOS 27 simulator before its commit. Final state: build succeeded with no compiler/build warnings; 29 tests ran, 28 passed and 1 skipped (the optional live filter check), with zero failures.

| Commit | Fix |
| --- | --- |
| `2f52820` | Toolbar ornament sits above the window (`contentAlignment: .bottom`) instead of covering the top of pages. The progress bar is overlaid on its bottom edge, and the chips float over the page, so neither changes the toolbar's size. |
| `b72a203` | Load errors clear when any navigation starts; Try again retries the failing URL; WebKit's download interrupt (102) no longer shows an error card. |
| `a03c7e0` | New windows use a `WindowRequest` with a fresh id, so an already-open URL still opens a new window. Restored windows resume their last page rather than the link that opened them. |
| `e863314` | Untitled pages save under their host name. |
| `2760846` | Address field has a rounded border and restores the page address when editing ends without submitting. |
| `10b1d6d` | Confirmation before removing a saved site (star or list) or clearing website data. |
| `b8ab704` | Video notes can be dismissed, per video. |
| `749e095` | Settings lists sites with blocking turned off, each with a Turn on button. |
| `d4b93c6` | VideoProbe batches reports every 250 ms and only re-sends when the video's state changes, or after 5 s for playback time alone. New `VideoProbeTests` floods a page with 1,000 DOM changes: the old probe sent 51 reports, the new one 1–3. |
| `4ba39f9` | Allowed popups return a real child web view, so `window.opener` survives, and `window.close()` closes the popup's window. Built-in sign-in hosts may open a popup within 2 s of a trusted tap. The new `testAllowedPopupKeepsItsOpener` (real WebKit) checks the page gets a window handle and the popup has its own script message handlers; `testSignInPopupNeedsRecentTap` covers the guard rule. |

Simulator launch after the fixes: Google loaded, the toolbar sat above the window with a visible address field, and the progress bar ran along the toolbar's edge without moving it.

Known limits: "Open once" on a blocked popup still opens an unlinked window, because the page already received a failed `window.open`. For providers not on the sign-in list, use Always allow on this site and tap sign-in again. Popups that open blank and set their address afterwards remain blocked.

Headset checks for these fixes: the same new-tab link twice gives two windows; a link-opened window restores its last page after relaunch; Back after a failed load clears the error card; the toolbar stays put during loads and when chips appear; Google popup sign-in completes and the popup closes itself; aggressive sites still open nothing on blank taps; delete and clear-data prompts appear; video notes dismiss; the shield list re-enables blocking; four busy video windows stay smooth.

Simulator WebKit emits process-suspension diagnostics when fixture windows close; these are runtime system logs, not compiler warnings or failed tests.

Pending: signing with Max's team and every headset check in PLAN.md §7. Native fullscreen behavior, environments/docking, real playback/time continuity, gaze/pinch, Wi-Fi-off archives and four-window smoothness cannot be certified by these unit tests. No Phase 0 spike result has been invented.

## Local hardening — October 1, 2026

H1: AVKit playback now occupies the browser window's root content instead of a full-screen modal. The hidden WebKit view remains mounted, with hit testing and accessibility disabled and its ornament hidden, preserving its document/history for the return. Xcode 27 simulator build passed without warnings; 29 tests ran, 28 passed and the optional live filter test skipped. Environments, docking and return continuity still require headset checks (§7 video).

H2: Video preparation now has a document/session token, canceled on navigation and teardown. Validation runs after the final asynchronous duration/seek stage and rejects changed sources, protection status and manifests. Old completions cannot clear a newer preparation or present a stale player. Two regression tests hold that stage open across navigation, teardown and source changes, plus verify an unchanged preparation succeeds. Fixtures use genuine WebKit frames (constructing an empty frame caused a test-only WebKit deallocation trap; corrected). Clean build; 31 tests ran, 30 passed, optional live filter check skipped.

H3: Video detection stops observing/scanning and sending reports in background/hidden documents or during AVKit playback, resumes with a fresh scan, and slows to a 2-second batch under serious/critical thermal pressure. Unrelated DOM mutations no longer trigger full-document searches. No media is paused merely for losing focus/backgrounding. Filter refreshes defer when all windows are backgrounded or the device is hot; existing rules stay active, cold startup waits for permission to work, interrupted conversion/compilation cooperatively cancels and retries when conditions recover. Foreground windows are counted independently. The budget test checks multiple windows and cooling; the real WebKit probe test checks suppression and foreground recovery. Final clean build; all 32 tests passed, including the real seven-source download/conversion/WebKit compilation test. This is a work-budget safeguard, not proof of headset temperature or frame rate.
