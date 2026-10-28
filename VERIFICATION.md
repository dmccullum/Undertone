# Verification

Last run: 2026-10-28, macOS 26.7.1 on Apple silicon, Swift 6.4, macOS 27 SDK.

## Automated

`swift test` runs 68 tests: 64 pass and 4 skip, with 0 failures. The skipped tests are opt-in:

| Environment variable | Test it enables |
| --- | --- |
| `UNDERTONE_PARITY_FULL=1` | Metal and CPU parity at 2160×2880 and 3840×2160 |
| `UNDERTONE_RENDERER_BENCHMARK=1` | CPU and Metal timing benchmarks at 4K and 8K |

The suites cover:

- **Renderer.** Deterministic output for a given seed, a distinct image for every style, sRGB output at the requested dimensions, rejection of invalid sizes, and handling of zero and one color.
- **Metal parity.** 20 recipes covering every style, grain sizes, swirl, bent 4×4 meshes, no colors and one color, rendered on the GPU and the CPU reference. A channel may differ by at most 2/255. At the sizes run by default (257×343 and 640×480) the largest difference is 1/255.
- **Launch self-test.** `RenderEngine` repeats the parity check on eight fixtures when it first renders. A Mac that exceeds 2/255 renders on the CPU.
- **Export.** PNG and JPEG encode at the requested dimensions, and a recipe round-trips with every setting intact. Recipes saved before the style field existed open as Organic, and Magic Linear files open as Linear.
- **Library.** Gradient and collection persistence, automatic names that follow the colors until renamed, collection import and export as independent copies, and migration of older palette files.
- **Naming.** The deterministic word picker.
- **Migration.** Copying settings from the old `studio.undertone.mac` preferences once, without system keys.

Grain uses a 32-bit hash sampled on integer cell coordinates, so both renderers compute identical noise. Output is dithered by ±1/255 per channel, independent of the seed, to avoid banding in smooth ramps.

## Manual checks

These need a person at the app and are not covered by tests:

- Gradients tab: new, duplicate, rename, delete and undo delete. Relaunch restores the last gradient with every setting and canvas size.
- Automatic names change with the colors and stop changing after a rename. The rename sheet's dice button fills in a name from the colors, and renaming to it keeps the name automatic.
- Canvas handles for Organic, Mesh, Glow, Linear and Aurora. Snapping and haptics on a Force Touch trackpad.
- Color tray: edit popover, drag to reorder, add related tones, remove all.
- Drag the canvas to Finder and into Canva. ⌘C with the canvas focused. Default names for Copy Image and Export Image.
- Undo and redo across slider drags, style changes and Randomize.
- Light and dark appearance of the blurred backdrop and inspector.
- Migration: an existing `palettes.json` becomes gradients and is renamed `palettes-migrated.json`.
- Settings (⌘,): the export format sets the Format pop-up in Export Image's save panel; switching the pop-up changes the file's extension; JPEG Quality changes JPEG file size.
- File panels (Export Image, Export and Import Recipe, Export and Import Collection) open as sheets on the window.
- Menus: View › Show Inspector is ⌥⌘I; Gradient › Canvas Size, Texture, Shuffle Flow, Reset Style, Reset Texture and Remove All Colors; the Colors menu opens its sheets from either sidebar tab.
- Right-click menus on the canvas, a collection header, a swatch, a tray chip and an unsaved gradient row.
- Bundle identifier migration: launch a build with the old `studio.undertone.mac` identifier, change the open gradient, sidebar tab, inspector and export settings, quit, then launch this build. Those settings and the library carry over, and `defaults read com.danielmccullum.Undertone migratedFromBundleID` prints the old identifier.
- The rose accent (light #C24D7D, dark #E66C9D) on selected tiles, swatches and the Settings controls, with Appearance › Accent color set to Multicolor.
- Reduce Motion, Reduce Transparency and Increase Contrast (System Settings › Accessibility › Display), and a yellow accent color for the swatch badge and the selected angle button.

## Distribution

`scripts/build-app.sh` produces an ad-hoc signed app. It is not Developer ID signed or notarized.
