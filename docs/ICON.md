# Undertone icon

The icon is the Prism Fan: three glass color chips (red, green and blue) fanned on a metal pin, on the system's own light and dark icon backgrounds (`icon.json` sets no fill). Each chip is filled with a three-stop gradient that runs corner to corner (amber to raspberry, lime to teal, cyan to violet) and has 50% glass translucency. The whole fan is tilted 16° clockwise. Its source is the Icon Composer document `Icon/Undertone.icon`, and `scripts/build-app.sh` compiles it with `actool` into `Assets.car` (the Liquid Glass icon) plus `Undertone.icns`.

`scripts/build-prism-fan-icon.py` generates the whole document, its SVG layers and `icon.json`. It replaces the bundle wholesale, so close the document in Icon Composer before running it, and make any change in the script rather than by hand.

```sh
python3 scripts/build-prism-fan-icon.py
python3 scripts/build-prism-fan-icon.py Icon/Undertone.icon '{"tilt": 10}'
```

The JSON argument overrides the script's settings:

- `angle` and `grad`: each chip's fan angle (−32°, 0°, 32°) and gradient stops, keyed by chip number from back to front
- `groups`: which chips share an Icon Composer group (`[["pin"], [3], [2], [1]]`)
- `translucency` (0.5), `blur` (0.1), `refract` (strength and depth, 0.5 and 0), `shadow` (0.4)
- `scale` (1.10, about the canvas centre) and `tilt` (16, degrees clockwise about the canvas centre)
- `center` (true): moves the chips' bounding box to the canvas centre
- `nudge` (18) and `shift` (6): horizontal and vertical offsets on the 1024 canvas, applied after centering. The tilted fan carries more weight at its upper left than its bounding box shows, so `nudge` moves it right to look centred.
- `bg`: two background gradient colors, or `null` for the system backgrounds

Adding `"caustic"` to the pin's group (`[["pin", "caustic"], [3], [2], [1]]`) brings back the spectral pool under the fan.

Icon Composer allows four visible groups: the pin and one per chip. Each chip in its own group gets the system's glass, highlight and layer-color shadow. Adding a fourth chip means two chips share a group, and shared chips are flattened before the glass is applied. For that case the script bakes what the glass would have given each one (`bake`): a tinted shadow on the chips behind it, and an edge highlight that is hidden in the dark appearance, because white layers make Icon Composer render the whole group as pale glass there. The pin can't share a group with chips: a translucent group turns it into ghostly glass, even with the layer's glass switched off.

Translucency above about 0.6 lets the background wash the chips out at Dock size, and the fan should stay near 1.10 scale to match the visual weight of neighboring icons. In the Clear and Tinted renditions the chips differ only in lightness (green lightest, blue darkest).

On macOS, the dark appearance always uses the system's dark background; a custom dark fill is ignored.

Preview a build without opening Icon Composer:

```sh
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Icon/Undertone.icon \
    --export-image --output-file preview.png --platform macOS --rendition Default \
    --width 512 --height 512 --scale 2 --design-generation 26
```

Renditions include `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight` and `TintedDark`. `assets/icon.png` is the `Default` rendition at 256 points and scale 2; `assets/undertone-icon.png` is the same at scale 1.
