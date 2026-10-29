/*
 * Undertone Organic gradient + film grain, ported from Sources/UndertoneKit/GradientRenderer.swift.
 * Same math as the app's CPU renderer: OKLab blending with chroma restore, the Still / Pull / Wave /
 * Classic flows, swirl, seeded grain in a 1280 px reference space, and the ±1/255 dither.
 *
 * Works as a plain <script> (sets globalThis.Undertone) and as a Node CommonJS module.
 *
 *   Undertone.render(recipe, width, height)          -> Uint8ClampedArray (RGBA)
 *   Undertone.renderToCanvas(recipe, canvas, w?, h?) -> canvas (browser)
 *   Undertone.layout(colors, options)                -> recipe with seeded point positions
 *
 * A recipe uses the keys of an exported .undertone.json file. Only the Organic style is ported;
 * other modes render as Organic.
 */
(function (root) {
  "use strict";

  const GRAIN_REFERENCE_SIZE = 1280;
  const EMPTY = [0.13, 0.14, 0.17];
  const FLOWS = ["still", "pull", "wave", "classic"];

  const DEFAULTS = {
    stops: [
      { hex: "F3AC91", x: 0.18, y: 0.2 },
      { hex: "7655A3", x: 0.78, y: 0.24 },
      { hex: "F3CC91", x: 0.34, y: 0.82 },
      { hex: "3B526E", x: 0.92, y: 0.85 },
    ],
    mode: "organic",
    organicFlow: "still",
    flow: 0.55,
    softness: 0.55,
    swirl: 0,
    textureEnabled: true,
    grain: 0.2,
    grainSize: 1,
    seed: 42,
    width: 2160,
    height: 2880,
  };

  // ---- Integer hashes (identical to the Swift / Metal versions) ----

  function hash32(input) {
    let v = input >>> 0;
    v ^= v >>> 16;
    v = Math.imul(v, 0x7feb352d) >>> 0;
    v ^= v >>> 15;
    v = Math.imul(v, 0x846ca68b) >>> 0;
    v ^= v >>> 16;
    return v >>> 0;
  }

  function hashNoise(x, y, seed) {
    const value = hash32((x + hash32((y + hash32(seed)) >>> 0)) >>> 0);
    return (value >>> 8) / 16777216 * 2 - 1;
  }

  function dither(column, row, channel) {
    const unit = (salt) =>
      (hash32((column + hash32((row + hash32((0x5eed0000 + salt) >>> 0)) >>> 0)) >>> 0) >>> 8) / 16777216;
    return (unit(channel * 2) + unit(channel * 2 + 1) - 1) / 255;
  }

  const MASK64 = (1n << 64n) - 1n;

  /** splitmix64 of seed + salt, as a value in 0..<1. */
  function seedUnit(seed, salt) {
    let v = (seed + BigInt(salt) * 0x9e3779b97f4a7c15n) & MASK64;
    v = ((v ^ (v >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK64;
    v = ((v ^ (v >> 27n)) * 0x94d049bb133111ebn) & MASK64;
    v ^= v >> 31n;
    return Number(v >> 11n) * (1 / 9007199254740992);
  }

  function toSeed(value) {
    if (typeof value === "bigint") return value & MASK64;
    if (typeof value === "string" && /^\d+$/.test(value)) return BigInt(value) & MASK64;
    if (typeof value === "number" && Number.isFinite(value) && value >= 0) return BigInt(Math.floor(value)) & MASK64;
    return 42n;
  }

  // ---- Color ----

  function clamp(value, lower, upper) {
    return Math.min(upper, Math.max(lower, Number.isFinite(value) ? value : lower));
  }

  function hexToRGB(hex) {
    const cleaned = String(hex || "").replace(/#/g, "");
    const value = /^[0-9a-fA-F]{1,8}$/.test(cleaned) ? parseInt(cleaned, 16) >>> 0 : 0;
    return [((value >>> 16) & 255) / 255, ((value >>> 8) & 255) / 255, (value & 255) / 255];
  }

  const linear = (v) => (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  const srgb = (v) => clamp(v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(Math.max(0, v), 1 / 2.4) - 0.055, 0, 1);

  function toOKLab([r8, g8, b8]) {
    const r = linear(r8), g = linear(g8), b = linear(b8);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [
      0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    ];
  }

  function fromOKLab(L, a, b, out) {
    const lr = L + 0.3963377774 * a + 0.2158037573 * b;
    const mr = L - 0.1055613458 * a - 0.0638541728 * b;
    const sr = L - 0.0894841775 * a - 1.291485548 * b;
    const l = lr * lr * lr, m = mr * mr * mr, s = sr * sr * sr;
    out[0] = srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s);
    out[1] = srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s);
    out[2] = srgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s);
    return out;
  }

  const normalized = (value, count) => (count === 1 ? 0.5 : value / (count - 1));
  const byte = (v) => Math.floor(Math.min(1, Math.max(0, v)) * 255 + 0.5);

  // ---- Scene ----

  function makeScene(input, width, height) {
    const recipe = Object.assign({}, DEFAULTS, input);
    width = Math.floor(width || recipe.width);
    height = Math.floor(height || recipe.height);
    if (!(width > 0 && height > 0 && width <= 8192 && height <= 8192)) {
      throw new RangeError(`Invalid size ${width}x${height}`);
    }
    const seed = toSeed(recipe.seed);
    const style = FLOWS.includes(recipe.organicFlow) ? recipe.organicFlow : "still";
    const stops = (recipe.stops || []).map((stop) => ({
      lab: toOKLab(hexToRGB(stop.hex)),
      x: clamp(stop.x, 0, 1),
      y: clamp(stop.y, 0, 1),
      weight: clamp(stop.weight == null ? 1 : stop.weight, 0.05, 4),
    }));
    const flow = clamp(recipe.flow, 0, 1);
    const softness = clamp(recipe.softness, 0, 1);
    const swirl = clamp(recipe.swirl, 0, 1);
    const phase = (Number(seed % 10000n) / 10000) * Math.PI * 2;
    const spin = (seed & 2n) === 0n ? 1 : -1;

    const brush = seedUnit(seed, 600) * Math.PI * 2;
    const pullStretch = style === "pull" ? 1 + flow * 2.6 : 1;
    const waveAngle = seedUnit(seed, 700) * Math.PI * 2;

    const scene = {
      width, height,
      hasColors: stops.length > 0,
      stops,
      chromas: stops.map((s) => Math.hypot(s.lab[1], s.lab[2])),
      pullCos: stops.map((_, i) => Math.cos(brush + (seedUnit(seed, 601 + i) - 0.5) * 0.9)),
      pullSin: stops.map((_, i) => Math.sin(brush + (seedUnit(seed, 601 + i) - 0.5) * 0.9)),
      pullStretch,
      pullNarrow: Math.sqrt(pullStretch),
      waveX: Math.cos(waveAngle),
      waveY: Math.sin(waveAngle),
      wavePhaseA: seedUnit(seed, 701) * Math.PI * 2,
      wavePhaseB: seedUnit(seed, 702) * Math.PI * 2,
      waveHeight: style === "wave" ? flow * 0.3 : 0,
      core: style === "classic"
        ? (0.0025 + softness * softness * 1.2) * (1 + swirl * 6.0)
        : 0.002 + softness * softness * 0.45,
      swirlStrength: swirl * swirl * 8.0 * spin,
      swirlCenterX: 0.5 + (seedUnit(seed, 91) - 0.5) * 0.5,
      swirlCenterY: 0.5 + (seedUnit(seed, 92) - 0.5) * 0.5,
      grain: recipe.textureEnabled === false ? 0 : clamp(recipe.grain, 0, 1),
      grainCellSize: Math.round(clamp(recipe.grainSize, 1, 128)),
      grainSeed: Number((seed ^ (seed >> 32n)) & 0xffffffffn) >>> 0,
      xWarp: null,
      yWarp: null,
    };

    if (style === "classic") {
      scene.xWarp = new Float64Array(height);
      for (let row = 0; row < height; row++) {
        const y = normalized(row, height);
        scene.xWarp[row] = flow * 0.14 * (Math.sin((y * 1.73 + 0.11) * Math.PI * 2 + phase) * 0.68 +
          Math.sin((y * 3.91 + 0.63) * Math.PI * 2 + phase * 1.7) * 0.32);
      }
      scene.yWarp = new Float64Array(width);
      for (let column = 0; column < width; column++) {
        const x = normalized(column, width);
        scene.yWarp[column] = flow * 0.14 * (Math.sin((x * 1.37 + 0.47) * Math.PI * 2 + phase * 1.3) * 0.72 +
          Math.sin((x * 3.23 + 0.19) * Math.PI * 2 + phase * 0.6) * 0.28);
      }
    }
    return scene;
  }

  function organicColor(scene, x, y, out) {
    let px = x, py = y;
    if (scene.waveHeight > 0) {
      const across = -px * scene.waveY + py * scene.waveX;
      const push = (Math.sin(across * 6.9 + scene.wavePhaseA) * 0.7 + Math.sin(across * 3.6 + scene.wavePhaseB) * 0.3) * scene.waveHeight;
      px += scene.waveX * push;
      py += scene.waveY * push;
    }
    if (scene.swirlStrength !== 0) {
      const dx = px - scene.swirlCenterX, dy = py - scene.swirlCenterY;
      const twist = scene.swirlStrength * Math.exp(-(dx * dx + dy * dy) * 3.2);
      const c = Math.cos(twist), s = Math.sin(twist);
      px = scene.swirlCenterX + dx * c - dy * s;
      py = scene.swirlCenterY + dx * s + dy * c;
    }
    let total = 0, L = 0, a = 0, b = 0, chroma = 0;
    const stops = scene.stops;
    for (let i = 0; i < stops.length; i++) {
      let dx = px - stops[i].x, dy = py - stops[i].y;
      if (scene.pullStretch !== 1) {
        const along = dx * scene.pullCos[i] + dy * scene.pullSin[i];
        const across = -dx * scene.pullSin[i] + dy * scene.pullCos[i];
        dx = along / scene.pullStretch;
        dy = across * scene.pullNarrow;
      }
      const distance = dx * dx + dy * dy + scene.core;
      const weight = stops[i].weight / (distance * distance);
      total += weight;
      L += stops[i].lab[0] * weight;
      a += stops[i].lab[1] * weight;
      b += stops[i].lab[2] * weight;
      chroma += scene.chromas[i] * weight;
    }
    a /= total; b /= total;
    const mixed = Math.sqrt(a * a + b * b);
    if (mixed > 1e-4) {
      const restore = 1 + (Math.min(chroma / total / mixed, 1.8) - 1) * 0.6;
      a *= restore; b *= restore;
    }
    return fromOKLab(L / total, a, b, out);
  }

  function grainAt(scene, column, row) {
    if (scene.grain <= 0) return 0;
    const longSide = Math.max(scene.width, scene.height, 1);
    const x = Math.floor((column * GRAIN_REFERENCE_SIZE) / longSide);
    const y = Math.floor((row * GRAIN_REFERENCE_SIZE) / longSide);
    const cell = scene.grainCellSize, seed = scene.grainSeed;
    let n;
    if (cell === 1) {
      n = hashNoise(x, y, seed);
    } else {
      const cx = Math.floor(x / cell), cy = Math.floor(y / cell);
      const fx = (x % cell) / cell, fy = (y % cell) / cell;
      const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
      const lerp = (p, q, t) => p + (q - p) * t;
      const top = lerp(hashNoise(cx, cy, seed), hashNoise(cx + 1, cy, seed), sx);
      const bottom = lerp(hashNoise(cx, cy + 1, seed), hashNoise(cx + 1, cy + 1, seed), sx);
      n = lerp(top, bottom, sy);
    }
    return n * scene.grain * 0.105;
  }

  /** Renders a recipe to 8-bit RGBA pixels. Width and height default to the recipe's own. */
  function render(recipe, width, height) {
    const scene = makeScene(recipe || {}, width, height);
    const { width: w, height: h } = scene;
    const pixels = new Uint8ClampedArray(w * h * 4);
    const color = [0, 0, 0];
    for (let row = 0; row < h; row++) {
      const y = normalized(row, h);
      for (let column = 0; column < w; column++) {
        if (scene.hasColors) {
          const x = normalized(column, w);
          if (scene.xWarp) organicColor(scene, x + scene.xWarp[row], y + scene.yWarp[column], color);
          else organicColor(scene, x, y, color);
        } else {
          color[0] = EMPTY[0]; color[1] = EMPTY[1]; color[2] = EMPTY[2];
        }
        const noise = grainAt(scene, column, row);
        const o = (row * w + column) * 4;
        pixels[o] = byte(color[0] + noise + dither(column, row, 0));
        pixels[o + 1] = byte(color[1] + noise + dither(column, row, 1));
        pixels[o + 2] = byte(color[2] + noise + dither(column, row, 2));
        pixels[o + 3] = 255;
      }
    }
    return pixels;
  }

  /** Browser: renders into a canvas, sizing it to width x height (defaults to the canvas's size). */
  function renderToCanvas(recipe, canvas, width, height) {
    width = Math.floor(width || canvas.width);
    height = Math.floor(height || canvas.height);
    canvas.width = width;
    canvas.height = height;
    const pixels = render(recipe, width, height);
    canvas.getContext("2d").putImageData(new ImageData(pixels, width, height), 0, 0);
    return canvas;
  }

  /**
   * Builds a recipe from a list of hex colors. Points are placed from `seed`, the same way the
   * app's Randomize places them (0.05...0.95 on each axis). Pass `positions: "ring"` for the app's
   * even ring layout instead. Any other recipe key in `options` is copied through.
   */
  function layout(colors, options) {
    const opts = Object.assign({}, options);
    const seed = toSeed(opts.seed == null ? Math.floor(Math.random() * 0xffffffff) + 1 : opts.seed);
    const ring = opts.positions === "ring";
    delete opts.positions;
    const stops = colors.map((hex, index) => {
      if (ring) {
        const angle = (index / Math.max(colors.length, 1)) * Math.PI * 2;
        return { hex: String(hex).replace(/#/g, "").toUpperCase(), x: 0.5 + Math.cos(angle) * 0.35, y: 0.5 + Math.sin(angle) * 0.35 };
      }
      return {
        hex: String(hex).replace(/#/g, "").toUpperCase(),
        x: 0.05 + seedUnit(seed, 1000 + index * 2) * 0.9,
        y: 0.05 + seedUnit(seed, 1001 + index * 2) * 0.9,
      };
    });
    return Object.assign({}, DEFAULTS, { stops, seed: seed.toString() }, opts, {
      mode: "organic",
      version: 5,
    });
  }

  /** The recipe as .undertone.json text the app can import (the seed is written as a bare integer). */
  function toRecipeJSON(recipe) {
    const full = Object.assign({}, DEFAULTS, recipe, { mode: "organic", version: 5 });
    const seed = toSeed(full.seed).toString();
    full.seed = "__SEED__";
    return JSON.stringify(full, null, 2).replace('"__SEED__"', seed);
  }

  /** Parses .undertone.json text, keeping a 64-bit seed exact. */
  function parseRecipeJSON(text) {
    return JSON.parse(String(text).replace(/("seed"\s*:\s*)(\d+)/, '$1"$2"'));
  }

  const api = { render, renderToCanvas, layout, toRecipeJSON, parseRecipeJSON, DEFAULTS, FLOWS };
  if (typeof module === "object" && module.exports) module.exports = api;
  root.Undertone = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
