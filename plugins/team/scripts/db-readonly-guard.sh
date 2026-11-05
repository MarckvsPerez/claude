#!/usr/bin/env bash
# PreToolUse (Bash, Read, Grep) for the database agent:
# - Bash: the only shell command it can run is
#     db-query [--env name] [--db name] <<'SQL'
#     ...
#     SQL
#   So it can't open another database client, use write credentials or chain commands.
# - Read and Grep: it uses the credentials through db-query but never sees them. It can't read
#   any .claude/db.<env>.env, the legacy database.envFile or any .env* file, and it can't Grep a
#   folder that holds one (Grep prints matching lines). Glob only returns names: it is free.
# It is a plugin hook because plugin agents ignore the hooks in their frontmatter.
#
# It only acts in projects with .claude/team.json, and only on the agent that covers the
# database role in that file (plus team:database). A repo's own "database" agent in a repo
# without team.json, with its own guard, is left alone.

set -uo pipefail

INPUT="$(cat)"
ROOT="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}"
CONFIG="$ROOT/.claude/team.json"
[[ -f "$CONFIG" ]] || exit 0

AGENT_TYPE="$(jq -r '.agent_type // empty' <<<"$INPUT")"
[[ -n "$AGENT_TYPE" ]] || exit 0
GUARDED="$(jq -r '["team:database", (.roles.database.agent // empty)] | unique | .[]' "$CONFIG" 2>/dev/null)"
grep -qxF -- "$AGENT_TYPE" <<<"$GUARDED" || exit 0

TOOL="$(jq -r '.tool_name // "Bash"' <<<"$INPUT")"

deny_secret() {
  echo "Blocked for the database agent: $1. Credentials are used through db-query, never read." >&2
  exit 2
}

# Absolute path with symlinks and .. resolved, even if the file doesn't exist.
resolve() {
  local p="$1" cwd
  cwd="$(jq -r '.cwd // empty' <<<"$INPUT")"; cwd="${cwd:-$ROOT}"
  [[ "$p" == /* ]] || p="$cwd/$p"
  if [[ -e "$p" ]]; then realpath "$p" 2>/dev/null && return; fi
  local dir; dir="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s' "$p"; return; }
  printf '%s/%s' "$dir" "$(basename "$p")"
}

# Secret files: the credentials of every environment, the legacy envFile and any .env*.
SECRETS=()
shopt -s nullglob
for f in "$ROOT"/.claude/db.*.env "$ROOT/$(jq -r '.database.envFile // empty' "$CONFIG")"; do
  [[ "$f" == "$ROOT/" ]] || SECRETS+=("$(resolve "$f")")
done
is_secret() {
  local name; name="$(basename "$1")"
  [[ "$name" == .env* || "$name" == *.local.env || ( "$name" == db.*.env && "$(basename "$(dirname "$1")")" == .claude ) ]] && return 0
  local s; for s in "${SECRETS[@]}"; do [[ "$1" == "$s" ]] && return 0; done
  return 1
}

case "$TOOL" in
  Read)
    TARGET="$(resolve "$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")")"
    is_secret "$TARGET" && deny_secret "reading $(basename "$TARGET")"
    exit 0 ;;
  Grep)
    TARGET="$(jq -r '.tool_input.path // empty' <<<"$INPUT")"
    TARGET="$(resolve "${TARGET:-.}")"
    is_secret "$TARGET" && deny_secret "searching inside $(basename "$TARGET")"
    for s in "${SECRETS[@]}"; do
      [[ "$s" == "$TARGET"/* ]] && deny_secret "Grep over $TARGET, which holds $(basename "$s"); search a narrower folder such as the migrations"
    done
    if [[ -d "$TARGET" ]] && [[ -n "$(find "$TARGET" -maxdepth 4 \( -name node_modules -o -name .git \) -prune -o \( -name '.env*' -o -name '*.local.env' -o -path '*/.claude/db.*.env' \) -print -quit 2>/dev/null)" ]]; then
      deny_secret "Grep over $TARGET, which holds .env files; search a narrower folder such as the migrations"
    fi
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

COMMAND="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"

deny() {
  {
    echo "Command blocked for the database agent: $1"
    echo "Use only:"
    echo "db-query [--env name] [--db name] <<'SQL'"
    echo "SELECT ..."
    echo "SQL"
  } >&2
  exit 2
}

FIRST_LINE="$(head -n 1 <<<"$COMMAND")"
LAST_LINE="$(tail -n 1 <<<"$COMMAND")"
LINES="$(wc -l <<<"$COMMAND" | tr -d ' ')"

[[ "$FIRST_LINE" =~ ^db-query(\ --env\ [a-z][a-z0-9_-]*)?(\ --db\ [A-Za-z0-9_]+)?\ \<\<\'SQL\'$ ]] || deny "the command doesn't start with the allowed call"
[[ "$LAST_LINE" == "SQL" ]] || deny "the heredoc must end with a SQL line"
(( LINES >= 3 )) || deny "the query is missing"
# The delimiter can't appear before the end: another command could follow it.
(( $(grep -cx 'SQL' <<<"$COMMAND") == 1 )) || deny "the SQL delimiter appears more than once"

exit 0
