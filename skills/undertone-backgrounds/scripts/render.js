#!/usr/bin/env node
/*
 * Renders Undertone Organic backgrounds to PNG (or JPEG on macOS, through sips).
 *
 *   node render.js --colors 0A1730,2068FF,B8CFEA --flow pull --seed 7 --size 4x5 --out bg.png
 *   node render.js --recipe "Harbor Hush.undertone.json" --size 1x1,4x5,9x16 --out out/harbor
 *
 * Options
 *   --recipe FILE      .undertone.json exported from the app (other options override its values)
 *   --colors HEX,...   colors for a new recipe; points are placed from --seed
 *   --ring             place --colors on an even ring instead of seeded positions
 *   --flow NAME        still | pull | wave | classic
 *   --amount N         Flow slider, 0-1 (how far Pull drags / how high Wave runs / Classic warp)
 *   --softness N       0-1
 *   --swirl N          0-1
 *   --grain N          0-1 (0 turns grain off)
 *   --grain-size N     1-10 (grain cell size in the 1280 px reference space)
 *   --seed N           integer; sets point positions, flow directions, swirl and grain
 *   --size LIST        WxH or a preset, comma-separated: 1x1 (1080x1080), 4x5 (1080x1350),
 *                      9x16 (1080x1920), 16x9 (1920x1080), instagram (2160x2880),
 *                      square (2048x2048), story (1440x2560). Default: the recipe's size.
 *   --scale N          multiply preset sizes (e.g. 2 for 2160x2700 at 4x5)
 *   --format png|jpg   jpg needs macOS sips
 *   --out PATH         file, or a base path when rendering several sizes ("-1x1.png" is appended)
 *   --save-recipe      also write <out>.undertone.json, importable in the app
 *
 * Prints one JSON line per file written.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { execFileSync } = require("child_process");
const Undertone = require("./undertone.js");

const PRESETS = {
  "1x1": [1080, 1080],
  "4x5": [1080, 1350],
  "9x16": [1080, 1920],
  "16x9": [1920, 1080],
  instagram: [2160, 2880],
  square: [2048, 2048],
  story: [1440, 2560],
};

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (!token.startsWith("--")) throw new Error(`Unexpected argument: ${token}`);
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) args[key] = true;
    else { args[key] = next; i++; }
  }
  return args;
}

const CRC_TABLE = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});

function crc32(buffer) {
  let c = -1;
  for (let i = 0; i < buffer.length; i++) c = CRC_TABLE[(c ^ buffer[i]) & 255] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** RGB PNG with an sRGB chunk. */
function encodePNG(rgba, width, height) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 3 + 1);
    for (let x = 0; x < width; x++) {
      const s = (y * width + x) * 4, d = rowStart + 1 + x * 3;
      raw[d] = rgba[s]; raw[d + 1] = rgba[s + 1]; raw[d + 2] = rgba[s + 2];
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 2; // 8-bit truecolor
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("sRGB", Buffer.from([0])),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function parseSize(token, scale) {
  const preset = PRESETS[token.toLowerCase()];
  if (preset) return { label: token, width: Math.round(preset[0] * scale), height: Math.round(preset[1] * scale) };
  const match = /^(\d+)x(\d+)$/i.exec(token);
  if (!match) throw new Error(`Unknown size "${token}". Use WxH or one of: ${Object.keys(PRESETS).join(", ")}`);
  return { label: `${match[1]}x${match[2]}`, width: +match[1], height: +match[2] };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || (!args.recipe && !args.colors)) {
    process.stdout.write(fs.readFileSync(__filename, "utf8").split("*/")[0].replace(/^#!.*\n\/\*\n?/, ""));
    process.exit(args.help ? 0 : 1);
  }

  let recipe = args.recipe
    ? Undertone.parseRecipeJSON(fs.readFileSync(args.recipe, "utf8"))
    : Undertone.layout(String(args.colors).split(/[,\s]+/).filter(Boolean), {
        seed: args.seed === undefined ? undefined : String(args.seed),
        positions: args.ring ? "ring" : undefined,
      });
  if (args.recipe && recipe.mode && recipe.mode !== "organic") {
    console.error(`Note: recipe mode "${recipe.mode}" is not ported; rendering it as Organic.`);
  }
  const number = (key) => (args[key] === undefined ? undefined : Number(args[key]));
  const overrides = {
    organicFlow: args.flow,
    flow: number("amount"),
    softness: number("softness"),
    swirl: number("swirl"),
    grain: number("grain"),
    grainSize: args["grain-size"] === undefined ? undefined : Math.min(10, Math.max(1, number("grain-size"))),
    seed: args.recipe && args.seed !== undefined ? String(args.seed) : undefined,
  };
  for (const [key, value] of Object.entries(overrides)) if (value !== undefined) recipe[key] = value;
  if (recipe.organicFlow && !Undertone.FLOWS.includes(recipe.organicFlow)) {
    throw new Error(`--flow must be one of ${Undertone.FLOWS.join(", ")}`);
  }

  const scale = Number(args.scale || 1);
  const sizes = args.size
    ? String(args.size).split(",").map((t) => parseSize(t.trim(), scale))
    : [{ label: `${recipe.width || 2160}x${recipe.height || 2880}`, width: recipe.width || 2160, height: recipe.height || 2880 }];
  const format = String(args.format || "png").toLowerCase().replace("jpeg", "jpg");
  const out = String(args.out || "undertone");
  const base = out.replace(/\.(png|jpe?g)$/i, "");
  fs.mkdirSync(path.dirname(path.resolve(base)), { recursive: true });

  for (const size of sizes) {
    const file = sizes.length === 1 && /\.(png|jpe?g)$/i.test(out) ? out : `${base}-${size.label}.${format}`;
    const started = Date.now();
    const pixels = Undertone.render(recipe, size.width, size.height);
    const png = encodePNG(pixels, size.width, size.height);
    if (format === "jpg") {
      const temp = `${file}.tmp.png`;
      fs.writeFileSync(temp, png);
      execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "95", temp, "--out", file], { stdio: "ignore" });
      fs.unlinkSync(temp);
    } else {
      fs.writeFileSync(file, png);
    }
    console.log(JSON.stringify({ file: path.resolve(file), width: size.width, height: size.height, ms: Date.now() - started }));
  }

  if (args["save-recipe"]) {
    const recipeFile = `${base}.undertone.json`;
    const first = sizes[0];
    fs.writeFileSync(recipeFile, Undertone.toRecipeJSON(Object.assign({}, recipe, { width: first.width, height: first.height })));
    console.log(JSON.stringify({ recipe: path.resolve(recipeFile) }));
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
