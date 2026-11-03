// Builds the zoned office from Cozy Startup's original world.json for one project's team.
// Usage:
//   node scripts/build-office.mjs --team path/to/.claude/team.json
// (rewrites public/worlds/cozy-startup/world.json)
//
// Character ids are "<project>-<role>", the same ones the team plugin's bridge sends. The
// lead stands at the whiteboard, reviewer takes the centre desk and the other roles take the
// 6 desks in team.json order. The team plugin's workers (explorer, test-runner,
// docs-researcher) take the desks left over.
//
// 20x16 grid. Rows 0-1: wall, fully covered by props so nobody walks on it.
//   Top left:     two desks by the windows.
//   Top centre:   lead standing at the big whiteboard; reviewer at the centre desk.
//   Right:        back office on a concrete floor (three desks).
//   Bottom:       coffee bar and chat corner (social), library desk.
//   Bottom strip: rest area with one beanbag per character. A character going "sleeping"
//                 walks to a free "rest" anchor; with none left the engine leaves it asleep
//                 in its chair.
// A desk is 3x2 cells with the chair below. The "work" anchor sits one cell below the chair:
// the engine draws a working character 1.2 cells above its anchor, so it ends up in the chair.

import { readFileSync, writeFileSync } from 'node:fs';

const dir = new URL('../public/worlds/cozy-startup/', import.meta.url);
const original = JSON.parse(readFileSync(new URL('world.original.json', dir), 'utf8'));

// The 4 bundled characters plus their colour variants (scripts/recolor-citizens.mjs): 8 looks
// for up to 8 characters (lead, reviewer and 6 desks) without repeats.
const SPRITES = ['nova', 'dexter', 'rio', 'morty', 'morty-blue', 'dexter-green', 'rio-teal', 'nova-khaki'];
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9-]+/g, '-');
const label = (role) => role.charAt(0).toUpperCase() + role.slice(1).replace(/-/g, ' ');

const teamArg = process.argv.indexOf('--team');
const teamPath = teamArg === -1 ? undefined : process.argv[teamArg + 1];
if (!teamPath) {
  console.error('Usage: node scripts/build-office.mjs --team path/to/.claude/team.json');
  process.exit(1);
}
const team = JSON.parse(readFileSync(teamPath, 'utf8'));
const roles = Object.keys(team.roles ?? {}).map(slug);
const others = roles.filter((r) => r !== 'reviewer' && r !== 'lead');
if (others.length > 6) {
  console.error(`The office has 6 desks and team.json has ${others.length} roles besides lead and reviewer.`);
  process.exit(1);
}
// Fixed look per known role, in pairs that work together: each pair shares a character in two
// outfits. Roles not listed here (a repo specialist such as legal) get the looks nobody else
// uses, in order, and only repeat past 8 characters.
const ROLE_SPRITES = {
  lead: 'dexter',
  reviewer: 'dexter-green',
  front: 'morty',
  back: 'morty-blue',
  designer: 'nova',
  'docs-researcher': 'nova-khaki',
  explorer: 'rio',
  'test-runner': 'rio-teal',
};
const spriteFor = (() => {
  const taken = new Set();
  return (role, everyone) => {
    if (taken.size === 0) everyone.forEach((r) => ROLE_SPRITES[r] && taken.add(ROLE_SPRITES[r]));
    if (ROLE_SPRITES[role]) return ROLE_SPRITES[role];
    const free = SPRITES.find((s) => !taken.has(s)) ?? SPRITES[taken.size % SPRITES.length];
    taken.add(free);
    return free;
  };
})();
// The team plugin's shared workers are fixed characters too: they take the desks the roles
// leave free and rest like everyone else. A worker without a free desk is left out and the
// engine places it on the fly if it ever shows up.
const WORKERS = ['explorer', 'test-runner', 'docs-researcher'];
const deskRoles = [...others, ...WORKERS.filter((w) => !others.includes(w))].slice(0, 6);
const everyone = ['lead', ...(roles.includes('reviewer') ? ['reviewer'] : []), ...deskRoles];
const roster = {
  project: slug(team.project ?? teamPath.split('/').at(-3)),
  lead: 'lead',
  reviewer: roles.includes('reviewer') ? 'reviewer' : null,
  desks: deskRoles,
  sprites: Object.fromEntries(everyone.map((r) => [r, spriteFor(r, everyone)])),
};

const COLS = 20;
const ROWS = 16;

const floor = Array.from({ length: ROWS }, (_, r) =>
  Array.from({ length: COLS }, (_, c) => {
    if (r < 2) return 'exposed_brick_wall';
    const backOffice = (c >= 12 && c <= 18 && r <= 7) || (c >= 12 && c <= 14 && r >= 8 && r <= 11);
    return backOffice ? 'concrete_accent' : 'main_floor';
  }),
);

const propImages = {
  ...original.propImages,
  desk_wood_modern: 'world_assets/props/prop_0_desk_wood_modern.png',
  whiteboard_large: 'world_assets/props/prop_8_whiteboard_large.png',
  bookshelf_full: 'world_assets/props/prop_8_bookshelf_full.png',
  potted_plant_small: 'world_assets/props/prop_3_potted_plant_small.png',
  bean_bag_chair_grey: 'world_assets/props/prop_6_bean_bag_chair_grey.png',
  beanbag_orange: 'world_assets/props/prop_6_beanbag_orange.png',
};

