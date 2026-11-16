# Rytivo: Essential Runner

Approved November 16, 2026: [Figma identity](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=527-17415).

The current identity is the clean, two-shape running R with the lowercase
**rytivo** wordmark in the already-bundled Nunito Sans SemiBold. The wordmark
uses -1% tracking and the approved 112-point mark / 8-point gap / 66-point type
ratio. Brand geometry stays left-to-right in translated interfaces; the
accessible name remains “Rytivo.” Ordinary product-name copy is unchanged.

## Active assets

- `Assets.xcassets/RytivoLogoMark.imageset`: exact full-node SVG exports,
  256 × 256, ink `#292421` for light appearance and white for dark.
- `Assets.xcassets/RytivoBrandInk.colorset`: matching adaptive wordmark color.
- `Assets.xcassets/AppIcon.appiconset/Rytivo-AppIcon-1024.png`: white mark on
  `#F86722`, with the approved 94% mark canvas and 3% inset. The production
  export is square, 1024 × 1024 and fully opaque; iOS supplies the corner mask.
- `rytivo-essential-runner-icon-preview.png`: rounded presentation preview,
  not the production app-icon source.

Asset-catalog paths above are relative to `IOS Frontend/IOS Frontend`.
`approved-brand-assets.json` records source nodes and normalized export hashes.
The only transformation of the production PNG removes an entirely opaque
alpha channel; its RGB pixels are unchanged. SVG geometry is not redrawn.
Older `rytivo-momentum-loop-*` files are retained historical references, not
active app assets.

## Scope and verification

The shared lockup covers Training, Food, workflow headers, Authentication and
Calendar. Mark-only loading/settings placements inherit the new local asset.
No backend, API, account state, main merge or TestFlight upload is involved.

Run `python3 Scripts/check-brand-assets.py` and
`bash Scripts/test-account-safety.sh`. The new Swift tests check source wiring;
neither they nor asset checks prove native rendering. Mac CI builds the app and
captures the relevant real SwiftUI screens in a dedicated simulator, including
light/dark, larger text and Arabic. Preview screenshots use disconnected
fixtures for signed-in pages; they do not establish live-backend behavior.

For a real-app simulator build, use the existing build path:

```bash
INSTALL_SIMULATOR=1 bash Scripts/validate-home-refresh.sh
```

It retains the installed app's configured API origin when available. A new
simulator requires an explicitly configured HTTPS testing origin; no backend
is deployed by this command. Before promotion, check the installed home-screen
icon, welcome/sign-in, Training, Food, Calendar and Settings in light/dark,
narrow widths, larger text, Arabic and VoiceOver. Keep the change on the shared
testing branch until explicitly approved for release.
