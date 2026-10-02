# YouTube pilot checks — October 2, 2026

| Check | Platform | Result |
| --- | --- | --- |
| Parsing and trusted-alias fixes against bundled sources | visionOS 27 simulator | PASS: 11 desktop / 7 mobile calls; both formerly malformed XHR regexes parse; exact aliases and exceptions are covered. |
| Pinned runtime removes matching fetch/XHR ad fields and preserves video details | Real WKWebView, controlled fixture on simulator | PASS: 11 desktop calls invoked, zero invocation failures; matching ad fields removed. This uses synthetic responses, not a live YouTube video. |
| Pilot off/on and unrelated-host isolation | Real WKWebView fixture / Settings persistence tests | PASS: off restores original responses, other user scripts remain; lookalike hosts invoke nothing; own toggle defaults on and persists independently. |
| Production launch / ordinary page | visionOS 27 simulator | PASS: Iris launched, loaded Google and displayed the ornament. Sign-in, scrolling and playback comparisons were not completed. |
| Live YouTube ads, overlays, captions, seek, Shorts and native fullscreen (§7.7, §7.9) | Simulator / headset | UNFINISHED: Device Hub displayed Iris but automated pointer clicks did not activate its controls, so no live YouTube page/video was reached. The paired physical headset reports unavailable. No live ad-removal result is claimed. |
| 2–3 anime sites: blank-area taps, Play, server selection, redirect logs and shield comparison (§7.1–§7.3) | Headset | UNFINISHED: actual site URLs were requested but not supplied; paired headset unavailable. Existing synthetic popup/redirect policy tests pass, but these are not anime-site acceptance results. |
| Apple environments, gaze/pinch, sustained smoothness and temperature (§7.9, §7.13) | Headset | UNFINISHED: requires the connected headset and the workload in HEADSET_CHECKS.md. |

The full local suite passed (55 passed, one optional live-filter download skipped, zero failures). Simulator and signed Release device builds passed without build warnings. The latest installable app is `/tmp/iris-headset-build/Build/Products/Release-xros/Iris.app`; it has not been installed on the unavailable headset.

To finish, connect and unlock/wear the paired Vision Pro and supply the 2–3 anime URLs. Follow the single checklist in HEADSET_CHECKS.md. For YouTube, first establish that a particular video actually serves an ad with both blocking controls off; reload with global blocking and the pilot on. Compare pilot off/on while leaving the global shield on as a separate test. Record each page's `YouTubeScriptlets` invocation/failure log and any anti-adblock wall. A play that happens to serve no ad is inconclusive; an invocation log alone does not establish removal. Restore both controls on afterward.
