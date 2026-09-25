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

The window has three parts: the library sidebar on the left, the canvas in the middle and the inspector on the right. Hide the inspector with the toolbar button when you want only the artwork.

**Gradients.** Every composition lives in the Gradients library and saves itself as you work. A gradient keeps everything: colors, point positions, direction, center, every slider, the seed and the canvas size. New Gradient (⌘N) starts a fresh layout from the current colors, Duplicate (⌘D) makes a variation and Delete can be undone. ⌘S confirms a save but is never required.

**Colors.** The Colors tab holds collections of named colors. A collection can be a full brand library such as Coldwell Banker or a small palette. Click a swatch to add it to the gradient and click again to remove it. The actions menu creates, imports, exports and deletes collections, and New Collection from Gradient Colors turns the current colors into a reusable palette. Built-in collections stay unchanged; colors added while viewing one go to My Colors.

**Names.** New gradients get a name from their colors, and the name follows the colors until you rename it. The dice button offers five more ideas. On a Mac with Apple Intelligence turned on (macOS 26 or later), the button shows sparkles and the ideas come from Apple's on-device model; otherwise a deterministic word picker supplies them. Exports use the name and size, such as `Harbor Hush 2160x2880.png`.

**Canvas.** Hover over the artwork to reveal its handles: color points for Organic, the center for Glow, and a position dot plus an angle knob for Linear and Aurora. Handles snap to the center and to 45-degree angles with a light trackpad tap. The color tray under the canvas shows the gradient's colors; click one to edit it, drag to reorder and use + for related tones or a custom color. Drag the artwork straight into Finder, Canva or another app to export it, or press ⌘C while it has focus.

**Styles.** The inspector shows each style as a live thumbnail of your colors:

- **Organic** blends movable color fields into a soft flowing surface.
- **Linear** fades along an angle, blending in OKLab. Color Arc bends each transition through a nearby contrasting tone; set it to 0 for a straight blend. (Magic Linear files open here.)
- **Tonal** turns one color into a flowing family of lighter, deeper and gently hue-shifted tones. (Formerly Magic Single.)
- **Glow** radiates from a draggable center that can sit off the canvas.
- **Aurora** makes sweeping, seed-driven color ribbons.

Randomize (⌘R) changes the geometry that matters for the current style. Every edit can be undone (⌘Z); a slider drag undoes in one step. Copy Image (⇧⌘C) and Export Image (⌘E) render at full size. Export Recipe and Import Recipe move portable `.undertone.json` files between Macs.

Gradients, collections and colors are stored under `~/Library/Application Support/Undertone/`. Older gradient presets, which saved only colors, move into the Gradients library on first launch.

See [PLAN.md](PLAN.md) for the design and remaining acceptance checks.
