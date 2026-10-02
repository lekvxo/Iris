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