const props = [];
const add = (id, x, y, w, h, extra = {}) => props.push({ id, x, y, w, h, layer: 'below', ...extra });

// Desk with chair. The chair goes in the second whole column the desk touches, and the work
// anchor one cell below the chair (see the note at the top).
const desk = (role, x, y, { id = 'wooden_desk_single', w = 3 } = {}) => {
  const chairX = Math.floor(x) + 1;
  add(id, x, y, w, 2, { anchors: [{ name: `desk_${role}`, ox: chairX - x, oy: 3, type: 'work' }] });
  add('ergonomic_chair', chairX, y + 2, 1, 1, { layer: 'above' });
};

// --- Wall (y = 0): covers columns 1-18 ---
add('large_window', 1, 0, 3, 2);
add('large_window', 4, 0, 3, 2);
// The lead works standing at the whiteboard (main.ts removes the seated offset), so its
// anchor sits on the first floor row, right against the board.
add('whiteboard_large', 7, 0, 3, 2, { anchors: [{ name: `desk_${roster.lead}`, ox: 1, oy: 2, type: 'work' }] });
add('wooden_framed_whiteboard', 10, 0.5, 2, 1.5, { anchors: [{ name: 'planning_board', ox: 1, oy: 1.5, type: 'social' }] });
add('large_window', 12, 0, 3, 2);
add('large_window', 15, 0, 3, 2);
add('tall_potted_plant', 18, 0, 1, 2);

// The 6 desks, in the order roles are assigned: by the windows (2), back office (2), lower
// back office and library. A desk without a role stays free (desk_free_N).
const SLOTS = [
  { x: 1, y: 3 },
  { x: 4, y: 3 },
  { x: 12, y: 3 },
  { x: 16, y: 3 },
  { x: 12, y: 8 },
  { x: 8.25, y: 8, w: 2.7 },
];
const slotRole = (i) => roster.desks[i] ?? `free_${i + 1}`;

desk(slotRole(0), SLOTS[0].x, SLOTS[0].y);
desk(slotRole(1), SLOTS[1].x, SLOTS[1].y);

// --- Reviewer, in the centre ---
desk(roster.reviewer ?? 'free_centre', 8.25, 3, { w: 2.7 });

// --- Back office ---
desk(slotRole(2), SLOTS[2].x, SLOTS[2].y);
add('tall_potted_plant', 15, 2.75, 1, 2);
desk(slotRole(3), SLOTS[3].x, SLOTS[3].y);
desk(slotRole(4), SLOTS[4].x, SLOTS[4].y);

// --- Coffee bar (bottom left) ---
add('coffee_bar_counter', 1, 8, 2.5, 2.3, { anchors: [{ name: 'coffee_bar', ox: 1, oy: 2.5, type: 'social' }] });
add('espresso_machine', 1.4, 8.2, 1.1, 0.8);
add('mini_fridge', 3.75, 8.5, 0.8, 1.1);

// --- Library ---
add('bookshelf_full', 5.5, 7.75, 2.7, 3);
desk(slotRole(5), SLOTS[5].x, SLOTS[5].y, { w: SLOTS[5].w });

// --- Chat corner (bottom right) ---
add('low_coffee_table', 15.8, 8.6, 1.5, 1.5, { anchors: [{ name: 'chat_table', ox: 0.75, oy: 1.9, type: 'social' }] });
add('tall_potted_plant', 18, 8, 1, 2);

// --- Rest area: bottom strip with 8 beanbags, one per character ---
// Beanbags sit on rows 12-13 and their "rest" anchor on row 14, which stays free as a
// corridor. As with desks, the engine draws a sleeping character 1.2 cells higher.
const BEANBAGS = ['bean_bag_chair_dark', 'beanbag_orange', 'bean_bag_chair_light', 'bean_bag_chair_grey'];
[1.2, 5.2, 10.2, 14.2].forEach((x) => add('area_rug_lounge', x, 12, 3.8, 2));
[2, 4, 6, 8, 11, 13, 15, 17].forEach((ax, i) => {
  add(BEANBAGS[i % BEANBAGS.length], ax - 0.6, 12.3, 1.3, 1.3, {
    anchors: [{ name: `rest_${i + 1}`, ox: 0.6, oy: 1.7, type: 'rest' }],
  });
});

const wanderPoints = [
  { name: 'corridor_west', x: 4, y: 7 },
  { name: 'corridor_centre', x: 10, y: 7 },
  { name: 'corridor_east', x: 15, y: 7 },
  { name: 'corridor_south', x: 10, y: 11 },
];

// Fixed desk and look per role: the same character always at the same desk.
const citizens = [roster.lead, ...(roster.reviewer ? [roster.reviewer] : []), ...roster.desks].map((role) => ({
  agentId: `${roster.project}-${role}`,
  name: label(role),
  sprite: roster.sprites[role] ?? SPRITES[0],
  position: `desk_${role}`,
  type: 'agent',
}));

const world = {
  ...original,
  gridCols: COLS,
  gridRows: ROWS,
  floor,
  propImages,
  props,
  wanderPoints,
  citizens,
};

writeFileSync(new URL('world.json', dir), JSON.stringify(world, null, 2) + '\n');
console.log(`world.json: ${roster.project}, ${COLS}x${ROWS}, ${props.length} props, ${citizens.length} characters`);
