# Iris blocking review — October 2, 2026

## Task 3: exceptions reviewed before policy changes

The findings below were reported to Max before adding rejection logging. No exception or navigation decision was changed. `NavigationGuard` now logs every rejection through OSLog (`com.max.iris`, category `NavigationGuard`), including popup/redirect, destination URL, source page URL and reason. Full URL fields are visible in Xcode's console. One attempted popup can be reported by both the existing script message and the native delegate.

| Existing exception | How an aggressive site could use it | Boundary that remains |
| --- | --- | --- |
| Sign-in hosts | Main-frame navigation to an exact provider host needs no user tap. A page could also open that provider within two seconds of any real tap, including a blank-area tap. Provider open-redirect endpoints, if available, could lead onward. | Hosts are exact matches, not suffix matches. Ordinary ad hosts and lookalike hostnames get no sign-in exception. Subframes cannot borrow it. |
| Forms | A main-frame `.formSubmitted`/`.formResubmitted` action is allowed without a trusted gesture. A scripted form submission could qualify and move to another domain. | The popup branch does not grant a form exception; subframe-to-top requests still undergo the frame check. |
| Approved server redirects | Any allowed provisional load may continue through cross-site HTTP redirects. A same-site URL could bounce to an ad host; approval is not currently tied specifically to a user tap. | Marker is scoped to the permitted `WKNavigation` and exact destination, then cleared. Known ad URLs may still be blocked by content rules. |
| User “Always allow” sites | The source site's registrable domain receives broad navigation and popup permission. A site's scripts can use it without a matching tap, and the permission persists. | It requires the user's stored permission and applies to main-frame actions; subframes cannot borrow it. It does not itself disable content rules. |
| Same-site navigation | Another subdomain of the same registrable domain is allowed. Same-site ad destinations are outside this cross-site guard. | Public Suffix List matching avoids treating unrelated tenants on listed private suffixes as one site. |

History/reload and explicit Iris loads also remain allowed. A real tapped link authorizes its target host for two seconds, so a genuine link aimed directly at an ad host can pass; the content lists must catch known ads. These are findings, not approved hardening changes.

Validation: warning-free Xcode 27 / visionOS 27 simulator build; all 50 local tests passed, optional live-download check skipped. Existing policy tests cover forms, server redirects, sign-in hosts, stored permissions, subframe denial and popup gesture boundaries. Real WebKit fixtures exercise scripted popup/redirect denial. Their console output includes destination, source and reason. Result: `build/Logs/Test/Test-Iris-2026.10.02_12-47-43--0700.xcresult`.

## Task 4: approved YouTube-only pilot

Max approved the maintained-scriptlet pilot with a license report, a separate default-on toggle, pinned runtime, per-load logging and parsing/alias tests. The GPL-3.0 finding and future closed-source App Store licensing requirement were reported before bundling; provenance, full source and notices are retained (see THIRD_PARTY.md). Global advanced conversion remains disabled.

The implemented adapter selects only YouTube source scriptlets through the existing FilterEngine, preserves its exceptions and explicitly maps the two reviewed trusted aliases. It serializes source arguments safely to repair the malformed XHR calls described below. The seven bundled filter sources provide offline initial rules; successful weekly/manual refreshes update rule data, never the pinned Scriptlets 2.3.1 library. Only six reviewed scriptlet names can run.

Allowed main-frame YouTube navigations install a document-start page-world script before allowing the load. Both native and JavaScript host checks require youtube.com or a dot-boundary subdomain. Root-to-www redirects have a host-specific plan; unrelated pages and frames do not run the catalog. Settings → YouTube ad blocking (pilot) defaults on and reloads YouTube windows when changed; global and per-site blocking choices also apply. Each load reports invoked names, mapped runtime names and failures in the page console and OSLog (`com.max.iris`, `YouTubeScriptlets`). An invocation log does not prove that a live ad response was intercepted.

The real WKWebView fixture ran all 11 desktop calls without invocation failures. Fetch and XHR ad fields were removed while video details were preserved; disabling the pilot restored the original responses, retained other user scripts and a lookalike host ran nothing. Five new tests cover both malformed regexes, escaped commas, alias restrictions, host boundaries, native exceptions, failed-refresh retention and independent toggle persistence. Full visionOS 27 suite: 55 passed, one optional network test skipped, no failures. Simulator and signed Release builds passed without build warnings.

Pilot limits: main-frame YouTube only (no third-party embeds), no continuous polling or custom overlay/skip script, no stream extraction or DRM workarounds. Same-document YouTube transitions retain the current document's hooks; rule/path changes need a reload. Website changes, anti-adblock walls and live playback require actual site verification. Current site-check outcomes are in SITE_CHECK_RESULTS.md.

### Original evaluation: why the global switch stays off

`BlockerEngine.convertChunk` passes `advancedBlocking: false` and consumes only `safariRulesJSON`. Advanced blocking was a post-v1 stretch task in PLAN.md (P2.5). Setting the flag to true produces separate `advancedRulesText`; Iris has no storage, URL lookup, scriptlet catalog or JavaScript runner for it. WebKit content rules alone cannot execute scriptlets. There is no evidence that visionOS 27 forbids the necessary public user-script API.

