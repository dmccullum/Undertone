# Undertone icon

The icon is a grained magenta-to-violet gradient panel on the system's own light and dark icon backgrounds (`icon.json` fills the tile with `system-light` and `system-dark`), with three clear glass discs lying on it. Its source is the Icon Composer document `Icon/Undertone.icon`, and `scripts/build-app.sh` compiles it with `actool` into `Assets.car` (the Liquid Glass icon) plus `Undertone.icns`.

`Icon/Undertone.icon` is maintained directly as an Icon Composer document. No script in this repository generates it, so edit it in Icon Composer and commit the bundle.

## Layers

The document has four groups, the most `actool` accepts (it fails the build with "Too many visible groups" above four). On the 1024 canvas, from back to front:

- **Well**: the gradient panel, 154 to 870 on both axes with a corner radius of 100, sitting flush in the tile with a 1.5 px hairline edge. It is an Organic gradient rendered by Undertone with grain 0.9 at size 5, baked into `panel.png`, `panel-dark.png` and `panel-tinted.png` (a plain grey ramp for the Tinted and Clear renditions). Above it in the same group, `shadows.svg` draws a soft drop shadow under each disc (`#14051C`, up to 46% opacity, 22 px down). The group has no shadow, specular or translucency of its own.
- **Disc 1 to Disc 3**: three discs of radius 110, centred at (384, 234), (790, 512) and (512, 790). Each one overlaps a different edge of the panel (top, right and bottom) by 30 px. Each disc is its own group with a neutral shadow at 0.45 and specular on, and is built from:
  - `discN-view.png` (with `-dark` and `-tinted` versions): a baked refraction of the panel and tile beneath the disc. The centre is magnified 1.12×; toward the rim the image is pulled in from up to 1.7 radii away and compressed, so the panel's edge curves round inside the rim; red, green and blue are offset by 3.5% for a slight colour fringe.
  - `discN-tile.svg`: a patch of the tile colour behind the refraction, so the tile shows where the refracted edge moves inward.
  - `discN.svg`: the glass shell, white from 14% at the top to 4% at the bottom.
  - `discN-sheen.svg` and `discN-sheen-dark.svg`: a bevel sheen toward the rim; the dark one is fainter so the dark tile inside the overhang doesn't turn grey.
  - `discN-edge.svg`, `discN-cyan.svg` and `discN-pink.svg`: a bright 2 px edge with a cyan ring outside it and a faint pink ring inside.

## Editing

The disc views are pictures of the panel and tile beneath each disc. If the panel, the tile colours or a disc's position changes, the matching `discN-view` images must be rebuilt, or the refraction will no longer line up with what is behind it.

`scripts/build-prism-fan-icon.py` generated the previous icon, the Prism Fan (three glass color chips fanned on a pin). It is kept as a record and no longer writes to `Icon/Undertone.icon`; give it another `.icon` path to generate that design.

Preview a build without opening Icon Composer:

```sh
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Icon/Undertone.icon \
    --export-image --output-file preview.png --platform macOS --rendition Default \
    --width 512 --height 512 --scale 2 --design-generation 26
```

Renditions include `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight` and `TintedDark`. `assets/icon.png` is the `Default` rendition at 256 points and scale 2; `assets/undertone-icon.png` is the same at scale 1.
