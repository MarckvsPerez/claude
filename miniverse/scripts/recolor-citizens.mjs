// Builds colour variants of the 4 bundled characters by shifting the hue of their clothes
// only, so skin and hair stay as drawn. Same silhouettes and animations, different outfits.
// Usage: node scripts/recolor-citizens.mjs   (writes <variant>_walk.png and _actions.png)
//
// Each range is a hue band (degrees, may wrap past 360) measured on the original sheets;
// skin and hair sit around 15°-30° and are never inside a band.

import sharp from 'sharp';

const DIR = new URL('../public/universal_assets/citizens/', import.meta.url);

const VARIANTS = [
  // morty's red hoodie → blue. minL keeps the darker reddish strands of his hair out.
  { name: 'morty-blue', base: 'morty', bands: [{ from: 325, to: 10, minS: 0.3, minL: 0.26, shift: 215 }] },
  // dexter's navy jacket → forest green
  { name: 'dexter-green', base: 'dexter', bands: [{ from: 200, to: 250, minS: 0.2, shift: -75 }] },
  // rio's purple hoodie → teal
  { name: 'rio-teal', base: 'rio', bands: [{ from: 265, to: 340, minS: 0.18, shift: -120 }] },
  // nova's green top → khaki, blue jeans → burgundy
  {
    name: 'nova-khaki',
    base: 'nova',
    bands: [
      // The top is a washed-out green (≈105°-137°, saturation ≈0.2): push it towards mustard and
      // saturate it, or it still reads as green.
      { from: 50, to: 165, minS: 0.1, shift: -78, satMul: 1.9 },
      { from: 195, to: 250, minS: 0.12, shift: 140 },
    ],
  },
];

const toHsl = (r, g, b) => {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn, s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  let h;
  if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (mx === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
};

const toRgb = (h, s, l) => {
  h = ((h % 360) + 360) % 360 / 360;
  if (s === 0) return [l, l, l].map((v) => Math.round(v * 255));
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => {
    t = (t + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map((v) => Math.round(v * 255));
};

const inBand = (h, { from, to }) => (from <= to ? h >= from && h <= to : h >= from || h <= to);

for (const variant of VARIANTS) {
  for (const sheet of ['walk', 'actions']) {
    const src = new URL(`${variant.base}_${sheet}.png`, DIR);
    const { data, info } = await sharp(src.pathname).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    let changed = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] === 0) continue;
      const [h, s, l] = toHsl(data[i], data[i + 1], data[i + 2]);
      const band = variant.bands.find((b) => s >= b.minS && l >= (b.minL ?? 0) && inBand(h, b));
      if (!band) continue;
      [data[i], data[i + 1], data[i + 2]] = toRgb(h + band.shift, Math.min(1, s * (band.satMul ?? 1)), l);
      changed++;
    }
    const out = new URL(`${variant.name}_${sheet}.png`, DIR);
    await sharp(data, { raw: info }).png().toFile(out.pathname);
    console.log(`${variant.name}_${sheet}.png: ${changed} pixels recoloured`);
  }
}
