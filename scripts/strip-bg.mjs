// Flood-fills white-ish pixels from the image edges and turns them
// transparent. Interior white (chef hat, wizard beard, ghost body) survives
// because the fill never reaches it through dark outlines.
//
// Pollinations returns JPEG bytes even when the URL extension is .png,
// so sharp is used for format-agnostic decode + true PNG (RGBA) re-encode.
//
// Per-directory thresholds — sword sprites are simpler shapes with cleaner
// outlines, so they tolerate a more aggressive sweep + an anti-fringe feather
// pass that fades alpha on still-opaque pixels touching transparent ones.
// Character sprites use a tighter threshold to protect interior whites
// (chef hat, wizard beard, etc.).
//
// Usage:  node scripts/strip-bg.mjs

import { readFile, writeFile, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));

const TARGETS = [
  // Swords — aggressive: wider white threshold + lower shadow value floor
  // + edge feather to kill the AA fringe at the blade outline.
  {
    dir: join(__dirname, '..', 'assets', 'swords'),
    whiteThreshold: 215,
    shadowValueMin: 120,
    shadowSatMax: 50,
    edgeFeatherLuminance: 175,  // any opaque-touching-transparent pixel ≥ L → fade
  },
  // Characters / bosses — conservative: keep the original thresholds so
  // interior whites (chef hat, etc.) survive.
  {
    dir: join(__dirname, '..', 'assets', 'characters', 'characters'),
    whiteThreshold: 235,
    shadowValueMin: 145,
    shadowSatMax: 35,
    edgeFeatherLuminance: 0,  // off
  },
  {
    dir: join(__dirname, '..', 'assets', 'characters', 'bosses'),
    whiteThreshold: 235,
    shadowValueMin: 145,
    shadowSatMax: 35,
    edgeFeatherLuminance: 0,
  },
];

function maxChannelDiff(r, g, b) {
  return Math.max(Math.abs(r - g), Math.abs(g - b), Math.abs(r - b));
}

function luminance(r, g, b) {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

function makeIsWhiteish(threshold) {
  return (r, g, b) => r >= threshold && g >= threshold && b >= threshold;
}

function makeIsShadowGrey(valueMin, satMax, whiteThreshold) {
  return (r, g, b) => {
    if (r < valueMin || g < valueMin || b < valueMin) return false;
    if (r >= whiteThreshold && g >= whiteThreshold && b >= whiteThreshold) return true;
    return maxChannelDiff(r, g, b) <= satMax;
  };
}

function floodFillFromEdges(rgba, width, height, predicate) {
  const visited = new Uint8Array(width * height);
  const queue = [];
  const push = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const idx = y * width + x;
    if (visited[idx]) return;
    const off = idx * 4;
    if (rgba[off + 3] === 0) {
      visited[idx] = 1;
      queue.push(idx);
      return;
    }
    if (!predicate(rgba[off], rgba[off + 1], rgba[off + 2])) return;
    visited[idx] = 1;
    queue.push(idx);
  };

  for (let x = 0; x < width; x++) {
    push(x, 0);
    push(x, height - 1);
  }
  for (let y = 0; y < height; y++) {
    push(0, y);
    push(width - 1, y);
  }

  while (queue.length) {
    const idx = queue.pop();
    rgba[idx * 4 + 3] = 0;
    const x = idx % width;
    const y = (idx - x) / width;
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }
}

// For any opaque pixel touching a transparent neighbour: if its luminance is
// over `lumThreshold`, fade its alpha proportional to brightness — kills the
// 1-2px white anti-aliased fringe that survives the flood fill. Single-pass
// (no recursion), so it only eats the outermost ring, never bites into the
// sprite interior.
function featherEdges(rgba, width, height, lumThreshold) {
  if (lumThreshold <= 0) return;
  const isTransparent = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return true;
    return rgba[(y * width + x) * 4 + 3] === 0;
  };
  // Snapshot original alpha so we don't cascade through the same pass.
  const origAlpha = new Uint8Array(width * height);
  for (let i = 0; i < origAlpha.length; i++) origAlpha[i] = rgba[i * 4 + 3];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      if (origAlpha[idx] === 0) continue;
      // Edge-touch check uses original alpha to keep determinism.
      const edge = origAlpha[(Math.max(0, y - 1) * width) + x] === 0
        || origAlpha[(Math.min(height - 1, y + 1) * width) + x] === 0
        || origAlpha[y * width + Math.max(0, x - 1)] === 0
        || origAlpha[y * width + Math.min(width - 1, x + 1)] === 0
        || x === 0 || y === 0 || x === width - 1 || y === height - 1;
      if (!edge) continue;
      const off = idx * 4;
      const l = luminance(rgba[off], rgba[off + 1], rgba[off + 2]);
      if (l < lumThreshold) continue;
      // Linearly fade from full alpha at lumThreshold to 0 at 255.
      const t = Math.min(1, (l - lumThreshold) / (255 - lumThreshold));
      rgba[off + 3] = Math.round(origAlpha[idx] * (1 - t));
    }
  }
}

async function processFile(path, opts) {
  const input = await readFile(path);
  const img = sharp(input).ensureAlpha();
  const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
  floodFillFromEdges(data, info.width, info.height,
    makeIsWhiteish(opts.whiteThreshold));
  floodFillFromEdges(data, info.width, info.height,
    makeIsShadowGrey(opts.shadowValueMin, opts.shadowSatMax, opts.whiteThreshold));
  featherEdges(data, info.width, info.height, opts.edgeFeatherLuminance);
  const out = await sharp(data, {
    raw: { width: info.width, height: info.height, channels: 4 },
  })
    .png({ compressionLevel: 9 })
    .toBuffer();
  await writeFile(path, out);
  return out.length;
}

async function main() {
  for (const target of TARGETS) {
    let files;
    try {
      files = (await readdir(target.dir)).filter((f) => f.endsWith('.png'));
    } catch (e) {
      if (e.code === 'ENOENT') continue;
      throw e;
    }
    for (const file of files) {
      const size = await processFile(join(target.dir, file), target);
      console.log(`✓ ${file} (${(size / 1024).toFixed(1)} KB)`);
    }
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
