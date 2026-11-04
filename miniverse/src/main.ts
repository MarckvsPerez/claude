import { Miniverse, PropSystem, Editor, createStandardSpriteConfig } from '@miniverse/core';
import type { SceneConfig, SpriteSheetConfig, CitizenDef } from '@miniverse/core';

// Team: the world is ?world=<id>, else the one scripts/build-office.mjs last built
// (public/worlds/current.json), else Capsule_corp. Set by resolveWorld() before anything loads.
let WORLD_ID = 'Capsule_corp';
let basePath = `/worlds/${WORLD_ID}`;

async function resolveWorld() {
  const built: string | undefined = await fetch('/worlds/current.json')
    .then(r => r.json())
    .then((d: { world?: string }) => d.world)
    .catch(() => undefined);
  WORLD_ID = (new URLSearchParams(location.search).get('world') ?? built ?? WORLD_ID).replace(/[^a-zA-Z0-9_-]/g, '');
  basePath = `/worlds/${WORLD_ID}`;
}

function charSprites(name: string): SpriteSheetConfig {
  return {
    sheets: {
      walk: `/universal_assets/citizens/${name}_walk.png`,
      actions: `/universal_assets/citizens/${name}_actions.png`,
    },
    animations: {
      idle_down: { sheet: 'actions', row: 3, frames: 4, speed: 0.5 },
      idle_up: { sheet: 'actions', row: 3, frames: 4, speed: 0.5 },
      walk_down: { sheet: 'walk', row: 0, frames: 4, speed: 0.15 },
      walk_up: { sheet: 'walk', row: 1, frames: 4, speed: 0.15 },
      walk_left: { sheet: 'walk', row: 2, frames: 4, speed: 0.15 },
      walk_right: { sheet: 'walk', row: 3, frames: 4, speed: 0.15 },
      working: { sheet: 'actions', row: 0, frames: 4, speed: 0.3 },
      sleeping: { sheet: 'actions', row: 1, frames: 2, speed: 0.8 },
      talking: { sheet: 'actions', row: 2, frames: 4, speed: 0.15 },
    },
    frameWidth: 64,
    frameHeight: 64,
  };
}

// Team: the engine's canvas holds one pixel per world pixel and CSS stretches it to `scale`,
// so images drawn smaller than their file (Capsule Corp's props) lose pixels and the
// enlargement blurs nothing but repeats them. This gives the canvas one pixel per screen
// pixel (world x scale x devicePixelRatio) at the same CSS size, so every image is drawn with
// all its detail. render() and resize() are the Renderer's own, plus that factor; the mouse
// is unaffected because it maps from the CSS size.
function renderAtScreenResolution(mv: Miniverse, scale: number) {
  type Layer = { render(ctx: CanvasRenderingContext2D, dt: number): void };
  type Renderer = {
    canvas: HTMLCanvasElement;
    ctx: CanvasRenderingContext2D;
    layers: Layer[];
    camera: { x: number; y: number; zoom: number; update(): void };
    render(dt: number): void;
    resize(width: number, height: number): void;
  };
  const renderer = (mv as unknown as { renderer: Renderer }).renderer;
  const density = scale * (window.devicePixelRatio || 1);
  const resize = (width: number, height: number) => {
    const { canvas, ctx } = renderer;
    canvas.width = Math.round(width * density);
    canvas.height = Math.round(height * density);
    canvas.style.width = `${width * scale}px`;
    canvas.style.height = `${height * scale}px`;
    ctx.imageSmoothingEnabled = false;
  };
  resize(renderer.canvas.width, renderer.canvas.height);
  renderer.resize = resize;
  renderer.render = (dt) => {
    const { ctx, canvas, camera } = renderer;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    camera.update();
    const z = camera.zoom * density;
    for (const layer of renderer.layers) {
      ctx.save();
      ctx.setTransform(z, 0, 0, z, -camera.x * z, -camera.y * z);
      layer.render(ctx, dt);
      ctx.restore();
    }
  };
}

function buildSceneConfig(cols: number, rows: number, floor: string[][] | undefined, tiles: Record<string, string> | undefined): SceneConfig {
  const safeFloor: string[][] = floor ?? Array.from({ length: rows }, () => Array(cols).fill(''));
  const walkable: boolean[][] = [];
  for (let r = 0; r < rows; r++) {
    walkable[r] = [];
    for (let c = 0; c < cols; c++) walkable[r][c] = (safeFloor[r]?.[c] ?? '') !== '';
  }

  const resolvedTiles: Record<string, string> = { ...(tiles ?? {}) };
  for (const [key, src] of Object.entries(resolvedTiles)) {
    if (/^(blob:|data:|https?:\/\/)/.test(src)) continue;
    const clean = src.startsWith('/') ? src.slice(1) : src;
    resolvedTiles[key] = `${basePath}/${clean}`;
  }

  return {
    name: 'main',
    tileWidth: 32,
    tileHeight: 32,
    layers: [safeFloor],
    walkable,
    locations: {},
    tiles: resolvedTiles,
  };
}