The existing `ContentBlockerConverter` package product already includes the Swift `FilterEngine` target. Its `FilterRuleStorage` and `FilterEngine.findAll(for:)` can select rules for a URL without another Swift dependency. However, the converter's extension runner uses a separate JavaScript runtime: `@adguard/scriptlets` 2.3.1 and, for extended CSS, `@adguard/extended-css` 2.1.1. That code is not currently bundled. For a scriptlet-only pilot, extended CSS is unnecessary. These runtime requirements are described in the [converter's extension documentation](https://github.com/AdguardTeam/SafariConverterLib/blob/v4.3.0/Extension/README.md).

### What the actual lists produced

A temporary macOS command-line probe used SafariConverterLib 4.3.0 against the exact seven compressed source files shipped in this snapshot, with advanced conversion enabled. No page scripts were injected or app configuration changed.

| Lookup | Advanced matches | Scriptlet matches |
| --- | ---: | ---: |
| `https://www.youtube.com/watch?v=fixture` | 12 | 11 |
| `https://m.youtube.com/watch?v=fixture` | 8 | 7 |
| `https://youtube.com.evil.test/watch?v=fixture` | 0 | 0 |
| `https://example.com/watch?v=fixture` | 0 | 0 |

Conversion produced 4,355 advanced rules overall. Desktop YouTube matches include setting initial player ad properties, replacing ad fields in fetch/XHR responses, pruning Shorts ad entries and suppressing a matching ad-statistics request.

Two concrete incompatibilities prevent treating this as a working switch:

- The official pinned [scriptlets 2.3.1 package](https://registry.npmjs.org/@adguard/scriptlets/-/scriptlets-2.3.1.tgz) exports `trusted-replace-fetch-response` and `trusted-replace-xhr-response`, but not the converter's `ubo-trusted-...` names. Four of the eleven matched calls use those missing names. The other seven names are present. Explicit mappings need behavior tests; stripping prefixes indiscriminately is unsafe because some uBO argument semantics differ.
- The converter's own `ScriptletParser.parse` rejects both converted XHR replacement calls with `Invalid arguments string`; their regex arguments contain embedded quotes that the generated call does not escape correctly. Nine of eleven calls parse. The adapter must preserve correctly parsed source arguments and serialize them safely, rather than executing or silently ignoring malformed converted text.

This proves conversion/lookup gaps, not live YouTube effectiveness. The [AdGuard scriptlet library](https://github.com/AdguardTeam/Scriptlets) supports uBO aliases, but the pinned-version gaps above must be addressed specifically. Converter 4.3.0 also documents limitations for broad scriptlet exceptions. That is another reason to constrain the first pilot.

### Would WKUserScript work?

In principle, yes: document-start scripts in the page content world can intercept page fetch/XHR/global properties. Apple exposes the [WKUserScript initializer with a content world](https://developer.apple.com/documentation/webkit/wkuserscript/init(source:injectiontime:formainframeonly:in:)). Iris already uses public page-world injection for popup reporting. Its isolated gesture world should remain separate.

The Safari extension runner cannot be copied unchanged: WKWebView does not provide the extension's `browser.runtime`/`browser.scripting` transport. A small native adapter must select rules, prepare safe scriptlet invocations and install a document-start `.page` user script. It must handle redirects, YouTube's same-document navigation, YouTube frames and reloads without late or repeated hooks. Host checks must match `youtube.com` or a dot-boundary subdomain, exclude lookalikes and unrelated frames, and respect global/per-site blocking choices. Turning blocking off should reload a clean document, since already-installed hooks cannot reliably be undone. Runtime code must be bundled and version-pinned; weekly downloads update rule data only.

For performance, use URL-matched hooks and existing visibility/thermal policy, with no continuous whole-page polling. Test response replacements with synthetic payloads first, then actual signed-in/signed-out YouTube videos, Shorts and native fullscreen on the headset. The pilot must preserve ordinary playback, seeks, captions, login and the user's player choice. It must not extract streams, bypass DRM or start a player automatically. Native Apple environments remain a device acceptance item.

### Smaller fallback if the pilot fails

A single `YouTubeAdCleaner.js` could run only on YouTube, hide known ad overlays and click a visible, enabled Skip ad button while the player reports an ad. A throttled, visibility-aware MutationObserver would replace constant polling. Avoid seeking based only on video duration: YouTube may use the main video's timeline, risking skipping actual content. Such a script would only skip ads when a genuine skip action is available and would not promise to remove every ad or defeat anti-adblock walls. It is simpler and adds no dependency, but relies on unstable DOM selectors and has less reach than response-level scriptlets.

HEADSET_CHECKS.md contains the comparison cases and includes first launch without a network. Simulator fixtures verify logic; headset testing is required for actual site behavior, gaze/pinch, heat, sustained smoothness and Apple environments. The current viewing experience remains the existing native window with selectable website fullscreen/AVKit handoff.
