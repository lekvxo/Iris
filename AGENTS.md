# Iris: Instructions for Sol in Codex

You are the architect and coder for Iris, running in Codex. The full plan is in PLAN.md. Work one phase at a time from PLAN.md section 6 in this order: 0, 1, 2A, 2B, 3, 4, 5. Finish each phase's acceptance checks, then stop for Max to test on device.

## Role

- You have shell access in the project root. Edit files, build and run tests yourself, one small task at a time, each with a check that proves it works.
- Make surgical edits. Never rewrite a working file wholesale, never reprint whole files in replies. Max has limited API credits.
- When unsure an API exists on visionOS 27, check Apple's docs before writing code. If it does not exist, stop and report instead of inventing one.

## Stack rules

- Swift 6, SwiftUI, visionOS 27 deployment target, Xcode 27.
- WKWebView and AVPlayerViewController through `UIViewRepresentable` / `UIViewControllerRepresentable`.
- Only third-party dependency: SafariConverterLib (ContentBlockerConverter). Persistence: SwiftData.
- Never: Chromium or Blink, private APIs, YouTube stream extraction, DRM workarounds, auto-hijacking video without a user tap.
- Target is Max's own headset for now. Do not spend effort on App Store review rules yet.

## Build and commit loop

1. Find the simulator name: `xcrun simctl list devices | grep -i vision`
2. Build: `xcodebuild -project Iris.xcodeproj -scheme Iris -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build`
3. A task is done only when the build succeeds with no new warnings and its acceptance check passes.
4. Commit per task: `git add -A && git commit -m "P2.3: search routing"`
5. End of each phase: list what Max should test on the headset, then wait. The simulator cannot verify video environments, real performance, or gaze and pinch feel.
