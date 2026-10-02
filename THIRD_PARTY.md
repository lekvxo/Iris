# Sources

- Public Suffix List: https://publicsuffix.org/list/public_suffix_list.dat, fetched October 1, 2026. MPL 2.0; license notice remains in the bundled file.
- SafariConverterLib 4.3.0: https://github.com/AdguardTeam/SafariConverterLib. GPL 3.0. Its transitive packages are managed by SwiftPM; no other direct dependency is added.
- Filter source URLs were checked against https://github.com/gorhill/uBlock/blob/master/assets/assets.json on October 1, 2026. EasyList and EasyPrivacy now use the uAssets canonical mirrors listed there. Peter Lowe's canonical hosts list is translated into ABP network rules at runtime. Downloaded list files retain their notices; lists are not bundled.
- Safari content-rule exceptions apply within each compiled list, not across lists. Iris must append its site exceptions to every compiled shard; a final separate `iris-allow` list alone cannot disable other shards. https://github.com/AdguardTeam/SafariConverterLib#safari-affinity

Apple APIs checked: WKPreferences.isElementFullscreenEnabled, WKWebView.callAsyncJavaScript, WKWebView.createWebArchiveData, AVURLAssetHTTPUserAgentKey. Installed SDK is visionOS 26.5; visionOS 27 validation remains pending.
