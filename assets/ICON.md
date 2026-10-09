# Undertone icon

The icon is the Prism Fan: five glass color chips fanned on a metal pin, over a violet-indigo background. Its source is the Icon Composer document `Icon/Undertone.icon`, and `scripts/build-app.sh` compiles it with `actool` into `Assets.car` (the Liquid Glass icon) plus `Undertone.icns` (the fallback on older systems).

`scripts/build-prism-fan-icon.py` generates the whole document, its SVG layers and `icon.json`, so change the script rather than the document. Close the document in Icon Composer before running it; the script replaces the bundle.

```sh
python3 scripts/build-prism-fan-icon.py
python3 scripts/build-prism-fan-icon.py Icon/Undertone.icon '{"scale": 1.06}'
```

The JSON argument overrides the script's settings: `groups`, `translucency` (0.6), `blur` (0.1), `refract` (strength and depth, 0.5 and 0), `scale` (1.10, about the canvas centre), `shift` (vertical offset on the 1024 canvas, 6), `bg` (the two background gradient colors) and the baked effect strengths. Adding `"caustic"` to the groups (for example `[["pin", "caustic"], [5], [4], [3, 2, 1]]`) brings back the spectral pool under the fan.

Icon Composer allows four visible groups. The groups are Pin, Chip 5, Chip 4 and Chips 3, 2, 1. Chips that share a group are flattened before the glass is applied, so the script bakes what the glass would have given each one: a tinted shadow on the chips behind it, and an edge highlight. The highlight is hidden in the dark appearance, because white layers make Icon Composer render the whole group as pale glass there. The pin can't share a group with chips: a translucent group turns it into ghostly glass, even with the layer's glass switched off.

Translucency above about 0.6 lets the background wash the chips out at Dock size, and the fan should stay near 1.10 scale to match the visual weight of neighboring icons.

On macOS, the dark appearance always uses the system's dark background; a custom dark fill is ignored.

Preview a build without opening Icon Composer:

```sh
"$(xcode-select -p)/Applications/Icon Composer.app/Contents/Executables/ictool" Icon/Undertone.icon \
    --export-image --output-file preview.png --platform macOS --rendition Default \
    --width 512 --height 512 --scale 2 --design-generation 26
```

Renditions include `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight` and `TintedDark`.
