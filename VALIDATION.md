# Validation — October 1, 2026

Setup and P1.1–P1.6, P2A.1–P2A.6, P2.1–P2.4, P3.1–P3.6, P4.1–P4.4 and P5.1–P5.4 were committed individually. Phase 0 and post-v1 P2.5 were skipped as requested/in scope.

All requested phases built and ran their tests before proceeding. Checks used Xcode 26.6 / Swift 6.3.3 / visionOS 26.5 because this Mac does not have Xcode 27 or its SDK. The committed project remains targeted at visionOS 27, Swift language mode 6.

| Phase | Passing tests at acceptance |
| --- | ---: |
| 1 | 2 |
| 2A | 11 |
| 2B | 15 |
| 3 | 19 |
| 4 | 22 |
| 5 / final | 25 local + 1 live filter check |

Local suite: `IRIS_XCODEGEN=/tmp/iris-tools/xcodegen/bin/xcodegen IRIS_TEST_DEPLOYMENT=26.5 Scripts/check-phase.sh final`. The optional live check was also run successfully using `IRIS_LIVE_FILTERS=1`; it is skipped by normal offline test runs.

Final result: build succeeded with no compiler/build warnings; 25 local tests passed with zero failures, plus the successful live filter check. The live network check downloaded all seven filter sources, converted 155,281 compatible rules into eight shards in 2.52 seconds, and compiled them in WebKit in 6.48 seconds on this Mac's simulator. Cached identifiers were looked up successfully. These timings are not headset performance measurements.

Verified behavior includes URL/search routing and encoding; Public Suffix List wildcard, exception, private suffix and international-domain handling; navigation policy and real WebKit delegate registration; page-world inability to forge gesture messages; scripted popup reporting and cross-site jump cancellation; WebKit cosmetic blocking and rule removal; media/DRM/MSE classification and playing-frame selection; cookie scope; SwiftData reopen/rename/delete; atomic archive storage and path validation; guarded webarchive replay; release of four web views and their coordinators/models. A production simulator launch loaded Google, displayed the ornament, and persisted all eight compiled filter shards before browsing.

Simulator WebKit emits process-suspension diagnostics when fixture windows close; these are runtime system logs, not compiler warnings or failed tests.

Pending: Xcode 27 / visionOS 27 build, signing with Max's team, and every headset check in PLAN.md §7. Native fullscreen behavior, environments/docking, real playback/time continuity, gaze/pinch, Wi-Fi-off archives and four-window smoothness cannot be certified by these unit tests. No Phase 0 spike result has been invented.
