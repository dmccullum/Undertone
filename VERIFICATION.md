# First-build verification

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
- Grain is deterministic monochrome procedural noise. Preview and export now sample the same canvas-relative grain pattern, so exported texture retains its apparent size when viewed at preview scale. It has not been visually matched to Granular.
