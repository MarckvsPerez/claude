// Builds the zoned office for one project's team, in one of the worlds in scripts/worlds/.
// Usage:
//   node scripts/build-office.mjs --team path/to/.claude/team.json [--plugin-agents dir] [--world id]
// The world is --world, else team.json's "miniverse.world", else Capsule_corp. It rewrites
// public/worlds/<world>/world.json and public/worlds/current.json, which tells the app (main.ts)
// which world to open.
//
// The office doesn't follow team.json's role names: it shows WHO works.
//   Main office: the team plugin's own agents (plugins/team/agents/*.md: front, back,
//                database…), by their own names and with fixed desks and looks, the same in
//                every repo. Two repo roles run by the same profile (front-cliente and
//                front-admin, both team:front) are one character, "Front".
//   Annex:       the repo's own agents (the .claude/agents/*.md next to team.json, e.g.
//                pagos and legal), all with the same look (repo-agent). It has 4 desks;
//                agents past the fourth, alphabetically, get no character and the bridge
//                shows their work as the lead's.
// Character ids are "<project>-<agent name>", the same ones the team plugin's bridge sends.
//
// Each world module (scripts/worlds/<id>.mjs) exports layout({ mainAgents, annexAgents }) and
// returns the world.json fields (grid, floor, tiles, propImages, props, wanderPoints) with
// these anchors, which is all this script relies on:
//   desk_<agent>   "work" anchor of each main agent's desk (desk_lead for the lead)
//   rest_<agent>   "rest" anchor of each main character's own sofa
//   desk_<annex agent>, rest_annex_1..4   the annex's desks and sofas

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9-]+/g, '-');
const label = (name) => name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, ' ');
const arg = (flag) => {
  const i = process.argv.indexOf(flag);
  return i === -1 ? undefined : process.argv[i + 1];
};

const teamPath = arg('--team');
if (!teamPath) {
  console.error('Usage: node scripts/build-office.mjs --team path/to/.claude/team.json [--plugin-agents dir] [--world id]');
  process.exit(1);
}
const team = JSON.parse(readFileSync(teamPath, 'utf8'));

const here = dirname(fileURLToPath(import.meta.url));
const worldsDir = resolve(here, '../public/worlds');
const worldId = (arg('--world') ?? team.miniverse?.world ?? 'Capsule_corp').replace(/[^a-zA-Z0-9_-]/g, '');
const layoutModule = join(here, 'worlds', `${worldId}.mjs`);
if (!existsSync(layoutModule)) {
  const known = readdirSync(join(here, 'worlds')).filter((f) => f.endsWith('.mjs')).map((f) => f.replace(/\.mjs$/, ''));
  console.error(`Unknown world "${worldId}". Known worlds: ${known.join(', ')}`);
  process.exit(1);
}
const { layout } = await import(layoutModule);

// An agent's name: the "name:" of its frontmatter, or the file name without ".md".
const agentNames = (agentsDir) => {
  if (!agentsDir || !existsSync(agentsDir)) return [];
  return readdirSync(agentsDir)
    .filter((f) => f.endsWith('.md'))
    .sort()
    .map((f) => {
      const text = readFileSync(join(agentsDir, f), 'utf8');
      const name = /^---\n[\s\S]*?^name:\s*["']?([^"'\n]+)["']?\s*$/m.exec(text)?.[1];
      return slug((name ?? f.replace(/\.md$/, '')).trim());
    });
};

// --- Main office: the team plugin's agents ---
const pluginAgentsDir = arg('--plugin-agents') ?? resolve(here, '../../plugins/team/agents');
const FALLBACK_AGENTS = ['ai', 'back', 'database', 'designer', 'docs-researcher', 'explorer', 'front', 'reviewer', 'test-runner'];
const pluginAgents = agentNames(pluginAgentsDir);
const mainAgents = pluginAgents.length > 0 ? pluginAgents : FALLBACK_AGENTS;

// Each character's look is <name>_walk.png and <name>_actions.png in universal_assets/citizens,
// named after its agent (front_walk.png…): replace those files to change a look. A character
// without its own files borrows the lead's.
const citizensDir = resolve(here, '../public/universal_assets/citizens');
const spriteFor = (name) => (existsSync(join(citizensDir, `${name}_walk.png`)) ? name : 'lead');

// --- Annex: the repo's own agents ---
const ANNEX_DESKS = 4; // the bridge's REPO_DESKS
const repoAgents = agentNames(join(dirname(resolve(teamPath)), 'agents')).filter((a) => !mainAgents.includes(a) && a !== 'lead');
const annexAgents = repoAgents.slice(0, ANNEX_DESKS);
if (repoAgents.length > ANNEX_DESKS) {
  console.warn(`The annex has ${ANNEX_DESKS} desks: ${repoAgents.slice(ANNEX_DESKS).join(', ')} will show up as the lead's work.`);
}
// One look shared by every repo agent.
const REPO_SPRITE = 'repo-agent';

const project = slug(team.project ?? teamPath.split('/').at(-3));

const world = layout({ mainAgents, annexAgents });

// Fixed desk, sofa and look per agent: the same character always in the same places.
const anchors = new Set(world.props.flatMap((p) => (p.anchors ?? []).map((a) => a.name)));
const deskless = mainAgents.filter((a) => !anchors.has(`desk_${a}`));
if (deskless.length > 0) console.warn(`No desk for ${deskless.join(', ')} in ${worldId}: add one to its layout.`);
const rest = (name) => (anchors.has(`rest_${name}`) ? `rest_${name}` : undefined);
const citizens = ['lead', ...mainAgents.filter((a) => anchors.has(`desk_${a}`))].map((name) => ({
  agentId: `${project}-${name}`,
  name: label(name),
  sprite: spriteFor(name),
  position: `desk_${name}`,
  rest: rest(name),
  type: 'agent',
}));
// Repo agents in the annex: same look for all of them, each on its own annex sofa.
annexAgents.forEach((name, i) => citizens.push({
  agentId: `${project}-${name}`,
  name: label(name),
  sprite: REPO_SPRITE,
  position: `desk_${name}`,
  rest: `rest_annex_${i + 1}`,
  type: 'agent',
}));

writeFileSync(join(worldsDir, worldId, 'world.json'), JSON.stringify({ ...world, citizens }, null, 2) + '\n');
writeFileSync(join(worldsDir, 'current.json'), JSON.stringify({ world: worldId }) + '\n');
console.log(`${worldId}/world.json: ${project}, ${world.gridCols}x${world.gridRows}, ${world.props.length} props, ${citizens.length} characters (${annexAgents.length} in the annex)`);
