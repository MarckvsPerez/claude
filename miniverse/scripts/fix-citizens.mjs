// Fixes drawing glitches in the bundled character sheets before the colour variants are made.
// Usage: node scripts/fix-citizens.mjs && node scripts/recolor-citizens.mjs
//
// Sleeping (row 1 of <name>_actions.png) alternates two frames. In nova's sheet the second
// frame is drawn 17 px higher than the first, so she bobs up and down while asleep. Each
// sleeping frame is moved down so that its lowest pixel rests on the same line as the frame
// that sits lowest. Idempotent: an already aligned sheet is left untouched.

import sharp from 'sharp';

const DIR = new URL('../public/universal_assets/citizens/', import.meta.url);
const BASES = ['morty', 'nova', 'dexter', 'rio'];
const FRAME = 64;
const SLEEP_ROW = 1;
const SLEEP_FRAMES = 2;

for (const name of BASES) {
  const file = new URL(`${name}_actions.png`, DIR).pathname;
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const px = (x, y) => (y * info.width + x) * 4;

  const bottoms = [];
  for (let f = 0; f < SLEEP_FRAMES; f++) {
    let bottom = -1;
    for (let y = 0; y < FRAME; y++) {
      for (let x = 0; x < FRAME; x++) {
        if (data[px(f * FRAME + x, SLEEP_ROW * FRAME + y) + 3] > 40) bottom = y;
      }
    }
    bottoms.push(bottom);
  }
  const floor = Math.max(...bottoms);

  let moved = 0;
  bottoms.forEach((bottom, f) => {
    const shift = floor - bottom;
    if (bottom < 0 || shift === 0) return;
    // Copy the frame and paste it `shift` px lower, inside its own 64x64 cell.
    const cell = Buffer.alloc(FRAME * FRAME * 4);
    for (let y = 0; y < FRAME; y++) {
      for (let x = 0; x < FRAME; x++) {
        data.copy(cell, (y * FRAME + x) * 4, px(f * FRAME + x, SLEEP_ROW * FRAME + y), px(f * FRAME + x, SLEEP_ROW * FRAME + y) + 4);
        data.fill(0, px(f * FRAME + x, SLEEP_ROW * FRAME + y), px(f * FRAME + x, SLEEP_ROW * FRAME + y) + 4);
      }
    }
    for (let y = 0; y + shift < FRAME; y++) {
      for (let x = 0; x < FRAME; x++) {
        cell.copy(data, px(f * FRAME + x, SLEEP_ROW * FRAME + y + shift), (y * FRAME + x) * 4, (y * FRAME + x) * 4 + 4);
      }
    }
    moved++;
    console.log(`${name}: sleeping frame ${f + 1} moved down ${shift} px`);
  });

  if (moved > 0) await sharp(data, { raw: info }).png().toFile(file + '.tmp').then(() => import('node:fs').then((fs) => fs.renameSync(file + '.tmp', file)));
}
