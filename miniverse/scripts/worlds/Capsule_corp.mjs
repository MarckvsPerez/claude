// Capsule Corp: ivory and cobalt lab-office, built from the assets in
// public/worlds/Capsule_corp (tiles/ and props/, see its manifest.json).
//
// The props are drawn for a 48px cell and the characters for a 32px one, so each prop is
// placed at 2/3 of its pixel size (pixels / 48 = cells, read from the PNG). The original files
// are used as they are: main.ts renders the canvas at screen resolution, so shrinking them
// doesn't lose detail. Every prop blocks every cell it touches, so anchors sit on free cells.
//
// 40x22 grid, landscape so it fits a laptop screen at about x1:
//   Rows 0-1    Wall with windows, the Capsule Corp sign and two blueprint screens. The lead
//               works standing in front of the screens (row 2).
//   Rows 3-7    Desks: designer, front, ai | back, test-runner, database.
//   Rows 8-14   Coffee corner and reviewer | medical bay: explorer, recovery capsule,
//               docs-researcher.
//   Rows 15-21  Lounge: two rows of 5 sofas, one per main character, and the dragon balls
//               display on its four-star rug.
//   Cols 27-39  Annex (ivory floor): 4 desks for repo agents and their 4 sofas.
// A desk is a workstation with its chair below; the "work" anchor sits on the cell below the
// chair, because the engine draws a working character 1.2 cells above its anchor.

import { readFileSync } from 'node:fs';

const DIR = new URL('../../public/worlds/Capsule_corp/', import.meta.url);
// Prop pixels per cell: the props are drawn for 48px cells, the world uses 32px ones.
const PROP_CELL = 48;
// The recovery capsule comes from another set at a much larger size: drawn at a
// workstation's footprint (128x112 px of this set).
const SOURCE_SIZE = { recovery_capsule: [128, 112] };

// Width and height of a PNG, from its IHDR chunk.
const pngSize = (file) => {
  const b = readFileSync(new URL(file, DIR));
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
};

