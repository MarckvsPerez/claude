// Cozy Startup: the zoned office built from the world's original world.json.
//
// 23x24 grid. Rows 0-1: wall, fully covered by props so nobody walks on it.
//   Whiteboard:   the lead, working standing.
//   Top row:      designer, front | ai (centre desk) | back, test-runner, database (back
//                 office, on concrete).
//   Bottom row:   coffee bar with the chat table, reviewer, explorer, recovery capsule and
//                 docs-researcher (the last three in the lower back office, on concrete).
//   Rest strip:   5 rugs of 2 beanbags, one beanbag per character (REST_PAIRS).
//   Annex (rows 16-23, own floor): 4 desks for repo agents and, below, their own sofas.
// A desk is 3x2 cells with the chair below. The "work" anchor sits one cell below the chair:
// the engine draws a working character 1.2 cells above its anchor, so it ends up in the chair.

import { readFileSync } from 'node:fs';

export function layout({ mainAgents, annexAgents }) {
  const original = JSON.parse(readFileSync(new URL('../../public/worlds/cozy-startup/world.original.json', import.meta.url), 'utf8'));

  // Fixed desk per agent. Top row, left to right: designer and front by the windows, ai at
  // the centre desk, then back, test-runner and database in the back office. Bottom row:
  // reviewer, then explorer and docs-researcher in the lower back office. The lead works
  // standing at the whiteboard. A desk whose agent the plugin doesn't have stays free.
  const DESKS = {
    designer: { x: 1, y: 3 },
    front: { x: 4, y: 3 },
    ai: { x: 8.25, y: 3, w: 2.7 },
    back: { x: 12, y: 3 },
    'test-runner': { x: 16, y: 3 },
    database: { x: 19, y: 3 },
    reviewer: { x: 8.25, y: 8, w: 2.7 },
    explorer: { x: 12, y: 8 },
    'docs-researcher': { x: 19, y: 8 },
  };

  // Fixed sofa per character, in pairs sharing a rug, left to right.
  const REST_PAIRS = [
    ['front', 'designer'],
    ['back', 'lead'],
    ['ai', 'database'],
    ['docs-researcher', 'reviewer'],
    ['explorer', 'test-runner'],
  ];

  const COLS = 23;
  const ROWS = 24;
  const ANNEX_TOP = 16;

  const floor = Array.from({ length: ROWS }, (_, r) =>
    Array.from({ length: COLS }, (_, c) => {
      if (r < 2) return 'exposed_brick_wall';
      if (r >= ANNEX_TOP) return 'annex_floor';
      const backOffice = c >= 12 && r <= 11;
      return backOffice ? 'concrete_accent' : 'main_floor';
    }),
  );

  const tiles = { ...original.tiles, annex_floor: 'world_assets/tiles/annex_floor.png' };

  const propImages = {
    ...original.propImages,
    desk_wood_modern: 'world_assets/props/prop_0_desk_wood_modern.png',
    whiteboard_large: 'world_assets/props/prop_8_whiteboard_large.png',
    recovery_capsule: 'world_assets/props/prop_namek_recovery_capsule.png',
    potted_plant_small: 'world_assets/props/prop_3_potted_plant_small.png',
    bean_bag_chair_grey: 'world_assets/props/prop_6_bean_bag_chair_grey.png',
    beanbag_orange: 'world_assets/props/prop_6_beanbag_orange.png',
  };

  const props = [];
  const add = (id, x, y, w, h, extra = {}) => props.push({ id, x, y, w, h, layer: 'below', ...extra });

  // Desk with chair. The chair goes in the second whole column the desk touches, and the
  // work anchor one cell below the chair (see the note at the top).
  const desk = (role, x, y, { id = 'wooden_desk_single', w = 3 } = {}) => {
    const chairX = Math.floor(x) + 1;
    add(id, x, y, w, 2, { anchors: [{ name: `desk_${role}`, ox: chairX - x, oy: 3, type: 'work' }] });
    add('ergonomic_chair', chairX, y + 2, 1, 1, { layer: 'above' });
  };

  // --- Wall (y = 0): covers columns 1-21 ---
  add('large_window', 1, 0, 3, 2);
  add('large_window', 4, 0, 3, 2);
  // The lead works standing at the whiteboard (main.ts removes the seated offset), so its
  // anchor sits on the first floor row, right against the board.
  add('whiteboard_large', 7, 0, 3, 2, { anchors: [{ name: 'desk_lead', ox: 1, oy: 2, type: 'work' }] });
  add('wooden_framed_whiteboard', 10, 0.5, 2, 1.5, { anchors: [{ name: 'planning_board', ox: 1, oy: 1.5, type: 'social' }] });
  add('large_window', 12, 0, 3, 2);
  add('large_window', 15, 0, 3, 2);
  add('tall_potted_plant', 18, 0, 1, 2);
  add('large_window', 19, 0, 3, 2);

  // --- Desks (see DESKS) ---
  for (const [name, { x, y, w }] of Object.entries(DESKS)) {
    desk(mainAgents.includes(name) ? name : `free_${name}`, x, y, w ? { w } : {});
  }
  add('tall_potted_plant', 15, 2.75, 1, 2);

  // --- Coffee bar (bottom left), with the chat table just above it ---
  add('coffee_bar_counter', 1, 8, 2.5, 2.3, { anchors: [{ name: 'coffee_bar', ox: 1, oy: 2.5, type: 'social' }] });
  add('espresso_machine', 1.4, 8.2, 1.1, 0.8);
  add('mini_fridge', 3.75, 8.5, 0.8, 1.1);
  add('low_coffee_table', 3.25, 6.75, 1.5, 1.5, { anchors: [{ name: 'chat_table', ox: 0.75, oy: 1.9, type: 'social' }] });
  add('tall_potted_plant', 7.25, 8, 1, 2);

  // --- Recovery capsule, in the lower back office between explorer and docs-researcher ---
  add('recovery_capsule', 15, 7.25, 4, 3.67);

  // --- Rest area: bottom strip with 5 rugs of 2 beanbags, one beanbag per character ---
  // Beanbags sit on rows 12-13 and their "rest_<name>" anchor on row 14, which stays free as
  // a corridor. As with desks, the engine draws a sleeping character 1.2 cells higher.
  // main.ts sends each character to its own beanbag.
  const BEANBAGS = ['bean_bag_chair_dark', 'beanbag_orange', 'bean_bag_chair_light', 'bean_bag_chair_grey'];
  [1.2, 5.2, 10.2, 14.2, 18.2].forEach((x) => add('area_rug_lounge', x, 12, 3.8, 2));
  const BEANBAG_X = [[2, 4], [6, 8], [11, 13], [15, 17], [19, 21]];
  REST_PAIRS.forEach((pair, r) => pair.forEach((name, i) => {
    const ax = BEANBAG_X[r][i];
    add(BEANBAGS[(r * 2 + i) % BEANBAGS.length], ax - 0.6, 12.3, 1.3, 1.3, {
      anchors: [{ name: `rest_${name}`, ox: 0.6, oy: 1.7, type: 'rest' }],
    });
  }));

  // --- Annex: 4 desks for repo agents (rows 16-19), work anchors on row 19 ---
  // Desks at x 3, 8, 13, 18 (centred on the 23 columns) so each chair (columns 4, 9, 14, 19)
  // sits above its own sofa, with a plant beside each desk and columns 7, 12 and 17 free to
  // walk through.
  const ANNEX_X = [3, 8, 13, 18];
  ANNEX_X.forEach((x, i) => desk(annexAgents[i] ?? `annex_free_${i + 1}`, x, ANNEX_TOP));
  [6, 11, 16].forEach((x) => add('tall_potted_plant', x, ANNEX_TOP, 1, 2));
  // --- Annex rest row: one sofa per desk on rows 20-21, "rest_annex_N" anchors on row 22 ---
  ANNEX_X.forEach((x) => add('area_rug_lounge', x - 0.4, 20, 3, 2));
  ANNEX_X.forEach((x, i) => {
    const ax = x + 1;
    add(BEANBAGS[(i + 1) % BEANBAGS.length], ax - 0.6, 20.3, 1.3, 1.3, {
      anchors: [{ name: `rest_annex_${i + 1}`, ox: 0.6, oy: 1.7, type: 'rest' }],
    });
  });

  const wanderPoints = [
    { name: 'corridor_west', x: 4, y: 7 },
    { name: 'corridor_centre', x: 10, y: 7 },
    { name: 'corridor_east', x: 15, y: 7 },
    { name: 'corridor_far_east', x: 20, y: 7 },
    { name: 'corridor_south', x: 10, y: 11 },
    { name: 'annex_corridor', x: 12, y: 19 },
  ];

  return { ...original, gridCols: COLS, gridRows: ROWS, floor, tiles, propImages, props, wanderPoints };
}
