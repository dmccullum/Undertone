# First-build verification

## Metal renderer

- The canvas is an `MTKView` (`MetalCanvas`) running the renderer's kernel straight into its sRGB drawable at full Retina resolution; it redraws only when the recipe or size changes. Export, Copy, drag-out, style tiles, sidebar thumbnails and the backdrop go through `RenderEngine`.
- `RenderEngine` runs a self-test on first use (warmed up off the main thread at launch): eight fixtures rendered on both renderers must match within 2/255, or that Mac stays on the CPU. This Mac's worst difference is 1/255.

### Original gate results

- One compute kernel (`MetalShaders`, compiled at runtime) renders every style from the same `GradientRenderer.Scene` the CPU uses. `renderBytes` produces 8-bit sRGB export pixels; `renderTexture` writes the preview into a drawable. The CPU renderer stays the reference and fallback.
- Parity gate (`MetalParityTests`): 20 recipes covering every style, grain sizes, swirl, bent 4×4 meshes, no colors and one color. Every channel of every pixel matches within 1/255 (the gate allows 2/255) at 257×343, 640×480, 2160×2880 and 3840×2160; at most 0.0036% of channels differ at all. Run the full sizes with `UNDERTONE_PARITY_FULL=1 swift test -c release --filter MetalParityTests`.
- Grain now uses a 32-bit hash (lowbias32) sampled on integer cell coordinates so both renderers compute identical noise. Existing gradients keep their grain amount and size, but the grain pattern shifted.
- Banding: a Coldwell Banker Blue → Midnight ramp with grain off held each 8-bit level for 40–90 px (535 px in a Glow). A triangular ±1/255 dither per channel, independent of the seed, brings the longest flat run under 10 px with no visible noise.
- Timing on Apple silicon: a full-Retina 1840×2454 preview takes 2.5 ms (Organic), 3.6 ms (Mesh) and under 1 ms for the other styles, scene setup included. The current CPU preview needs 21 ms for Organic at 960×1280.

## Redesign: gradient library, naming and interface (unverified build)

Written in a cloud container with no Swift toolchain, so this pass has been syntax-checked only. It has not been compiled, tested or run. Before relying on it, run `swift build` and `swift test` on a Mac, then check the app by hand:

- Gradients tab: new, duplicate, rename, delete and undo delete; relaunch restores the last gradient with every setting and canvas size intact.
- Automatic names change with the colors and stop changing after a rename; the dice popover offers five ideas.
- On macOS 26 with Apple Intelligence on, the button shows sparkles and the ideas come from the on-device model. Building with Xcode 16 or earlier skips that code through `canImport(FoundationModels)`.
- Canvas handles for Organic, Glow, Linear and Aurora; snapping and haptics on a Force Touch trackpad.
- Color tray: edit popover, drag to reorder, add related tones, remove all.
- Drag the canvas to Finder and Canva; ⌘C with the canvas focused; Copy Image and Export Image default names.
- Undo and redo across slider drags, style changes and randomize.
- Light and dark appearance of the blurred backdrop and inspector.
- Migration: an existing `palettes.json` becomes gradients and is renamed `palettes-migrated.json`.


## Gradient modes

- Added Organic, Linear, Magic Linear, Magic Single, Radial Glow, and Aurora as native inspector choices.
- Linear exposes angle, position, fade width, and easing. Radial exposes center, spread, and easing. Aurora exposes direction, position, flow, fade width, easing, and color arc.
- Magic Linear uses local OKLab interpolation with a controlled curved path between colors. Magic Single derives four tonal variants from one selected base color; clicking a color-library swatch replaces that base immediately.
- Randomize changes the parameters that matter to the selected mode. Existing saved recipes without the new fields decode as Organic with stable defaults.
- Release tests cover distinct output for every mode, linear angle, radial center, Magic Single variation, old-recipe compatibility, deterministic output, dimensions, and export encoding.

## User color libraries

- Renamed Brand colors to Color libraries. Coldwell Banker remains a protected built-in library and can be the saved default for this user.
- Added locally persisted custom libraries, a native New Library sheet, JSON import/export through native panels, legacy `colors.json` migration, and a per-user last-selected-library preference.
- Adding a swatch while viewing the built-in library routes it to a personal My Colors library, keeping the supplied Coldwell Banker values intact.
- Library import makes an independent local copy with a new identifier. Tests cover create/save/reload, export/import, legacy coexistence with gradient presets, and instant swatch toggling.
- Visual QA confirmed the renamed section and picker. The actions control was changed from a subtle icon to a labeled Manage… menu for discoverability.

## Palette and window polish

- Simplified brand colors to direct manipulation: one click adds a named swatch to the active gradient and its checkmark removes it. The intermediate selection list, Clear action, and Use Selected Colors confirmation were removed.
- Verified the live interaction: clicking Coldwell Banker Blue immediately added a fifth color stop and updated the preview/status.
- Fixed inspector collisions by allowing the native color well to keep its intrinsic width, hiding the visible text-field label while preserving its accessibility label, and adding spacing.
- Unified the native toolbar, made its title bar transparent, and removed the title-bar separator. Visual QA confirms the dark workspace now continues behind the title instead of producing the previous colored rectangle in the top-left transition.
- Gradient presets and the save-current-gradient field now share one section. Copy/Save-only handoff and the Instagram Portrait 2160 × 2880 preset remain in place.

## Color library and icon update

- Included the 12 named Coldwell Banker swatches supplied by the user, selectable in a native sidebar grid with checkmarks. Selections of 2–8 colors replace gradient stops without changing surface/export settings. Selections can span the preset and personal libraries.
- Personal named swatches persist separately in `colors.json`, preserving existing saved gradient palettes.
- Release tests: 10 passed, optional large-render benchmark skipped (previously passed); new tests verify personal-color persistence, preservation of existing palettes, subset application and invalid selection rejection.
- Generated a vibrant gradient ribbon app icon; packaged PNG representations in a native ICNS container. Apple's iconutil rejected the iconset in this environment, so the build includes a lossless ICNS container fallback.
- New UI and Dock icon await visual verification after relaunch. The running composition has not been interrupted.

- Release compilation and local `.app` packaging passed on Apple Silicon with Swift 6.2.3.
- Nine tests passed: deterministic rendering, seed behavior, invalid dimensions/allocation rejection, minimum color count, sRGB output/dimensions, 4K/8K rendering, PNG/JPEG encode/decode dimensions, and recipe round trip.
- Renderer-only benchmark on this Mac: approximately 0.010 seconds at 3840×2160 and 0.036 seconds at 7680×4320. These timings exclude image encoding, clipboard transfer and destination-app import.
- App is ad-hoc signed for local development; not Developer ID signed or notarized.
- Following explicit user approval, the app launched and its native interface was inspected. An oversized AppKit drag thumbnail was found; explicit sizing, lower compression resistance and clipping were added. The updated release app builds successfully. Its visual recheck awaits restart; the running composition was left open to preserve user edits.
- Copy Image reported success and an immediate New from Clipboard action in Preview created an Untitled image document. Prepare Drag reported a prepared PNG and enabled the drag source.
- Direct Canva paste/drop, completed Finder drag, palette persistence through restart and save completion remain manual acceptance checks. The native recipe save panel opened successfully.
- Grain is currently deterministic monochrome procedural noise. It has not been visually matched to Granular. Grain size is measured in rendered pixels, so the reduced preview does not reproduce exported grain density at the same viewing size.
