#!/usr/bin/env bash
# Tests for the plugin's scripts. They touch no database and no network except Miniverse
# on 127.0.0.1:4321, whose test is skipped if it isn't running.
# Usage: plugins/team/tests/run.sh

set -uo pipefail
PLUGIN="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected $2, got $3)"; fi
}

# --- Database guard ---
mkdir -p "$TMP/guard/.claude" "$TMP/guard-custom/.claude" "$TMP/guard-none"
jq -n '{roles: {database: {agent: "team:database"}}}' >"$TMP/guard/.claude/team.json"
jq -n '{roles: {database: {agent: "data-auditor"}}}' >"$TMP/guard-custom/.claude/team.json"
guard_in() { printf '%s' "$3" | jq -Rs --arg a "$2" '{agent_type: $a, tool_input: {command: .}}' | CLAUDE_PROJECT_DIR="$1" "$PLUGIN/scripts/db-readonly-guard.sh" >/dev/null 2>&1; echo $?; }
guard() { guard_in "$TMP/guard" "$@"; }
check "guard: allowed call" 0 "$(guard team:database $'db-query <<\'SQL\'\nSELECT 1\nSQL')"
check "guard: with --db" 0 "$(guard team:database $'db-query --db test_a <<\'SQL\'\nSELECT 1\nSQL')"
check "guard: direct mysql" 2 "$(guard team:database 'mysql -uroot -e "DROP TABLE x"')"
check "guard: command after the heredoc" 2 "$(guard team:database $'db-query <<\'SQL\'\nSELECT 1\nSQL\nrm -rf /\nSQL')"
check "guard: unquoted heredoc" 2 "$(guard team:database $'db-query <<SQL\nSELECT $(whoami)\nSQL')"
check "guard: chained command" 2 "$(guard team:database $'db-query <<\'SQL\' && rm x\nSELECT 1\nSQL')"
check "guard: other command" 2 "$(guard team:database 'git status')"
check "guard: other agent is not filtered" 0 "$(guard team:back 'mysql -uroot')"
check "guard: main session is not filtered" 0 "$(guard '' 'ls')"
check "guard: repo database agent from team.json" 2 "$(guard_in "$TMP/guard-custom" data-auditor 'mysql -uroot')"
check "guard: repo without team.json is left alone" 0 "$(guard_in "$TMP/guard-none" database '.claude/bin/db-query.sh <<x')"

# --- db-query SQL validation (fails before connecting) ---
mkdir -p "$TMP/db/.claude" "$TMP/db/env"
printf 'DB_NAME=fake\nDB_RO_USER=ro\nDB_RO_PASSWORD="x"\n' >"$TMP/db/env/.env.local"
jq -n '{database: {engine: "mysql", host: "127.0.0.1", port: 3999, composeProject: "team-test-missing", service: "db", envFile: "env/.env.local", nameVar: "DB_NAME", userVar: "DB_RO_USER", passwordVar: "DB_RO_PASSWORD"}}' >"$TMP/db/.claude/team.json"
query() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMP/db" "$PLUGIN/bin/db-query" 2>&1; }
expect_msg() { if grep -q "$3" <<<"$(query "$2")"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1 → $(query "$2")"; fi; }
expect_msg "db-query: DELETE" "DELETE FROM orders" "only SELECT"
expect_msg "db-query: two statements" "SELECT 1; DROP TABLE a" "one statement"
expect_msg "db-query: executable comment" "SELECT 1 /*! DROP */" "comments"
expect_msg "db-query: FOR UPDATE" "SELECT * FROM a FOR UPDATE" "forbidden word"
expect_msg "db-query: OUTFILE" "SELECT * INTO OUTFILE '/tmp/x' FROM a" "forbidden word"
expect_msg "db-query: valid read reaches the local-database check" "SELECT status, COUNT(*) FROM orders GROUP BY status" "doesn't publish"
jq '.database.host = "10.0.0.5"' "$TMP/db/.claude/team.json" >"$TMP/t.json" && mv "$TMP/t.json" "$TMP/db/.claude/team.json"
expect_msg "db-query: remote host" "SELECT 1" "is not local"

# --- Quality gate ---
R="$TMP/gate"
mkdir -p "$R/.claude" "$R/web" "$R/api" "$R/docs"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
jq -n '{gate: {ignore: ["*.md", "docs/*", ".claude/*"], checks: [
  {name: "web", when: ["web/*"], run: "echo WEB-FAILURE; exit 1"},
  {name: "api", when: ["api/*"], run: "echo api-ok"}]}}' >"$R/.claude/team.json"
echo a >"$R/web/x.ts"; echo b >"$R/api/y.ts"; echo c >"$R/docs/a.md"
git -C "$R" add -A && git -C "$R" commit -qm init
gate() { echo '{"task_subject":"T1"}' | CLAUDE_PROJECT_DIR="$1" "$PLUGIN/scripts/quality-gate.sh" >/dev/null 2>&1; echo $?; }
echo x >>"$R/docs/a.md"
check "gate: docs only" 0 "$(gate "$R")"
echo y >>"$R/api/y.ts"
check "gate: passing check" 0 "$(gate "$R")"
echo z >>"$R/web/x.ts"
check "gate: failing check" 2 "$(gate "$R")"
# {files}: only the changed files that match the check's `when`, quoted, existing ones only;
# with `cwd`, the check runs there and the paths are relative to it.
F="$TMP/gate-files"
mkdir -p "$F/.claude" "$F/web/src" "$F/api"
git -C "$F" init -q && git -C "$F" config user.email t@t && git -C "$F" config user.name t
jq -n --arg out "$TMP/files.out" --arg cwdout "$TMP/cwd.out" '{gate: {checks: [
  {name: "lint", when: ["web/*"], run: ("printf \"[%s]\\n\" {files} > " + $out)},
  {name: "scoped", when: ["web/*"], cwd: "web", run: ("{ pwd -P; printf \"[%s]\\n\" {files}; } > " + $cwdout)}]}}' >"$F/.claude/team.json"
