# Iris headset acceptance — PLAN.md §7

H1–H4, Phase 6 history, bundled offline blocking and navigation logging are implemented and tested on the visionOS 27 simulator (50 local tests passed; one optional live-download check skipped). The latest signed Release build passed with Xcode 27 and includes the fallback/logging changes. The earlier installation attempt failed because the paired headset was locked; this build has not been installed on it. H5's sustained measurement and Task 4's approved YouTube implementation remain pending. No headset performance, temperature or environment result is claimed.

Unlock and wear the paired headset, then install `/tmp/iris-headset-build/Build/Products/Release-xros/Iris.app` from Xcode or with `xcrun devicectl device install app --device 00008112-000C31EC2681A01E /tmp/iris-headset-build/Build/Products/Release-xros/Iris.app`. Keep `project.yml` as the source of truth; replace `YOUR_TEAM_ID` at `settings.base.DEVELOPMENT_TEAM` for future signed builds, or supply the team as a build-command override. This session's override was `F47GC3BYK3`.

One checklist, following §7's order:

- [ ] §7.1: On 2–3 anime streaming sites you use (record each URL), test blank-area taps, Play and server-selection buttons: no unwanted popup or cross-site jump. Start without Always allow permissions; compare shield on/off and confirm the navigation guard remains active in both. Check the console's blocked URL, source page and reason.
- [ ] §7.2: Real cross-site links work; Google sign-in completes and its popup closes itself.
- [ ] §7.3: A blocked chip appears; Open once opens the intended target. Always allow permits a subsequent linked sign-in popup.
- [ ] §7.4: A word searches Google; a domain loads its site; abandoning an edit restores the address.
- [ ] §7.5: Back, forward, reload and stop work by gaze/pinch; errors clear on navigation; the ornament stays put.
- [ ] §7.6: The same new-tab link opened twice creates two windows; closing them stops their work. Unadopted popups expire instead of leaking.
- [ ] §7.7: Shield on reduces news-site ads; a per-site exception survives relaunch and can be removed in Settings. On ordinary sites, compare blocking on/off for sign-in, form submission, scrolling and video playback; record any breakage.
- [ ] §7.8: On a fresh install with Wi-Fi off, Settings shows bundled protection and a nonzero rule count without downloading lists. Reconnect and compare shield on/off on an ad-heavy page. Weekly/manual filter updates keep browsing responsive; failed updates retain protection. Cached blocking remains active while updates defer under heat/backgrounding and resume when allowed.
- [ ] §7.9: Compare both Settings video modes with direct MP4 and HLS. Verify Apple player controls, captions/audio choices when offered, environments/docking, seek continuity and return to the preserved page. Navigate/close during preparation: no late player/audio. Disconnect/reconnect networking during playback: Retry works and Back still returns. Native fullscreen on streamed/protected sites must use the website's supported path.
- [ ] §7.7, §7.9 / Task 4 pending: Record a YouTube video that serves pre-roll/mid-roll ads with blocking off, then compare blocking on. Check overlays, ad skipping, captions, seeking, signed-in/out playback, Shorts and native fullscreen. Repeat after the approved YouTube implementation lands; current native rules do not guarantee removal of video ads.
- [ ] §7.10: Unsupported video explains why Watch is unavailable; no crash. A stopped page process offers Try again; playback stalls/failures offer Retry or Back.
- [ ] §7.11: Saved sites survive relaunch. Wi-Fi-off archives open, reload and recover from a page-process stop using local data; rename/delete confirmations work.
- [ ] §7.12: Clear website data signs sites out after confirmation; saved sites stay intact.
- [ ] §7.13: Complete the 30-minute four-window profile below; confirm gaze/pinch and scrolling remain smooth, including native playback and background/foreground transitions.
- [ ] §7.11 / P6.1–P6.3: Open Saved → History. Visit and revisit pages: one entry per exact address per local day, with newest visits first and correct day headings. Popup pages and YouTube's same-page URL changes appear; failed/blocked pages and offline copies do not.
- [ ] §7.5, §7.11 / P6.3: Search by title and address, including mixed case. Tap a result to open it in this window; Delete removes only that visit. Switch back to Saved: saved sites and offline actions still work, with no additional toolbar button.
- [ ] §7.12 / P6.4: Try Last hour, Today, Today and yesterday, and All history from the History tab and Settings. History clears while sign-in cookies/saved sites/offline copies remain. Clear website data signs you out while keeping history. Back/Forward still work in existing windows until they close.
- [ ] §7.11 / P6.4–P6.5: Relaunch: visits and the retention choice persist. Default retention is 1 year; compare 1 month and Forever. Older entries prune on launch according to the chosen setting.
- [ ] §7.13 / P6.3: Check search, scrolling and segment switching by gaze/pinch with four browser windows. Phase 7 waits for these Phase 6 headset checks.

## 30-minute measurement

Use the signed Release build on the headset, starting from a stable temperature. Keep the headset unlocked and connected to this Mac. Once Iris is open, run:

```sh
Scripts/profile-headset.sh 00008112-000C31EC2681A01E
```

This records RealityKit frame/hitch data, Time Profiler, Activity Monitor and Thermal State across all processes, including WebContent/GPU. Xcode 27 accepted this instrument configuration via `xctrace --show-recording-options`. The default trace lives under ignored `build/Profiles/`; open it in Instruments after recording. The script does not launch or automate the workload.

Minutes 0–5: one window, baseline reading/scrolling. Minutes 5–15: four representative busy pages; scroll, load links and switch focus. Minutes 15–25: keep the four windows open while playing direct MP4/HLS through AVKit, test an environment/docking and returning; compare website fullscreen. Minutes 25–30: close/reopen windows, background/foreground Iris, and retry interrupted playback.

Record sites/video sources, starting/ending thermal state, CPU by Iris/WebContent/GPU, memory trend before/after closing windows, frame/hitch intervals, and any audio/return problems with timestamps. Distinguish the sampling overhead and website work from Iris's own main-thread stacks. Investigate sustained serious/critical thermal state, recurring hitches, continuing idle detector/filter work, or memory that grows on each close/reopen cycle. An empty/idle recording cannot certify this workload.

Unfinished: Task 4 implementation approval, Task 5's subsequent site-testing pass, the actual recording and all unchecked device acceptance items. Known v1 limits in PLAN.md still apply, including scriptlets, website-dependent fullscreen/DRM behavior and HLS sources requiring unavailable request headers. Simulator coverage verifies offline blocking, delegate decisions and other logic; use the headset for the site/video and sustained-performance checks above.
