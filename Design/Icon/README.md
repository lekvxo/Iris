# Frosted glacier Iris icon

Max selected Option B on October 2, 2026. `Frosted-Concept.png` preserves that original concept. The built-in image generation tool extracted `Frosted-Aperture.png` with transparency and prepared the opaque `Frosted-Background.png`; no external icon library is used.

`swift Scripts/generate-icon.swift` prepares the app's two 1024 × 1024 layers in `Iris/Assets.xcassets/AppIcon.solidimagestack`. The aperture sits inside a 72-pixel canvas inset, leaving room for visionOS's circular crop and foreground motion. The background fills the canvas without alpha. `Preview.png` shows the layers together with the circular mask; actual gaze/parallax appearance must be checked on the headset.

Prompts used with the built-in tool:

- Selected concept: “App icon for a visionOS web browser called Iris. Spatial glass motif: a translucent, frosted-glass circular aperture with layered depth, subtle refraction and soft light bending through it. Concentric rings suggesting a camera iris or lens diaphragm, but abstract, not an eye. Frosted glacier blue palette: pale icy blues, crisp white highlights, hints of cyan, like light through glacier ice. Clean light or soft white background, cool ambient shadows, premium Apple design language, rounded square icon, centered, high detail.” No text, branding or watermark.
- Foreground adaptation: Extract the existing circular aperture and glass rim, preserving the selected blade arrangement, icy blue/cyan palette, frosted grain, refraction, highlights and frontal view. Remove the white backdrop and rounded-square tile; use a genuinely transparent background and central opening. Keep the full rim within the square canvas.
- Background adaptation: Remove the aperture, rings, blades and square boundary. Preserve the pale icy blue, soft-white frosted lighting and cyan hints as a quiet, fully opaque, full-bleed background. No objects, text or dark blue/violet.

Apple's layered icon guidance: https://developer.apple.com/design/human-interface-guidelines/app-icons