echo a >"$F/web/src/a.ts"; echo b >"$F/web/src/gone.ts"; echo c >"$F/api/c.ts"
git -C "$F" add -A && git -C "$F" commit -qm init
echo x >>"$F/web/src/a.ts"; echo y >"$F/web/src/new file.ts"; echo z >>"$F/api/c.ts"; rm "$F/web/src/gone.ts"
check "gate {files}: passes" 0 "$(gate "$F")"
check "gate {files}: only matching existing files, quoted" "$(printf '[web/src/a.ts]\n[web/src/new file.ts]')" "$(cat "$TMP/files.out" 2>/dev/null)"
check "gate cwd: runs in cwd with relative paths" "$(printf '%s\n[src/a.ts]\n[src/new file.ts]' "$(cd "$F/web" && pwd -P)")" "$(cat "$TMP/cwd.out" 2>/dev/null)"

# team-gate: the same checks on demand, outside a task (size S path of team:lead)
team_gate() { (cd "$1" && env -u CLAUDE_PROJECT_DIR "$PLUGIN/bin/team-gate" "palette" >"$TMP/tg.out" 2>&1); echo $?; }
check "team-gate: passing checks" 0 "$(team_gate "$F")"
check "team-gate: failing check" 2 "$(team_gate "$R")"
if grep -q "Can't close 'palette'" "$TMP/tg.out"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: team-gate: reports the failure → $(cat "$TMP/tg.out")"; fi

mkdir -p "$TMP/no-config"
check "gate: project without team.json" 0 "$(gate "$TMP/no-config")"
check "gate: releases the lock" 0 "$(ls "${TMPDIR:-/tmp}"/team-gate-*.lock 2>/dev/null | wc -l | tr -d ' ')"

# --- Miniverse bridge (only if the server is running) ---
if curl -s -m 1 -o /dev/null http://127.0.0.1:4321/api/agents; then
  mkdir -p "$TMP/mv/.claude"
  # Repo agents: motion, r2, r3 and r4 take the annex's 4 desks (alphabetical); r5 is left over.
  mkdir -p "$TMP/mv/.claude/agents"
  for n in motion r2 r3 r4 r5; do printf -- '---\nname: %s\n---\n' "$n" >"$TMP/mv/.claude/agents/$n.md"; done
  jq -n '{project: "team-test", roles: {"front-admin": {agent: "team:front"}, motion: {agent: "motion"}}, miniverse: {url: "http://127.0.0.1:4321"}}' >"$TMP/mv/.claude/team.json"
  bridge() { echo "$1" | CLAUDE_PROJECT_DIR="$TMP/mv" "$PLUGIN/scripts/miniverse-bridge.sh"; }
  state_of() { jq -r --arg a "$1" '.agents[] | select(.agent == $a) | "\(.state)|\(.task)"' <<<"$AGENTS"; }
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Read","agent_type":"team:front","tool_input":{"file_path":"/a/b/App.tsx"}}'
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Grep","agent_type":"team:explorer"}'
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_type":"motion","tool_input":{"file_path":"/a/Scene.tsx"}}'
  bridge '{"hook_event_name":"UserPromptSubmit","prompt":"secret-text"}'
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Glob","agent_type":"general-purpose"}'
  AGENTS="$(curl -s http://127.0.0.1:4321/api/agents)"
  check "bridge: plugin agent under its own name" "working|Read · App.tsx" "$(state_of team-test-front)"
  check "bridge: role name gets no character of its own" "" "$(state_of team-test-front-admin)"
  check "bridge: plugin worker under its own name" "working|Grep" "$(state_of team-test-explorer)"
  check "bridge: repo agent with an annex desk" "working|Edit · Scene.tsx" "$(state_of team-test-motion)"
  check "bridge: built-in agent shows as the lead's work" "working|general-purpose · Glob" "$(state_of team-test-lead)"
  check "bridge: built-in agent gets no character" "" "$(state_of team-test-general-purpose)"
  check "bridge: doesn't send the prompt" 0 "$(grep -c secret-text <<<"$AGENTS")"
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Read","agent_type":"r5","tool_input":{"file_path":"/a/terms.md"}}'
  bridge '{"hook_event_name":"PreToolUse","tool_name":"Edit","teammate_name":"front-admin","tool_input":{"file_path":"/a/Admin.tsx"}}'
  AGENTS="$(curl -s http://127.0.0.1:4321/api/agents)"
  check "bridge: repo agent past the annex desks shows as the lead's work" "working|r5 · Read · terms.md" "$(state_of team-test-lead)"
  check "bridge: repo agent past the annex desks gets no character" "" "$(state_of team-test-r5)"
  check "bridge: teammate works as its profile, labelled with its role" "working|front-admin · Edit · Admin.tsx" "$(state_of team-test-front)"
  for a in team-test-front team-test-motion team-test-explorer team-test-lead; do
    curl -s -o /dev/null -X POST http://127.0.0.1:4321/api/agents/remove -H 'Content-Type: application/json' -d "{\"agent\":\"$a\"}"
  done
else
  echo "(Miniverse bridge: server not running, test skipped)"
fi

echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
