# Iris: Next Plan

Oct 1, 2026 · @Max

Two additions after v1, in this order: history with search, then stronger ad protection. Proton VPN stays in Proton's own app, so Iris has no VPN work. Goal: keep the window calm. **No new toolbar buttons.** Work rules are the same as AGENTS.md: one task at a time, build with no warnings, tests pass, commit per task, stop for a headset test at the end of each phase.

Out of scope, by Max's choice: a VPN inside Iris, dragging links out into windows, downloads, private windows, tabs, extra stats or counters.

## Phase 6: History with search

History stays on the headset only (SwiftData, no sync). It lives in the existing Saved popover, so the toolbar doesn't change.

1. **P6.1 Model.** `HistoryEntry` (`@Model`): `url`, `title`, `host`, `visitedAt`. Store one row per URL per day: a repeat visit on the same day updates `visitedAt` and `title` instead of adding a row. Register it in the `ModelContainer` in `SettingsStore`.
2. **P6.2 Recording.** Add a small `HistoryStore` on `SettingsStore` with `record(url:title:)`.
   - Record on `didFinish` for main-frame loads, and on same-page URL changes (KVO on `url` while not loading), so sites like YouTube that change pages without a full load still show up.
   - Update the latest entry's title when the title arrives after `didFinish`.
   - Don't record: offline-copy loads (`nativeArchiveDestination`), non-http(s) URLs, failed loads, blocked navigations, `about:blank`.
   - Popup windows record like any other window.
3. **P6.3 History list.** Add a segmented control at the top of the Saved popover: **Saved | History**.
   - History shows newest first, grouped under Today, Yesterday, then weekday names, then dates.
   - Each row shows the title, the host and the time. Tapping a row opens it in the current window. The context menu has Delete.
   - Search with `.searchable`. Match the title or URL using a `#Predicate` with `localizedStandardContains`. Without a search, fetch at most the last 500 entries to keep the list fast.
4. **P6.4 Clear history.**
   - A **Clear…** button at the bottom of the History tab opens a confirmation dialog: Last hour / Today / Today and yesterday / All history.
   - Settings gets a **History** section with the same Clear… dialog.
   - Optional: a "Keep history for" picker (1 month, 1 year, forever; default 1 year) that prunes old entries at launch.
   - Clearing history leaves website data alone, and Clear website data leaves history alone. Both say so in their footer text.
5. **P6.5 Tests.**
   - One row per URL per day.
   - Skipped URL types are never recorded.
   - Each clear range deletes exactly the right rows.
   - Search matches title and URL, case-insensitive.
   - Pruning respects the "keep" setting.

Known limit: WebKit has no public way to wipe an open window's back/forward list, so Back still works in open windows after clearing. History is clean after those windows close.

Done when: visited pages appear in History grouped by day, search finds them by title or address, each Clear option removes the right range, and history survives a relaunch.

## Phase 7: Stronger ad protection

Today Iris converts seven lists with `advancedBlocking: false` (`BlockerEngine.swift`), which leaves out uBO's scriptlets and advanced CSS. That's the main reason YouTube ads and anti-adblock walls get through.

1. **P7.1 More lists** (`FilterLists.swift`): add **uBO Quick fixes** (`https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt`, which changes often and fixes breakage fast) and **URLhaus malicious URLs** (malware hosts). Check each URL against uBO's `assets.json` first, as in P2.1.
2. **P7.2 Optional cookie and annoyance lists.** One Settings toggle, **Hide cookie banners and pop-overs**, off by default. When on, it adds uBO's cookie and annoyance lists. These sometimes break sites, so it stays opt-in.
3. **P7.3 Faster refresh.** Check lists **daily** instead of weekly (`needsRefresh` in `BlockerEngine.swift`). Send `If-None-Match` / `If-Modified-Since` so unchanged lists aren't downloaded again. Only recompile when a list actually changed. Keep the H3 energy rule: refreshes wait while `BlockerController.workAllowed` is false (Iris in the background or the headset hot), and compilation stays off the main thread.
4. **P7.4 Spike: advanced rules in a WKWebView** (half a day, then decide). SafariConverterLib's documented path for scriptlets is a Safari Web Extension; there is no WKWebView guidance. Check:
   - whether `convertArray(..., advancedBlocking: true)` plus the package's `FilterEngine` can be built into the app target and asked "which advanced rules apply to this URL";
   - whether injecting AdGuard's scriptlets bundle as a page-world `WKUserScript`, updated in `decidePolicyFor` before the main-frame load commits, runs early enough to beat the page's own scripts;
   - test on a YouTube video page and two anti-adblock news sites.

   Write the result into this file. The scriptlets bundle (`@adguard/scriptlets`, GPL-3.0) would be a second third-party piece, so Max approves it and THIRD_PARTY.md is updated before anything ships.
5. **P7.5 Build the advanced path** only if P7.4 passes. Scriptlets and advanced CSS are applied per site; the shield's per-site off switch turns them off too.

Free extra layer, no Iris work: in the Proton VPN app on the headset, turn on **NetShield** (block malware, ads and trackers). It blocks those domains at the DNS level for everything on the headset, which catches some requests WebKit's rules miss.

Honest limit: even with scriptlets, YouTube ad blocking is cat-and-mouse. Expect it to break now and then until the lists catch up.

Done when: a busy news site and an ad-block test page show fewer ads than v1, pages load no slower, nothing obvious breaks, and P7.4's result is recorded.

## Suggested order

1. Phase 6 (history): self-contained, about a day.
2. P7.1–P7.3 (lists and refresh): small, safe gains, about half a day.
3. P7.4 spike, then P7.5 only if it passes.
4. Anytime: turn on NetShield in the Proton app.
