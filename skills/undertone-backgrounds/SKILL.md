---
name: undertone-backgrounds
description: >-
  Render Undertone's Organic gradient with film grain as a background image (PNG/JPEG) or inside
  an HTML page or artifact. Use when the user wants a gradient, grainy, soft-color or "Undertone"
  background for a social post, ad, story, promo, slide, banner or web page, wants backgrounds
  at 1x1 / 4x5 / 9x16, or hands over an .undertone.json recipe to render. Output matches the
  Undertone Mac app's renderer pixel for pixel.
---

# Undertone backgrounds

`scripts/undertone.js` is a dependency-free port of the Undertone app's Organic style: colors
placed as points on the canvas, blended in OKLab, with four flows, swirl, seeded film grain and an
anti-banding dither. Given the same recipe and size it produces the same bytes as the app's CPU
renderer. Only Organic is ported; recipes in other modes (Mesh, Linear, Tonal, Glow, Aurora)
render as Organic.

## Recipe

A recipe is the JSON the app exports as `.undertone.json`. Keys that matter:

| Key | Range | Effect |
| --- | --- | --- |
| `stops` | 1–8 of `{hex, x, y, weight?}` | Color points. `x`, `y` are 0–1 from the top left. `weight` 0.05–4 (default 1) grows a color's area. |
| `organicFlow` | `still` `pull` `wave` `classic` | Still: colors melt in place. Pull: each color smears in a seeded direction. Wave: borders ripple. Classic: broad sine warp. |
| `flow` | 0–1 (0.55) | How far Pull smears, how high Wave runs, how strong the Classic warp is. No effect on Still. |
| `softness` | 0–1 (0.55) | Width of the blend between colors. |
| `swirl` | 0–1 (0) | A vortex; the seed picks its center and direction. |
| `grain` | 0–1 (0.2) | Film grain strength. 0 or `textureEnabled: false` turns it off. |
| `grainSize` | 1–10 (1) | Grain cell size, measured in a 1280 px reference so grain looks the same at any output size. |
| `seed` | integer | Sets flow directions, swirl center, grain pattern, and point positions when built with `layout`. |
| `width`, `height` | px | Default output size. |

Points are in normalized coordinates, so one recipe rendered at 1×1, 4×5 and 9×16 stretches with
the canvas. Put the color you want behind text away from where the text goes, and keep a dark or
light point near the text area for contrast.

## Render image files (social posts, ads)

```bash
node ~/.claude/skills/undertone-backgrounds/scripts/render.js \
  --colors 012169,418FDE,DAE1E8,0A1730 --flow wave --amount 0.6 --swirl 0.3 --seed 2026 \
  --size 1x1,4x5,9x16 --out out/promo --save-recipe
```

- `--size` takes `WxH` or presets: `1x1` 1080×1080, `4x5` 1080×1350, `9x16` 1080×1920,
  `16x9` 1920×1080, `instagram` 2160×2880, `square` 2048×2048, `story` 1440×2560. `--scale 2`
  doubles the presets.
- Several sizes write `out/promo-1x1.png`, `out/promo-4x5.png`, … A single size with an
  `.png`/`.jpg` `--out` writes exactly that file.
- `--recipe file.undertone.json` renders a recipe from the app; other flags override its values.
- `--ring` places `--colors` evenly on a ring instead of at seeded positions.
- `--format jpg` converts through macOS `sips` at quality 95.
- `--save-recipe` writes `<out>.undertone.json`; File → Import Recipe in the app opens it for
  hand-tuning.
- Each file written prints one JSON line with its path, size and render time. 1080×1350 takes
  about 0.5 s.

To place points yourself, write a recipe file with explicit `stops` and pass `--recipe`. Try 2–4
seeds and look at the results (Read the PNG) before picking one; the seed changes the layout a lot
when points come from `--colors`.

## Use in HTML pages and artifacts

Inline `scripts/undertone.js` (14 KB) in a `<script>` tag rather than embedding a
rendered PNG as a data URI; it renders in the viewer's browser. It sets `window.Undertone`.

```html
<canvas id="bg" style="position:absolute;inset:0;width:100%;height:100%;z-index:-1"></canvas>
<script>/* paste the contents of scripts/undertone.js here */</script>
<script>
  const recipe = {
    stops: [
      { hex: "0A1730", x: 0.15, y: 0.2 },
      { hex: "2068FF", x: 0.8, y: 0.3, weight: 1.4 },
      { hex: "B8CFEA", x: 0.3, y: 0.85 },
    ],
    organicFlow: "pull", flow: 0.7, softness: 0.5, grain: 0.3, seed: 7,
  };
  const canvas = document.getElementById("bg");
  const scale = Math.min(window.devicePixelRatio || 1, 2);
  Undertone.renderToCanvas(recipe, canvas,
    canvas.clientWidth * scale, canvas.clientHeight * scale);
</script>
```

- Rendering runs on the main thread; Node renders about 3 megapixels per second with 4 colors. Render at the displayed size
  times `devicePixelRatio` (capped at 2), not at export resolution.
- For a fixed post canvas (e.g. a 1080×1350 card), render at exactly that size so grain matches
  the PNG export.
- `canvas.toDataURL("image/png")` gives a downloadable image of the result.

## API

- `Undertone.render(recipe, width, height)` → `Uint8ClampedArray` of RGBA pixels.
- `Undertone.renderToCanvas(recipe, canvas, width?, height?)` → resizes the canvas and draws.
- `Undertone.layout(colors, options?)` → a full recipe; points placed from `options.seed`
  (`positions: "ring"` for the ring layout). Other recipe keys in `options` are copied in.
- `Undertone.toRecipeJSON(recipe)` / `Undertone.parseRecipeJSON(text)` → app-compatible JSON;
  keeps 64-bit seeds exact.

## Brand colors

The app ships a Coldwell Banker collection: Coldwell Banker Blue `012169`, Midnight `0A1730`,
Slate `1B3C55`, Smoky Gray `58718D`, Celestial `418FDE`, Bright Blue `2068FF`, Tide `B8CFEA`,
Mist `BECAD7`, Glacier `DAE1E8`, Icy Blue `F0F5FB`. For AdLab (Coldwell Banker Commercial) work,
read the palette from AdLab's `get_brand_rules` first; it can differ from this list.

## Source

Ported from `Sources/UndertoneKit/GradientRenderer.swift` in the Undertone repository
(`skills/undertone-backgrounds/`). After changing the Swift Organic or grain math, port the change
here and recheck parity with `SampleRenderTests` (see the repository's `skills/README.md`).