export function layout({ mainAgents, annexAgents }) {
  const COLS = 40;
  const ROWS = 22;
  const ANNEX_LEFT = 27;

  // --- Floor: blue base, circuit outlines around each zone, medical bay, ivory annex ---
  const floor = Array.from({ length: ROWS }, (_, r) =>
    Array.from({ length: COLS }, (_, c) => (r < 2 || c > ANNEX_LEFT ? 'floor_ivory' : 'floor_blue')),
  );
  const fill = (c0, r0, c1, r1, tile) => {
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) floor[r][c] = tile;
  };
  // Circuit line along the edge of a rectangle (inclusive cells). Corner tiles are named after
  // the two directions their line leaves the cell's centre: se = top-left corner, and so on.
  const outline = (c0, r0, c1, r1) => {
    for (let c = c0 + 1; c < c1; c++) floor[r0][c] = floor[r1][c] = 'circuit_horizontal';
    for (let r = r0 + 1; r < r1; r++) floor[r][c0] = floor[r][c1] = 'circuit_vertical';
    floor[r0][c0] = 'circuit_corner_se';
    floor[r0][c1] = 'circuit_corner_sw';
    floor[r1][c0] = 'circuit_corner_ne';
    floor[r1][c1] = 'circuit_corner_nw';
  };
  outline(0, 2, 13, 7); // west desks
  outline(14, 2, 26, 7); // east desks
  outline(0, 8, 13, 14); // coffee corner and reviewer
  fill(15, 9, 25, 13, 'floor_medical');
  outline(14, 8, 26, 14); // medical bay
  outline(0, 15, 26, ROWS - 1); // lounge

  const tiles = Object.fromEntries(
    ['floor_blue', 'floor_ivory', 'floor_medical', 'circuit_horizontal', 'circuit_vertical',
      'circuit_corner_nw', 'circuit_corner_ne', 'circuit_corner_se', 'circuit_corner_sw']
      .map((t) => [t, `tiles/${t}.png`]),
  );

  const USED = ['wall_left', 'wall_middle', 'wall_right', 'window_capsule_city', 'sign_capsule_corp',
    'screen_blueprint', 'wall_clock', 'workstation_complete', 'chair_orange', 'chair_blue',
    'namek_tree', 'namek_bonsai', 'coffee_counter_complete', 'capsule_vending', 'fridge',
    'water_cooler', 'meeting_table', 'medical_platform', 'recovery_capsule', 'server_cabinet',
    'sofa_orange', 'sofa_blue', 'coffee_table', 'display_seven_dragon_balls', 'rug_four_stars'];
  const propImages = Object.fromEntries(USED.map((id) => [id, `props/${id}.png`]));
  const size = Object.fromEntries(USED.map((id) => [
    id, (SOURCE_SIZE[id] ?? pngSize(propImages[id])).map((px) => px / PROP_CELL),
  ]));

  const props = [];
  // A prop at its own size, top-left corner at (x, y) in cells.
  const add = (id, x, y, extra = {}) => {
    const [w, h] = size[id];
    props.push({ id, x, y, w, h, layer: 'below', ...extra });
  };
  // A prop centred on column cx + 0.5 (the centre of a character standing on column cx).
  const addCentred = (id, cx, y, extra) => add(id, cx + 0.5 - size[id][0] / 2, y, extra);

  // Workstation for `name`, seated character on column cx. The chair is drawn below the
  // characters so the sitter covers its back.
  const desk = (name, cx, y, chair = 'chair_orange') => {
    const [, h] = size.workstation_complete;
    const chairY = y + h - 0.33;
    addCentred('workstation_complete', cx, y, {
      anchors: [{ name: `desk_${name}`, ox: size.workstation_complete[0] / 2 - 0.5, oy: Math.ceil(chairY + size[chair][1]) - y, type: 'work' }],
    });
    addCentred(chair, cx, chairY);
  };
  // Sofa for one character, sitting on column cx, rest anchor on the row below it.
  const sofa = (id, cx, y, name) => {
    addCentred(id, cx, y, { anchors: [{ name, ox: size[id][0] / 2 - 0.5, oy: size[id][1], type: 'rest' }] });
  };
  const deskName = (name) => (mainAgents.includes(name) ? name : `free_${name}`);

  // --- Wall (rows 0-1): 2/3-cell pieces, left end, middles, right end ---
  const piece = size.wall_middle[0];
  add('wall_left', 0, 0);
  for (let i = 1; i < Math.round(COLS / piece) - 1; i++) add('wall_middle', i * piece, 0);
  add('wall_right', COLS - piece, 0);
  add('window_capsule_city', 0.75, 0);
  add('window_capsule_city', 3.5, 0);
  add('wall_clock', 6.25, 0.5);
  add('sign_capsule_corp', 7.5, 0, { anchors: [{ name: 'planning_board', ox: 1, oy: 2, type: 'social' }] });
  // The lead works standing in front of the blueprints (main.ts removes the seated offset).
  add('screen_blueprint', 10.5, 0, { anchors: [{ name: 'desk_lead', ox: 2, oy: 2, type: 'work' }] });
  add('screen_blueprint', 13.17, 0);
  add('window_capsule_city', 17.5, 0);
  add('window_capsule_city', 20.5, 0);
  add('window_capsule_city', 23.5, 0);
  add('sign_capsule_corp', 29.5, 0);
  add('window_capsule_city', 32.5, 0);
  add('window_capsule_city', 35.75, 0);

  // --- Desks (workstations on rows 3-5, chairs on 5-6, anchors on row 7) ---
  desk(deskName('designer'), 2, 3);
  desk(deskName('front'), 6, 3);
  desk(deskName('ai'), 10, 3);
  desk(deskName('back'), 16, 3, 'chair_blue');
  add('namek_tree', 18.5, 3);
  desk(deskName('test-runner'), 21, 3, 'chair_blue');
  desk(deskName('database'), 25, 3, 'chair_blue');

  // --- Coffee corner: counter, capsule vending, fridge, round table for a chat ---
  add('coffee_counter_complete', 0.5, 9.25, { anchors: [{ name: 'coffee_bar', ox: 0.5, oy: 3, type: 'social' }] });
  add('capsule_vending', 2.67, 10);
  add('fridge', 4.17, 10);
  add('meeting_table', 3.25, 7.25, { anchors: [{ name: 'chat_table', ox: 1, oy: 2, type: 'social' }] });
  add('water_cooler', 5.25, 10, { anchors: [{ name: 'water_cooler', ox: 0, oy: 1.8, type: 'utility' }] });
  add('namek_tree', 8.5, 9.25);
  // --- Reviewer's desk ---
  desk(deskName('reviewer'), 11, 9);

  // --- Medical bay: explorer, recovery capsule on its platform, docs-researcher ---
  desk(deskName('explorer'), 16, 9, 'chair_blue');
  // Capsule and platform enlarged in the editor, past their 2/3 size.
  add('medical_platform', 18.083, 10.5, { w: 5.033, h: 3.033 });
  add('recovery_capsule', 18.417, 8, { w: 4.467, h: 4.133 });
  desk(deskName('docs-researcher'), 24, 9, 'chair_blue');

  // --- Lounge: two rows of 5 sofas (anchors on rows 17 and 20), display on the right ---
  // Columns 16-17 stay free so both rows of sofas can be reached from the corridor.
  const LOUNGE = [
    ['front', 'designer', 'ai', 'lead', 'reviewer'],
    ['back', 'database', 'test-runner', 'explorer', 'docs-researcher'],
  ];
  LOUNGE.forEach((row, r) => row.forEach((name, i) => {
    sofa((r + i) % 2 ? 'sofa_blue' : 'sofa_orange', 1 + 3 * i, 15 + 3 * r, `rest_${name}`);
  }));
  add('namek_bonsai', 17.75, 16.5);
  add('display_seven_dragon_balls', 18.75, 15.25, { w: 3.467, h: 2.8 });
  add('namek_bonsai', 22.25, 16.5);
  addCentred('rug_four_stars', 20, 18.25);
  add('coffee_table', 24.5, 17.25);

  // --- Annex: 4 desks for repo agents (2x2), a sofa for each one below ---
  const ANNEX_CX = [30, 36];
  [3, 9].forEach((y, r) => ANNEX_CX.forEach((cx, i) => {
    const n = r * 2 + i;
    desk(annexAgents[n] ?? `annex_free_${n + 1}`, cx, y, n % 2 ? 'chair_blue' : 'chair_orange');
  }));
  add('server_cabinet', 31.75, 9.25, { w: 1.833, h: 2.167 });
  add('server_cabinet', 33.5, 9.25, { w: 1.833, h: 2.167 });
  [15, 18].forEach((y, r) => ANNEX_CX.forEach((cx, i) => {
    const n = r * 2 + i;
    sofa(n % 2 ? 'sofa_orange' : 'sofa_blue', cx, y, `rest_annex_${n + 1}`);
  }));
  add('coffee_table', 32.25, 15.5);

  const wanderPoints = [
    { name: 'corridor_north', x: 6, y: 2 },
    { name: 'corridor_west', x: 4, y: 8 },
    { name: 'corridor_centre', x: 13, y: 8 },
    { name: 'corridor_east', x: 22, y: 8 },
    { name: 'lounge', x: 17, y: 14 },
    { name: 'annex_corridor', x: 33, y: 8 },
  ];

  return { gridCols: COLS, gridRows: ROWS, floor, tiles, propImages, props, wanderPoints };
}
