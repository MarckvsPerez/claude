#!/usr/bin/env bash
# Bridge between Claude Code hooks and Miniverse: one character per AGENT that works, with id
# "<project>-<agent name>", the same office in every repo (miniverse/scripts/build-office.mjs):
#   - Main office: this plugin's agents (agents/*.md: front, back, database…), by their own
#     names. Two team.json roles run by the same profile (front-cliente and front-admin, both
#     team:front) are the same character, "Front".
#   - Annex: the repo's own agents (.claude/agents/*.md), the first REPO_DESKS alphabetically.
#   - Anything else (agents past the annex desks, Claude Code built-ins such as
#     general-purpose, Explore or Plan, other plugins' agents) shows up as the lead's work,
#     labelled with its name. Otherwise every ad-hoc type would add a character that
#     SessionEnd never puts offline.
# Only active if .claude/team.json has "miniverse".
#
# Runs as an async hook: it never blocks, prints nothing and always exits 0.
# It only sends agent, state, tool and file name: never prompts, commands or content.
# The Miniverse server listens on every network interface.

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$ROOT/.claude/team.json"
[[ -f "$CONFIG" ]] || exit 0
URL="$(jq -r '.miniverse.url // empty' "$CONFIG" 2>/dev/null)"
[[ -n "$URL" ]] || exit 0

PROJECT="$(jq -r '.project // empty' "$CONFIG" 2>/dev/null)"
[[ -n "$PROJECT" ]] || PROJECT="$(basename "$ROOT")"
PROJECT="$(tr '[:upper:]' '[:lower:]' <<<"$PROJECT" | tr -c 'a-z0-9-\n' '-')"
slug() { tr '[:upper:]' '[:lower:]' <<<"$1" | tr -c 'a-z0-9-\n' '-'; }
# Agent names in a folder of agent files, alphabetically: the "name:" of each frontmatter, or
# the file name without ".md".
agent_names() {
  local f name
  for f in "$1"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } /^name:/ { sub(/^name:[ \t]*/, ""); gsub(/["\047]/, ""); print; exit }' "$f")"
    [[ -n "$name" ]] || name="$(basename "$f" .md)"
    slug "$name"
  done
}
REPO_DESKS=4
MAIN_AGENTS=" $(agent_names "$(dirname "$0")/../agents" | tr '\n' ' ')"
REPO_LIST=()
while read -r name; do
  [[ -n "$name" && "$name" != "lead" && "$MAIN_AGENTS" != *" $name "* ]] && REPO_LIST+=("$name")
done < <(agent_names "$ROOT/.claude/agents")
REPO_SEATED=" ${REPO_LIST[*]:0:$REPO_DESKS} "
# Characters registered at session start, so they are on screen (asleep) before they work.
ROLES="lead$MAIN_AGENTS$REPO_SEATED"

INPUT="$(cat)"
field() { jq -r "$1 // empty" <<<"$INPUT" 2>/dev/null; }

role_name() {
  local first rest
  first="$(cut -c1 <<<"$1" | tr '[:lower:]' '[:upper:]')"
  rest="$(cut -c2- <<<"$1" | tr '-' ' ')"
  echo "$first$rest"
}

beat() {
  local role="$1" state="$2" task="${3:-}" payload
  payload="$(jq -nc --arg agent "$PROJECT-$role" --arg name "$(role_name "$role")" \
    --arg state "$state" --arg task "$task" \
    '{agent: $agent, name: $name, state: $state} + (if $task == "" then {task: null} else {task: $task} end)')"
  curl -s -m 2 -o /dev/null -X POST "$URL/api/heartbeat" \
    -H 'Content-Type: application/json' -d "$payload" 2>/dev/null
}

EVENT="$(field .hook_event_name)"
TOOL="$(field .tool_name)"

# Who works: the event's agent type, or else its teammate name; nothing for the main session,
# which is the lead. In a teammate's own events agent_type is the TEAMMATE's name, i.e. its
# team.json role ("front-admin"), not its profile ("team:front"). So a name that is a role
# key resolves through that role's "agent"; any other name is an agent itself
# ("team:front" → "front", "pagos" → "pagos"). A role whose name differs from its agent
# ("front-admin" running team:front) labels its tasks with the role.
NAME="$(field .agent_type)"
[[ -n "$NAME" ]] || NAME="$(field .teammate_name)"
WHO=""
ROLE_LABEL=""
if [[ -n "$NAME" ]]; then
  WHO="$(jq -r --arg r "$NAME" '.roles[$r].agent // empty' "$CONFIG" 2>/dev/null)"
  if [[ -n "$WHO" ]]; then
    WHO="${WHO#team:}"
    [[ "$(slug "$WHO")" == "$(slug "$NAME")" ]] || ROLE_LABEL="$NAME"
  else
    WHO="${NAME#team:}"
  fi
fi
WHO="$(slug "$WHO")"
ROLE="lead"
FOREIGN=""
if [[ -n "$WHO" ]]; then
  if [[ "$MAIN_AGENTS$REPO_SEATED" == *" $WHO "* ]]; then ROLE="$WHO"; else FOREIGN="$WHO"; fi
fi
LABEL="${FOREIGN:-$ROLE_LABEL}"
PREFIX="${LABEL:+$LABEL · }"

tool_label() {
  local file
  file="$(field '.tool_input.file_path')"
  if [[ -n "$file" ]]; then echo "$PREFIX$TOOL · ${file##*/}"; else echo "$PREFIX$TOOL"; fi
}

# A teammate's own session starting or ending only touches its character; only the lead's
# session (no agent) sets up or closes the whole office.
if [[ -n "$WHO" && ( "$EVENT" == "SessionStart" || "$EVENT" == "SessionEnd" ) ]]; then
  [[ -z "$FOREIGN" ]] && beat "$ROLE" sleeping
  exit 0
fi

case "$EVENT" in
  SessionStart)
    for role in $ROLES; do
      [[ "$role" == "lead" ]] && continue
      beat "$role" sleeping
    done
    beat lead idle
    ;;
  UserPromptSubmit) beat "$ROLE" thinking "Thinking" ;;
  PreToolUse) beat "$ROLE" working "$(tool_label)" ;;
  PostToolUse) beat "$ROLE" working "Done: $(tool_label)" ;;
  PostToolUseFailure) beat "$ROLE" error "Failed: $(tool_label)" ;;
  SubagentStart) beat "$ROLE" working "${PREFIX}Starting" ;;
  # A foreign subagent finishing doesn't mean the lead is idle: it still has its result.
  SubagentStop) if [[ -n "$FOREIGN" ]]; then beat lead working "${PREFIX}Done"; else beat "$ROLE" idle; fi ;;
  TeammateIdle | Stop) beat "$ROLE" idle ;;
  TaskCompleted)
    SUBJECT="$(field .task_subject)"
    beat "$ROLE" speaking "Completed: ${SUBJECT:0:50}"
    ;;
  SessionEnd)
    for role in $ROLES; do beat "$role" offline; done
    ;;
esac

exit 0
