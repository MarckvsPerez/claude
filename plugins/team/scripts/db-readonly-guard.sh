#!/usr/bin/env bash
# PreToolUse (Bash): the only shell command the database agent can run is
#   db-query [--db name] <<'SQL'
#   ...
#   SQL
# So it can't open another database client, use write credentials or chain commands.
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

COMMAND="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"

deny() {
  {
    echo "Command blocked for the database agent: $1"
    echo "Use only:"
    echo "db-query [--db name] <<'SQL'"
    echo "SELECT ..."
    echo "SQL"
  } >&2
  exit 2
}

FIRST_LINE="$(head -n 1 <<<"$COMMAND")"
LAST_LINE="$(tail -n 1 <<<"$COMMAND")"
LINES="$(wc -l <<<"$COMMAND" | tr -d ' ')"

[[ "$FIRST_LINE" =~ ^db-query(\ --db\ [A-Za-z0-9_]+)?\ \<\<\'SQL\'$ ]] || deny "the command doesn't start with the allowed call"
[[ "$LAST_LINE" == "SQL" ]] || deny "the heredoc must end with a SQL line"
(( LINES >= 3 )) || deny "the query is missing"
# The delimiter can't appear before the end: another command could follow it.
(( $(grep -cx 'SQL' <<<"$COMMAND") == 1 )) || deny "the SQL delimiter appears more than once"

exit 0
