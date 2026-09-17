# Undertone — Liquid Glass ribbon

## Start here

Open **Undertone.icon** in Apple Icon Composer. It already contains the two vector faces, their color gradients, the blue/violet background, and a shared Liquid Glass group. This project was successfully rendered with Apple's installed `ictool` in all six appearances.

## Files

- `Undertone.icon` — native, editable Icon Composer document.
- `layers/01-rear-cyan.svg` — cyan face, on a transparent 1024 × 1024 canvas.
- `layers/02-front-coral.svg` — coral face, with the same canvas and registration.
- `source/Undertone-master.svg` — both editable face paths in named groups; transparent background.
- `source/Undertone-color-layout.svg` — full-square vector color reference, including background; no glass effects.
- `source/Undertone-silhouette.svg` — one continuous white silhouette for alternate uses.
- `previews/` — actual Apple-rendered appearances, a contact sheet, and a compact preview.
- `source/build_assets.py` and `source/geometry.json` — reproducible geometry and measurement record.

## Shape

This is a geometric reinterpretation, not a tracing of the supplied artwork. A U centerline has straight parallel stems and a circular bend. A strip of **184 units of physical width** rotates **180°** through the lower bend. Its projected width changes as the surface turns toward the edge. The rounded terminal corners have a 40-unit radius.

The two colored paths describe visible faces of that one strip. Their overlap is intentional: the coral face sits in front of cyan near the lower center. Keep them registered. The model is an open half-twisted ribbon, not a closed Möbius ring. The projection is an oblique design view, rather than a physically simulated material.

## Import into your own Composer document

1. Import the **two files in `layers/` together**, at their original size and position.
2. Keep both in one group. Put **02 front coral above 01 rear cyan** in the sidebar.
3. Keep Liquid Glass enabled. Set the layer fills to the gradients below.
4. Set the canvas background in Composer. Do not import the preview images as layers.
5. Check Default, Dark, Clear, and Tinted, including small sizes. Save as `.icon`.

All import SVGs are opaque filled paths with transparent surroundings. They contain no raster images, filters, shadows, highlights, strokes, or icon corner masks. Apple adds the outer icon shape and the dynamic material.

## Color and material recipe

| Element | Start | End | Direction |
|---|---|---|---|
| Background | `#111B92` | `#5413C8` | Upper left → lower right |
| Cyan face | `#8AF2FF` | `#3979EC` | Top → bottom |
| Coral face | `#FFE5A3` | `#FF4E9A` | Top → bottom |

The supplied native project uses 100% layer opacity, group translucency 22%, blur material 12%, and a neutral shadow at 30%. These are starting art-direction values, not baked artwork. The SVGs have simpler solid fallback fills; the richer gradients live in the native project.

The Dark, Clear, and Tinted previews use Composer's automatic appearance adaptations. Clear and Tinted rendering varies with wallpaper and user tint. The exported PNGs are inspection/marketing references; use the `.icon` for the adaptive asset.

## Edit or rebuild

Edit the SVG paths in a vector editor for manual changes. The generator requires Python, NumPy, and Shapely; running it regenerates the primary vectors and native project, replacing manual changes to those outputs. The optional color layout and preview exports are separate snapshots.

The source measurement check confirms constant cross-section width to floating-point precision, a connected silhouette, and overlapping valid face shapes. The vector boundaries are fitted with cubic Béziers to a 0.2-unit target tolerance on the 1024-unit canvas.

## Apple references

- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Create icons with Icon Composer — WWDC25](https://developer.apple.com/videos/play/wwdc2025/361/)

The layer packaging follows Apple's guidance to use full-canvas SVG layers, keep source graphics simple, and add background and material effects in Composer.
