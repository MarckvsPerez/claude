#!/usr/bin/env bash
# Bridge between Claude Code hooks and Miniverse: one character per team ROLE, with id
# "<project>-<role>". Only active if .claude/team.json has "miniverse".
#
# Runs as an async hook: it never blocks, prints nothing and always exits 0.
# It only sends role, state, tool and file name: never prompts, commands or content.
# The Miniverse server listens on every network interface.

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$ROOT/.claude/team.json"
[[ -f "$CONFIG" ]] || exit 0
URL="$(jq -r '.miniverse.url // empty' "$CONFIG" 2>/dev/null)"
[[ -n "$URL" ]] || exit 0

PROJECT="$(jq -r '.project // empty' "$CONFIG" 2>/dev/null)"
[[ -n "$PROJECT" ]] || PROJECT="$(basename "$ROOT")"
PROJECT="$(tr '[:upper:]' '[:lower:]' <<<"$PROJECT" | tr -c 'a-z0-9-\n' '-')"
# Characters registered at session start: the lead, the team.json roles and the plugin's
# shared workers, so they are on screen (asleep) before they ever work.
ROLES="lead $(jq -r '.roles // {} | keys | join(" ")' "$CONFIG" 2>/dev/null) explorer test-runner docs-researcher"

INPUT="$(cat)"
field() { jq -r "$1 // empty" <<<"$INPUT" 2>/dev/null; }

slug() { tr '[:upper:]' '[:lower:]' <<<"$1" | tr -c 'a-z0-9-\n' '-'; }
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

# Role: the team.json role whose "agent" is the event's agent type (so a repo specialist
# and a plugin profile both show up under their role name); otherwise the teammate name
# in team events; otherwise a plugin profile without its prefix ("team:front" → "front");
# and "lead" for the main session.
# Any other agent type (Claude Code built-ins such as general-purpose, Explore or Plan, or
# another plugin's agents) is not a team role: it gets no character of its own and shows
# up as the lead's work, labelled with its type. Otherwise every ad-hoc type would add a
# character that SessionEnd never puts offline.
AGENT_TYPE="$(field .agent_type)"
ROLE=""
FOREIGN=""
if [[ -n "$AGENT_TYPE" ]]; then
  ROLE="$(jq -r --arg t "$AGENT_TYPE" '[.roles // {} | to_entries[] | select(.value.agent == $t) | .key][0] // empty' "$CONFIG" 2>/dev/null)"
fi
[[ -n "$ROLE" ]] || ROLE="$(field .teammate_name)"
if [[ -z "$ROLE" && -n "$AGENT_TYPE" ]]; then
  if [[ "$AGENT_TYPE" == team:* ]]; then ROLE="${AGENT_TYPE#team:}"; else FOREIGN="$AGENT_TYPE"; fi
fi
[[ -n "$ROLE" ]] || ROLE="lead"
ROLE="$(slug "$ROLE")"
PREFIX="${FOREIGN:+$FOREIGN · }"

tool_label() {
  local file
  file="$(field '.tool_input.file_path')"
  if [[ -n "$file" ]]; then echo "$PREFIX$TOOL · ${file##*/}"; else echo "$PREFIX$TOOL"; fi
}

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
