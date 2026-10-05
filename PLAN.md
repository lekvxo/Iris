# Vision Pro Browser: Build Plan for GPT-6.1 Sol

Oct 1, 2026 · @Max

## 1. Read first: build on WebKit, not Chromium

This app is a native visionOS browser built on WKWebView, with uBlock Origin's filter lists compiled into WebKit's content blocker, plus a native guard that stops popups and redirects the user did not ask for. That guard is the top priority. Sol must not attempt a Chromium or Blink port.

Why Chromium is off the table:

- No Chromium build exists for visionOS. On iOS, a non-WebKit engine needs BrowserEngineKit, offered only in the EU and Japan, and as of June 2026 no browser maker has shipped one; Microsoft has only a research prototype ([MacRumors](https://www.macrumors.com/2026/06/17/webkit-rule-costs-ios-users-browser-performance/), [Apple BrowserEngineKit docs](https://developer.apple.com/documentation/browserenginekit)).
- A Chromium checkout plus build needs 100+ GB of disk and many hours of compiling. On a fanless M4 MacBook Air it would throttle for days, and porting Blink to visionOS is a multi-engineer, multi-year job.
- uBlock Origin the extension would not run anyway. It is a Manifest V2 extension, Chrome has removed MV2 support, and Chromium builds on Apple platforms have no extension system.

How each goal is still met:

| Goal | How it works on WebKit |
| --- | --- |
| No Safari | Own app, own WKWebView, own UI and data. Safari never opens. |
| uBlock Origin blocking | Same lists uBO uses (uBO filters, uBO Privacy, uBO Badware, EasyList, EasyPrivacy, Peter Lowe) converted to WebKit content rules. Network and cosmetic blocking run natively inside WebKit. |
| Google search | Address bar sends non-URL text to Google search. |
| Apple video player | Detected video is handed to AVPlayerViewController, which supports visionOS environments and docking. |
| Save websites | SwiftData bookmarks with optional offline copy. |
| Popup and redirect blocking (main focus) | Native guard in the web view's delegates. Scripted popups and jumps to other sites the user did not click are stopped, with a one-tap allow. |

Honest gap: content rules catch most of what uBO blocks on normal sites, but not uBO's scriptlets. YouTube in-page ads and anti-adblock walls are the main misses.

## 2. Project setup (Max does this)

Name: **Iris**. Xcode is installed and the Iris folder exists, so steps 1, 2 and 5 below reflect that.

Setup steps on the MacBook Air M4:

1. Xcode is installed. Open **Xcode > Settings > Components** and confirm the visionOS 27 platform and simulator are installed.
2. Your Iris folder already exists. Nothing to do here.
3. **Xcode > File > New > Project**, choose the **visionOS** tab, pick **App**, click **Next**.
4. Fill in: Product Name `Iris`, Team = your developer team, Organization Identifier `com.yourname`, Initial Scene **Window**, Immersive Space Renderer **None**, Immersive Space **None**. Click **Next**.
5. In the save dialog, select your existing Iris folder, tick **Create Git repository on my Mac**, click **Create**. Xcode makes an inner Iris folder holding `Iris.xcodeproj`. That inner folder is the project root.
6. In the left Project navigator, click the blue **Iris** project, select the **Iris** target, open **Signing & Capabilities**, confirm **Automatically manage signing** is on and Team is set. A paid developer account keeps builds alive for a year; a free Apple ID expires every 7 days.
7. Add the filter converter: **File > Add Package Dependencies**, paste `https://github.com/AdguardTeam/SafariConverterLib`, use the latest release, add the **ContentBlockerConverter** product to the Iris target.
8. Pair the headset: on Vision Pro open **Settings > General > Remote Devices**; on the Mac open **Xcode > Window > Devices and Simulators** and pair. Then on Vision Pro turn on **Settings > Privacy & Security > Developer Mode** and restart.
9. Export this doc as Markdown, save it as `PLAN.md` in the project root, and commit it. Then in **Terminal**, `cd` into the project root, run `codex`, pick GPT-6.1 Sol with `/model`, and send: *Read PLAN.md, follow section 3, start Phase 0.*

## 3. Instructions for Sol in Codex

You are the architect and coder for Iris, running in Codex. Work one phase at a time from section 6 in this order: 0, 1, 2A, 2B, 3, 4, 5. Finish each phase's acceptance checks, then stop for Max to test on device. Save this section as AGENTS.md in the project root so every new Codex session loads it.

**Role**

- You have shell access in the project root. Edit files, build and run tests yourself, one small task at a time, each with a check that proves it works.
- Make surgical edits. Never rewrite a working file wholesale, never reprint whole files in replies. Max has limited API credits.
- When unsure an API exists on visionOS 27, check Apple's docs before writing code. If it does not exist, stop and report instead of inventing one.

**Stack rules**

- Swift 6, SwiftUI, visionOS 27 deployment target, Xcode 27.
- WKWebView and AVPlayerViewController through `UIViewRepresentable` / `UIViewControllerRepresentable`.
- Only third-party dependency: SafariConverterLib (ContentBlockerConverter). Persistence: SwiftData.
- Never: Chromium or Blink, private APIs, YouTube stream extraction, DRM workarounds, auto-hijacking video without a user tap.

**Build and commit loop**

1. Find the simulator name: `xcrun simctl list devices | grep -i vision`
2. Build: `xcodebuild -project Iris.xcodeproj -scheme Iris -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build`
3. A task is done only when the build succeeds with no new warnings and its acceptance check passes.
4. Commit per task: `git add -A && git commit -m "P2.3: search routing"`.
5. End of each phase: list what Max should test on the headset, then wait. The simulator cannot verify video environments, real performance, or gaze and pinch feel.

## 4. Scope

v1 is one simple browser window with ad blocking, Google search, a Watch in Player button, and saved sites. Everything else waits. v1 targets Max's own headset; App Store prep comes later.

**In v1**

- Window with a top ornament: back, forward, reload or stop, address bar, save, saved list, Watch in Player, shield toggle.
- Popup and redirect guard (main focus): scripted popups, popunders and click hijacks to other sites are blocked, with a one-tap allow.
- Address bar: URL text loads the site; anything else becomes a Google search.
- Links that open a new tab open a new Iris window instead.
- Ad and tracker blocking from uBO's default lists, refreshed weekly, with a per-site off switch.
- Watch in Player for videos with a direct or HLS source, playing in AVPlayerViewController with environments.
- Saved sites: save, list, open, rename, delete; optional offline copy.
- Settings: blocking on/off, popup and redirect allowlist, list update now, clear website data.

**Not in v1**

- Tabs strip, history view, downloads, passwords and autofill, sync, extensions, private mode, spatial or immersive browsing, search engines other than Google.

## 5. Architecture and files

Each window owns one WKWebView. Blocking, video handoff and saving all attach to it; the only other network traffic is the weekly filter list download.

&#91;embedded content: Iris architecture: 8 components around one web view\]

BlockerEngine compiles lists once at launch, and every new web view gets them before its first page load.

```
Iris/
  IrisApp.swift            WindowGroup(id: "browser", for: URL.self), SwiftData container
  Browser/
    BrowserWindow.swift    window view + toolbar ornament
    BrowserModel.swift     @Observable page state
    WebView.swift          WKWebView wrapper and delegates
    InputRouter.swift      URL vs Google search
  Blocking/
    NavigationGuard.swift  popup and redirect rules, blocked chip state
    GestureProbe.js        records real link clicks
    PublicSuffix.swift     registrable domain (eTLD+1) lookup
    FilterLists.swift      list sources, download, cache
    BlockerEngine.swift    convert, compile, attach, allowlist
  Video/
    VideoProbe.js          injected video detector
    VideoBridge.swift      message handler and classification
    PlayerView.swift       AVPlayerViewController wrapper
  Saved/
    SavedSite.swift        SwiftData model
    SavedListView.swift    popover list
    ArchiveStore.swift     .webarchive files
  Settings/
    SettingsView.swift
IrisTests/
  InputRouterTests.swift
  NavigationGuardTests.swift
```

## 6. Build phases

Seven phases in order 0, 1, 2A, 2B, 3, 4, 5, each ending in a device test. Phase 2A, the popup and redirect guard, is the main focus. Phase 0 is a one-day spike that can shrink Phase 3, so do it first.

### Phase 0: Spikes (answer two questions before building)

1. **P0.1 Native fullscreen test.** Minimal window with a WKWebView loading a page with a plain HTML5 `<video>` (direct MP4) and a YouTube video. Config: `allowsInlineMediaPlayback = true`, `preferences.isElementFullscreenEnabled = true`, `mediaTypesRequiringUserActionForPlayback = []`. Max taps the video's fullscreen button on the headset and records: does it open Apple's player, and can he pick or dock into an environment?
   - If yes, Watch in Player becomes a JS call to `video.webkitEnterFullscreen()`. That path also works for YouTube and other MSE sites, and Phase 3 drops to a day.
   - If no, build the full handoff in Phase 3.
2. **P0.2 Blocker test.** Download uBO filters and EasyList, convert with ContentBlockerConverter, compile with `WKContentRuleListStore`. Log rule count, conversion time and compile time on the headset. Confirm the per-list rule cap on visionOS 27.

Done when: both results are written into PLAN.md under a "Spike results" heading.

### Phase 1: Browser core

1. **P1.1 `BrowserModel`** (`@Observable`): url, title, canGoBack, canGoForward, isLoading, estimatedProgress, fed by KVO on the WKWebView.
2. **P1.2 `WebView.swift`** (`UIViewRepresentable`): `preferredContentMode = .desktop`, back and forward swipe gestures on, default website data store, `WKNavigationDelegate` and `WKUIDelegate` set.
3. **P1.3 Toolbar ornament**: `.ornament(attachmentAnchor: .scene(.top))` holding back, forward, reload or stop, address bar, save, saved list, Watch in Player, shield. Use `.glassBackgroundEffect()` and hover effects on every button.
4. **P1.4 `InputRouter.swift`**: text with http or https scheme loads as is; text with no spaces, a dot and a valid host loads with `https://` added; `localhost` loads; everything else goes to `https://www.google.com/search?q=` built with `URLComponents` query items. Unit tests: `apple.com`, `how to cook rice`, `news.ycombinator.com/item?id=1`, `1+1`, `localhost:3000`. Field uses `.keyboardType(.webSearch)`, no autocorrect, no autocapitalization, `.submitLabel(.go)`, selects all text on focus.
5. **P1.5 New windows**: `WindowGroup(id: "browser", for: URL.self)`. In `createWebViewWith`, call `openWindow(id: "browser", value: url)` and return nil, so `target=_blank` and `window.open` open a new Iris window.
6. **P1.6 Basics**: Info.plist `NSAppTransportSecurity > NSAllowsArbitraryLoadsInWebContent = YES`; home page is Google; `@SceneStorage` restores each window's last URL; simple error page for failed loads.

Done when: Max can search, browse, go back and forward, and open a new-tab link into a second window on the headset.

### Phase 2A: Popup and redirect guard (main focus)

Content rules cannot stop scripted popups or click hijacks, so this guard lives in Swift, in the web view's delegates. The rule: a new window or a jump to another site happens only when the user clicked a real link to that site.

1. **P2A.1 Block scripted popups.** Set `preferences.javaScriptCanOpenWindowsAutomatically = false`. In `createWebViewWith`, open a new Iris window only when `navigationAction.navigationType == .linkActivated` and the source is the main frame. Script `window.open`, popunders fired on any page click, and any popup from an iframe all return nil.
2. **P2A.2 `GestureProbe.js`** as a `WKUserScript` in the main frame at document start: on `pointerdown` and `click` in the capture phase, record the time and, if the target sits inside an `<a>`, its resolved `href`. Post to `webkit.messageHandlers.irisGesture`; native keeps the last gesture per window.
3. **P2A.3 Redirect rules** in `decidePolicyFor navigationAction`, comparing registrable domains (eTLD+1, so `news.bbc.co.uk` counts as `bbc.co.uk`):
   - Allow: same site; back, forward, reload; address bar and saved-site loads (flag these natively); form submits; cross-site loads whose host matches the link just clicked, within 2 seconds.
   - Allow server redirects that continue a navigation already allowed (track it through `didReceiveServerRedirectForProvisionalNavigation`).
   - Block: cross-site main-frame loads with no matching click (timers, location changes after a click on a non-link, click handlers that swap the destination), and any iframe trying to move the top window to another site.
4. **P2A.4 Blocked chip.** On a block, show a small chip in the ornament, such as *Blocked popup to example.com* or *Blocked redirect to example.com*, with **Open once** and **Always allow on this site**. Never a modal.
5. **P2A.5 Allowlists.** Per-site "allow popups and redirects" stored in SwiftData and editable in Settings. Built-in exceptions for sign-in hosts (accounts.google.com, appleid.apple.com, login.microsoftonline.com, github.com) so OAuth flows work.
6. **P2A.6 Domain logic and tests.** eTLD+1 needs the Public Suffix List: bundle the list file (MPL 2.0) and parse it in `PublicSuffix.swift`. `NavigationGuardTests` covers same-site, cross-site with matching click, cross-site without click, iframe top navigation, server redirect chains and allowlisted hosts.

Phase 2B's lists add a second net: they block top-level loads of known ad and malware domains, catching hijacks that pass this guard.

Done when: on a few aggressive streaming and file-host sites, clicking anywhere on the page opens nothing and never leaves the site unless a real link was clicked; Google sign-in still works; the chip opens a blocked target in one tap.

### Phase 2B: Ad blocking with uBO lists

1. **P2.1 `FilterLists.swift`**: sources downloaded at runtime to Application Support (not bundled; the lists are GPL and CC BY-SA). Verify each URL against `assets.json` in the uBlockOrigin/uAssets repo before using it:
   - uBO filters `https://ublockorigin.github.io/uAssets/filters/filters.txt`
   - uBO Privacy `.../privacy.txt`, uBO Badware `.../badware.txt`, uBO Unbreak `.../unbreak.txt`
   - EasyList `https://easylist.to/easylist/easylist.txt`, EasyPrivacy `https://easylist.to/easylist/easyprivacy.txt`
   - Peter Lowe's list (Adblock Plus format)
2. **P2.2 `BlockerEngine`** (an `actor`): convert all lists with ContentBlockerConverter, split output under the rule cap, compile as `iris-1`, `iris-2` and so on. On launch, `lookUpContentRuleList` the cached ones and attach them to each web view's `userContentController` before its first load. Never block the UI thread.
3. **P2.3 Refresh**: if the last update is older than 7 days, refresh in a background `Task` on launch, then swap lists on open web views. Settings has Update now.
4. **P2.4 Per-site off switch**: a last rule list `iris-allow` with one `ignore-previous-rules` rule per allowed domain. Shield button toggles the current host, recompiles only that small list, reloads.
5. **P2.5 Stretch, after v1**: the converter's advanced rules (scriptlets, extended CSS) via `WKUserScript`. This is what would close part of the YouTube gap.

Done when: an ad-block test page and a busy news site show clearly fewer ads with the shield on than off, and pages do not load slower.

### Phase 3: Watch in Player

If P0.1 passed, implement only step 6. Otherwise do steps 1 to 5.

1. **P3.1 `VideoProbe.js`** as a `WKUserScript` at document end in all frames: listen for `play` in the capture phase, read `currentSrc`, `currentTime`, `duration`; wrap `fetch` and `XMLHttpRequest.open` to note URLs ending in `.m3u8` or `.mp4`; post to `webkit.messageHandlers.irisVideo`.
2. **P3.2 Classify**: http(s) MP4, MOV, M4V or M3U8 is playable; `blob:` with a captured M3U8 plays that M3U8; `blob:` without one is unsupported (MSE); an `encrypted` event or set `mediaKeys` means DRM, unsupported. The button is disabled with a short reason when unsupported.
3. **P3.3 Build the asset**: pause the web video by JS, collect cookies for the host from `httpCookieStore`, create `AVURLAsset` with `AVURLAssetHTTPCookiesKey` and `AVURLAssetHTTPUserAgentKey` set to the page's user agent. Sites that require a Referer header will fail; accept that.
4. **P3.4 Play**: present `AVPlayerViewController` full window, seek to the page's `currentTime`, set the page title as metadata, play. visionOS gives this player its environments and docking.
5. **P3.5 Return**: on dismiss, write the player's time back to the web video by JS.
6. **P3.6 Native path (if P0.1 passed)**: Watch in Player runs `document.querySelector('video')?.webkitEnterFullscreen()` on the playing video. Keep P3.2's DRM check for the label only.

Done when: a direct MP4 and one of Apple's public HLS example streams open in the player with environments and resume at the right time; YouTube behaves as P0.1 predicted.

### Phase 4: Saved sites

1. **P4.1 SwiftData model `SavedSite`**: id, url, title, note, createdAt, lastOpened, archiveFileName (optional). Model container set up in the App struct.
2. **P4.2 Save button**: star fills when the current URL is saved; its menu adds Save offline copy, which writes `createWebArchiveData` output to `Application Support/Archives/<id>.webarchive`.
3. **P4.3 Saved list**: popover from the ornament with search, tap to open in the current window, context menu to rename, open offline copy, or delete (deleting also removes the archive file).
4. **P4.4 Offline open**: `load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: url)`.

Done when: saved sites survive an app relaunch and an offline copy opens with Wi-Fi off.

### Phase 5: Polish

1. Settings sheet: blocking on or off, Update lists now with last-updated date, Clear website data (`removeData` for all types since `.distantPast`).
2. Thin load progress bar under the ornament.
3. Release each web view when its window closes; check memory with 4 windows open.
4. App icon: visionOS layered icon, three 1024 x 1024 layers in Assets.

Done when: the section 7 checklist passes on the headset.

## 7. Device checklist, limits and shipping

v1 is done when every box below passes on the headset.

- [ ] Clicking blank areas on aggressive sites opens no popup and never leaves the site
- [ ] A real link to another site still works; Google sign-in still works
- [ ] Blocked chip appears and Open once loads the target
- [ ] Typing a word searches Google; typing a domain opens the site
- [ ] Back, forward, reload and stop work by gaze and pinch
- [ ] A new-tab link opens a tab in the same Iris window (October 4 scope update below)
- [ ] News site shows clearly fewer ads with shield on; shield off for one site sticks after relaunch
- [ ] Filter lists refresh after 7 days without freezing the UI
- [ ] Direct MP4 and HLS video open in Apple's player with environments and resume at the right time
- [ ] Unsupported video shows a disabled button with a reason, never a crash
- [ ] Saved sites survive relaunch; an offline copy opens with Wi-Fi off
- [ ] Clear website data signs you out of sites
- [ ] Four windows open at once stay smooth

**Known limits**

- The redirect guard judges by the click. If a site's real link itself points at an ad host, the click goes through; the 2B lists block the known ones.
- Content rules match most uBO network and cosmetic blocking, not scriptlets. YouTube ads and anti-adblock walls may get through.
- Without the native fullscreen path, MSE sites (YouTube, Twitch, most big platforms) and DRM services (Netflix, Disney+) cannot hand off to the player.
- Some HLS sources need a Referer header that public AVFoundation APIs cannot send.

**Shipping**

- Personal use: install from Xcode to the paired headset. This is the current target. A paid developer account keeps it working for a year.
- Later, if Iris goes public: a WebKit browser with content blocking is allowed. Download filter lists at runtime rather than bundling them, and do not add stream extraction for YouTube or DRM sites, which review will reject.

## October 4 headset feedback: scope amendment

Max now requests tabs in one browser window, replacing the original P1.5/§7.6 new-window behavior. Approved new-window links adopt their real WebKit views into tabs, preserving OAuth opener communication. Tabs can be pinned and restored; hidden-tab video pauses. Browser controls reserve space above the website. Google's desktop Safari layout and dark appearance replace its bare-WebKit fallback.

The supplied blue/violet logo replaces the frosted icon and nearly fills its circular mask. Playback work adds a stable constrained WebKit host, browser-size restoration and a Reset window size action. Max confirmed dark appearance; the rejected custom Cinema environment has been removed. Tab links, pins and selection now recover from durable local SwiftData storage after closing Iris. Both subsequent native-caption adapters failed on Max's headset. The native fullscreen entry is restored exactly to pre-caption commit `6e77e61`, with no track/cue/controls mutations or fullscreen API overrides; only passive diagnostics remain for the user-reported working mini-player path. The separate AVPlayer handoff requires a matching native subtitle track; website-only subtitles remain a handoff limit. Miruro/Moon visibility, playback continuity and closed-window recovery require the updated headset checks; unit tests cannot certify the immersive compositor.

Apple documents Cinema within its TV app, and no public visionOS API to open that environment was found. Iris continues using AVKit's available system environments. Sources: https://support.apple.com/guide/apple-vision-pro/watch-movies-and-tv-in-an-environment-tan7241583f5/visionos and https://developer.apple.com/documentation/visionos/building-an-immersive-media-viewing-experience.
