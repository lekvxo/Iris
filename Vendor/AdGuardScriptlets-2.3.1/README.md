# Pinned AdGuard Scriptlets 2.3.1

GPL-3.0. Original package integrity: `sha512-E60vnKYv4GIlvtAVriyf3SYZk/u10shlfogTJFQa8ZKS2HHMuRAUTk8Msn42mycmD/Kf9P9J17l1SvgwVJ+otg==` (verified against npm's official version metadata).

`npm-package.tgz` is the exact published package. `source.tar.gz` is the complete official GitHub source at `c75c18fd95de614c733d9db285fb0daa9835028b` / `v2.3.1`, including its build inputs, lockfiles and license. `Iris/Resources/YouTubeScriptlets` contains the unchanged LZFSE-compressed `dist/scriptlets/index.js`, a SHA-256 manifest, notices and the GPL text. The dependency-free catalog avoids adding a Node/npm runtime to Iris.

To reproduce the bundled JS, extract `npm-package.tgz` and use Foundation's `(data as NSData).compressed(using: .lzfse)` on `package/dist/scriptlets/index.js`; check the decompressed bytes against `runtime.json`. Iris's loader removes only the final `export { scriptlets };` declaration in memory and wraps the catalog for host-gated WKUserScript injection. Runtime upgrades require an explicit code/bundle change; filter downloads never update this library.

This approval covers a personal headset pilot. A closed-source App Store release needs a licensing decision for both Scriptlets and the existing GPL SafariConverterLib; AdGuard describes commercial dual licensing at https://adguard.com/en/eula.html. No commercial license has been obtained, and this repository's own license has not been changed.
