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

Simulator WebKit emits process-suspension diagnostics when fixture windows close; these are runtime system logs, not compiler warnings or failed tests.

Pending: signing with Max's team and every headset check in PLAN.md §7. Native fullscreen behavior, environments/docking, real playback/time continuity, gaze/pinch, Wi-Fi-off archives and four-window smoothness cannot be certified by these unit tests. No Phase 0 spike result has been invented.
