# Undertone

A native Mac studio for expressive gradients and film grain. Built with SwiftUI and AppKit, with no external package dependencies. Requires macOS 14+ and Xcode command-line tools to build.

## Run

```sh
swift run
```

To package a local app:

```sh
zsh scripts/build-app.sh
open build/Undertone.app
```

Open `Package.swift` in Xcode to develop with Apple's tooling. `swift test` runs renderer checks. The packaged app is ad-hoc signed for local use, not notarized for distribution.

## Workflow

In Color libraries, choose Coldwell Banker or any library you create or import. Clicking a swatch immediately adds it to the current gradient; clicking its checkmark removes it. The actions menu creates libraries and imports or exports portable `.undertone-colors.json` files. The last selected library is saved per macOS user. Built-in libraries remain unchanged; adding a color while viewing one creates or uses a personal My Colors library. Gradient presets remain reusable complete combinations. The twelve Coldwell Banker colors are included exactly as supplied.

Choose a palette and one of six gradient types:

- **Organic** blends movable color fields into a soft flowing surface.
- **Linear** adds angle, position, fade-width, and easing controls.
- **Magic Linear** blends in OKLab and bends the transition through restrained contrasting bridge tones with the Color Arc control.
- **Magic Single** turns one selected library color into a flowing family of lighter, deeper, and gently hue-shifted tones.
- **Radial Glow** adds a movable center, spread, and easing.
- **Aurora** makes sweeping, seed-driven color ribbons with adjustable direction and flow.

Randomize changes the geometry appropriate to the selected type. Save your own named palette or a portable JSON composition. Related-tone suggestions derive from the first color; they are starting points for judgment, not automated brand approval. Magic modes are deterministic local color math and do not call an AI service.

Copy Image places a full-resolution PNG/TIFF image on the clipboard. Save Image opens the native save panel; use `.png`, `.jpg`, or `.jpeg` for the format. The canvas presets include Instagram Portrait at 2160 × 2880 pixels. Color points can still be moved within the editor.

Palettes and named colors are stored under `~/Library/Application Support/Undertone/`.

See [PLAN.md](PLAN.md) for the design, implementation phases and remaining acceptance checks. Direct Canva interoperability requires a test in the actual destination app/browser. Undo/redo and full document autosave are planned follow-on work.