async function main() {
  const container = document.getElementById('miniverse-container')!;
  const tooltip = document.getElementById('tooltip')!;
  const statusBar = document.getElementById('status-bar')!;

  await resolveWorld();
  const sceneData = await fetch(`${basePath}/world.json`).then(r => r.json()).catch(() => null);

  // Collect work anchor names from props for citizen placement
  const workAnchors: string[] = (sceneData?.props ?? [])
    .flatMap((f: any) => (f.anchors ?? []).filter((a: any) => a.type === 'work').map((a: any) => a.name));

  const gridCols = sceneData?.gridCols ?? 16;
  const gridRows = sceneData?.gridRows ?? 12;
  const sceneConfig = buildSceneConfig(gridCols, gridRows, sceneData?.floor, sceneData?.tiles);
  const tileSize = 32;
  // Team: the largest scale (up to x2) at which the whole world fits in the window, below the
  // title and above the status bar, so a big world still fits on a laptop screen. Measured
  // once at load: the editor and the props map the mouse with this same scale.
  const RESERVED_HEIGHT = 120;
  const fitScale = Math.min(
    2,
    (window.innerWidth - 24) / (gridCols * tileSize),
    (window.innerHeight - RESERVED_HEIGHT) / (gridRows * tileSize),
  );

  // Auto-discover agents from server and available sprites
  const availableSprites: string[] = await fetch('/api/citizens').then(r => r.json()).catch(() => ['lead']);
  const serverAgents: { agent: string; name: string; state?: string }[] = await fetch('http://localhost:4321/api/agents')
    .then(r => r.json())
    .then((d: any) => d.agents ?? [])
    .catch(() => []);

  // Team: each role has a fixed desk and sprite in world.json, so the team is always
  // laid out by zone. Agents the server knows but world.json doesn't fall back to
  // the original order-based placement.
  const roleDefs: { agentId: string; name: string; sprite: string; position: string }[] =
    sceneData?.citizens ?? [];
  const knownIds = new Set(roleDefs.map(d => d.agentId));
  // Agents outside world.json only while they are online: the server keeps every agent that
  // ever sent a heartbeat (an older bridge's per-role ids, other projects), offline forever.
  const extraAgents = serverAgents.filter(a => !knownIds.has(a.agent) && a.state !== 'offline');
  const extraAnchors = workAnchors.filter(name => !roleDefs.some(d => d.position === name));

  // Team: roles that work standing (the lead plans at the whiteboard). Their
  // "working" animation is the talking gesture and they skip the seated offset.
  const STANDING_ROLES = new Set(roleDefs.map(d => d.agentId).filter(id => id.endsWith('-lead')));
  const roleSprites = (d: { agentId: string; sprite: string }) => {
    const sheet = charSprites(availableSprites.includes(d.sprite) ? d.sprite : availableSprites[0]);
    if (STANDING_ROLES.has(d.agentId)) sheet.animations.working = sheet.animations.talking;
    return sheet;
  };

  const spriteSheets: Record<string, SpriteSheetConfig> = {
    ...Object.fromEntries(roleDefs.map(d => [d.agentId, roleSprites(d)])),
    ...Object.fromEntries(extraAgents.map((a: any, i: number) =>
      [a.agent, charSprites(availableSprites[i % availableSprites.length])]
    )),
  };

  const mv = new Miniverse({
    container,
    world: WORLD_ID,
    scene: 'main',
    signal: {
      type: 'websocket',
      url: 'ws://localhost:4321/ws',
    },
    citizens: [
      ...roleDefs.map(d => ({
        agentId: d.agentId,
        name: d.name,
        sprite: d.agentId,
        position: d.position,
      })),
      ...extraAgents.map((a: any, i: number) => ({
        agentId: a.agent,
        name: a.name || a.agent,
        sprite: a.agent,
        position: extraAnchors[i] ?? sceneData?.wanderPoints?.[i]?.name ?? 'wander_' + i,
      }))
    ],
    scale: fitScale,
    width: gridCols * tileSize,
    height: gridRows * tileSize,
    sceneConfig,
    spriteSheets,
    objects: [],
  });
  renderAtScreenResolution(mv, fitScale);

  // Team: the server marks an agent "offline" after a minute without heartbeats and the
  // engine then hides it. Team roles stay in the office asleep instead.
  const roleIds = new Set(roleDefs.map(d => d.agentId));
  type SignalUpdate = { id: string; state: string };
  const engine = mv as unknown as { handleSignalUpdate(updates: SignalUpdate[]): void };
  const handleSignalUpdate = engine.handleSignalUpdate.bind(mv);
  engine.handleSignalUpdate = updates => handleSignalUpdate(
    updates.map(u => (roleIds.has(u.id) && u.state === 'offline' ? { ...u, state: 'sleeping' } : u)),
  );

  // --- Props system ---
  const props = new PropSystem(tileSize, fitScale);

  const rawSpriteMap: Record<string, string> = sceneData?.propImages ?? {};
  await Promise.all(
    Object.entries(rawSpriteMap).map(([id, src]) => {
      const clean = src.startsWith('/') ? src : '/' + src;
      return props.loadSprite(id, `${basePath}${clean}`);
    }),
  );

  props.setLayout(sceneData?.props ?? []);
  if (sceneData?.wanderPoints) {
    props.setWanderPoints(sceneData.wanderPoints);
  }

  props.setDeadspaceCheck((col, row) => {
    const floor = mv.getFloorLayer();
    return floor?.[row]?.[col] === '';
  });

  const syncProps = () => {
    mv.setTypedLocations(props.getLocations());
    mv.updateWalkability(props.getBlockedTiles());
  };
  syncProps();
  props.onSave(syncProps);

  await mv.start();

  for (const agentId of STANDING_ROLES) {
    const citizen = mv.getCitizen(agentId);
    if (!citizen) continue;
    // Standing only while working: asleep on a beanbag it still needs the seated offset.
    const seatedOffset = citizen.getSittingOffset.bind(citizen);
    citizen.getSittingOffset = () => (citizen.state === 'working' ? 0 : seatedOffset());
  }

  // Team: every character has its own sofa ("rest" in world.json). The engine sends a
  // sleeping character to any free "rest" anchor, so each one only gets to see its own;
  // characters without one see the sofas nobody owns.
  type Anchor = { name: string; type: string };
  type Citizen = { goToAnchorType(type: string, anchors: Anchor[], ...rest: unknown[]): boolean };
  const restOf = new Map(roleDefs.map(d => [d.agentId, (d as { rest?: string }).rest]));
  const ownedRests = new Set([...restOf.values()].filter(Boolean));
  for (const id of [...roleDefs.map(d => d.agentId), ...extraAgents.map(a => a.agent)]) {
    const citizen = mv.getCitizen(id) as unknown as Citizen | undefined;
    if (!citizen) continue;
    const own = restOf.get(id);
    const allowed = (a: Anchor) => a.type !== 'rest' || (own ? a.name === own : !ownedRests.has(a.name));
    const goToAnchorType = citizen.goToAnchorType.bind(citizen);
    citizen.goToAnchorType = (type, anchors, ...rest) =>
      goToAnchorType(type, type === 'rest' ? anchors.filter(allowed) : anchors, ...rest);
  }

  mv.addLayer({ order: 5, render: (ctx) => props.renderBelow(ctx) });
  mv.addLayer({ order: 15, render: (ctx) => props.renderAbove(ctx) });

  // --- Editor ---
  const editor = new Editor({
    canvas: mv.getCanvas(),
    props,
    miniverse: mv,
    worldId: WORLD_ID,
    apiBase: '',
    onSave: async (scene) => {
      const res = await fetch('/api/save-world', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...scene, worldId: WORLD_ID }),
      });
      if (!res.ok) throw new Error(await res.text());
    },
  });
  editor.loadCitizenDefs(sceneData?.citizens);
  mv.addLayer({ order: 50, render: (ctx) => {
    editor.renderOverlay(ctx);
    if (editor.isActive()) syncProps();
  } });

  // --- Tooltip ---
  mv.on('citizen:click', (data: unknown) => {
    const d = data as { name: string; state: string; task: string | null };
    tooltip.style.display = 'block';
    tooltip.querySelector('.name')!.textContent = d.name;
    tooltip.querySelector('.state')!.textContent = `State: ${d.state}`;
    tooltip.querySelector('.task')!.textContent = d.task ? `Task: ${d.task}` : 'No active task';
    setTimeout(() => { tooltip.style.display = 'none'; }, 3000);
  });

  container.addEventListener('mousemove', (e) => {
    tooltip.style.left = e.clientX + 12 + 'px';
    tooltip.style.top = e.clientY + 12 + 'px';
  });
}

main().catch(console.error);
