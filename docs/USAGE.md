# Undertone user guide

Reference for the library, canvas, styles and file formats. For install and build instructions, see the [README](../README.md).

## Run

```sh
swift run -c release
```

Use the release configuration. A plain `swift run` builds for debugging, and the CPU renderer runs many times slower that way.

Rendering runs on the GPU (Metal) when this Mac's GPU passes a self-test at launch: it renders a set of fixtures on the GPU and on the CPU reference and requires every pixel to match within 2/255. A Mac that doesn't pass keeps rendering on the CPU, so every Mac produces the same image within 2/255. All output is 8-bit sRGB.

To package a local app:

```sh
zsh scripts/build-app.sh
open build/Undertone.app
```

Or double-click `Build Undertone.command` in Finder. It builds the app, quits a running copy so the new build and its icon replace it, and opens `build/Undertone.app`.

Open `Package.swift` in Xcode to develop with Apple's tooling. `swift test` runs renderer checks. The packaged app is ad-hoc signed for local use, not notarized for distribution.

## Workflow

The window has three parts: the library sidebar on the left, the canvas in the middle and the inspector on the right. Randomize, Copy and Export sit at the top of the inspector. Hide the sidebar with ⌃⌘S.

Closing the window keeps Undertone running. Reopen it from the Dock or with ⌘0. Quit the app with ⌘Q.

**Gradients.** The Gradients library has two sections, Unsaved and Saved. A gradient keeps everything: colors, point positions, direction, center, every slider, the seed and the canvas size. The first edit to a saved gradient opens an unsaved copy at the top of the library, and the saved gradient stays as it was. Unsaved gradients autosave and survive quitting. Then:

- **Save as New Gradient (⌘S)** adds the copy to Saved, numbered if the name is taken (Dusk 2).
- **Update “Dusk” (⌥⌘S)** writes the copy over the gradient it came from.
- **Revert to Saved** drops the copy and reopens the original.
- Or leave it unsaved. An unsaved copy you edit back to match its original is removed when you open another gradient.

The same commands are in the File menu, the toolbar’s Save button and the row’s right-click menu, and all of them can be undone. The right-click menu also has Rename, Duplicate, Export Recipe and Delete (Discard for an unsaved gradient). New Gradient (⌘N) starts an empty unsaved gradient.

**Colors.** The Colors tab holds collapsible collections of named colors. A collection can be a full brand library such as Coldwell Banker or a small palette. Every click on a swatch adds that color to the gradient, so a color can appear more than once; a badge shows how many times. Right-click a swatch to edit, rename or delete it. Each collection's menu adds colors, renames, exports and deletes it. New Collection at the bottom also imports a collection or turns the gradient's colors into one. Built-in collections are locked.

**Names.** New gradients get a name from their colors, and the name follows the colors until you rename it. The dice button next to the name offers five ideas; More Ideas asks again. On a Mac with Apple Intelligence turned on (macOS 26 or later), the button shows sparkles and the ideas come from Apple's on-device model; otherwise a deterministic word picker supplies them. Exports use the name and size, such as `Harbor Hush 2160x2880.png`.

**Canvas.** Hover over the artwork to reveal its handles: color points for Organic, the bendable grid for Mesh, the center for Glow, and a position dot plus an angle knob for Linear and Aurora. Handles snap to the center and to 45-degree angles with a light trackpad tap. The color tray under the canvas shows the gradient's colors. Click one to edit it, drag it along the tray to reorder (the others slide aside, as in the Dock) or pull it away from the tray to remove it. Right-click to duplicate. Use + for related tones or a custom color. Drag the artwork straight into Finder, Canva or another app to export it, or press ⌘C while it has focus.

**Styles.** The inspector shows each style as a live thumbnail of your colors:

- **Organic** melts soft color fields into each other, blended in OKLab with saturation kept so mixes stay vivid. Choose how the colors move: **Still** melts them in place, shaped only by the points; **Pull** drags each color in a shared brush direction into long smears; **Wave** ripples the borders in long, soft waves. **Classic** is the original Organic: the same shapes and broad flowing warp, mixed in OKLab so it no longer goes muddy. The slider sets how far colors are pulled or how high the waves run, Softness runs from defined shapes to a smooth haze, Swirl adds a vortex, and Shuffle Flow picks new directions.
- **Mesh** is a true gradient mesh: a 3 × 3 or 4 × 4 grid of points, each with its own color, joined by a smooth surface in OKLab. The tray turns into a small grid that mirrors the points. Click a point (on the canvas or in the tray), then click colors in your collections to paint it; the selection steps to the next point, so a few clicks fill the grid. Double-click a point for its color popover. Drag points to bend the grid into curved, directional seams. Shuffle Colors rearranges the colors, and Softness runs from crisp seams through a classic mesh to a hazy wash. The first time a gradient becomes a mesh, its colors seed the points; older Mesh files open as the nearest grid.
- **Linear** fades along an angle, blending in OKLab. Color Arc bends each transition through a nearby contrasting tone; set it to 0 for a straight blend. (Magic Linear files open here.)
- **Tonal** turns one color into a flowing family of lighter, deeper and gently hue-shifted tones. (Formerly Magic Single.)
- **Glow** radiates from a draggable center that can sit off the canvas.
- **Aurora** makes sweeping, seed-driven color ribbons.

Randomize (⌘R) changes the geometry that matters for the current style. Every edit can be undone (⌘Z), including changes to colors, collections and gradient names; a slider drag undoes in one step. Opening another gradient clears its canvas edits from the undo history but keeps library changes. Copy Image (⇧⌘C) and Export Image (⌘E) render at full size. Export Recipe and Import Recipe move portable `.undertone.json` files between Macs.

Gradients, collections and colors are stored under `~/Library/Application Support/Undertone/`. Older gradient presets, which saved only colors, move into the Gradients library on first launch.

See [PLAN.md](../PLAN.md) for the design and remaining acceptance checks.
