#!/usr/bin/env bash
# Mechanical check for the TaskCompleted hook: no task closes with the project's checks
# failing. Exits with 2 to send the failure back to the agent.
#
# Configured in .claude/team.json → gate:
#   ignore: patterns (shell globs) of files that don't trigger checks
#   checks: [{ name, when: [patterns], run: "command" }]
# Without team.json or without checks, it does nothing.
#
# The scope comes from the files changed in the working tree, which the whole team shares.
# Checks run one at a time (a per-project lock): several at once overwrite each other's build
# artefacts. Tests that write to a database shouldn't be here: the reviewer runs them one
# after another.

set -uo pipefail

INPUT="$(cat)"
TASK_SUBJECT="$(jq -r '.task_subject // "untitled task"' <<<"$INPUT")"
ROOT="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}"
CONFIG="$ROOT/.claude/team.json"
[[ -f "$CONFIG" ]] || exit 0
(( $(jq '.gate.checks // [] | length' "$CONFIG") > 0 )) || exit 0
cd "$ROOT" || exit 0

IGNORE="$(jq -r '.gate.ignore // [] | .[]' "$CONFIG")"
CHANGED="$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u | sed '/^$/d')"

matches_any() {
  local file="$1" patterns="$2" pattern
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # shellcheck disable=SC2254 # the pattern is a glob on purpose
    case "$file" in $pattern) return 0 ;; esac
  done <<<"$patterns"
  return 1
}

RELEVANT=""
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  matches_any "$file" "$IGNORE" || RELEVANT+="$file"$'\n'
done <<<"$CHANGED"
[[ -n "$RELEVANT" ]] || exit 0

# Checks that apply, in team.json order.
TO_RUN=()
COUNT="$(jq '.gate.checks | length' "$CONFIG")"
for (( i = 0; i < COUNT; i++ )); do
  WHEN="$(jq -r ".gate.checks[$i].when // [] | .[]" "$CONFIG")"
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if matches_any "$file" "$WHEN"; then TO_RUN+=("$i"); break; fi
  done <<<"$RELEVANT"
done
(( ${#TO_RUN[@]} > 0 )) || exit 0

LOCK="${TMPDIR:-/tmp}/team-gate-$(printf '%s' "$ROOT" | shasum | cut -c1-12).lock"
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  # A lock older than 15 minutes belongs to a check that died without cleaning up.
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]]; then
    rmdir "$LOCK" 2>/dev/null
    continue
  fi
  if (( waited >= 480 )); then
    echo "quality-gate: another check has been running for more than 8 minutes. Try closing '$TASK_SUBJECT' again." >&2
    exit 2
  fi
  sleep 5
  waited=$((waited + 5))
done
LOG="$(mktemp)"
trap 'rmdir "$LOCK" 2>/dev/null; rm -f "$LOG"' EXIT

for i in "${TO_RUN[@]}"; do
  NAME="$(jq -r ".gate.checks[$i].name // \"check $i\"" "$CONFIG")"
  RUN="$(jq -r ".gate.checks[$i].run" "$CONFIG")"
  if ! bash -c "$RUN" >"$LOG" 2>&1; then
    {
      echo "Can't close '$TASK_SUBJECT': the '$NAME' check fails ($RUN)."
      echo "Last lines of the output:"
      tail -n 60 "$LOG"
      echo
      echo "Fix the failure and mark the task as completed again."
      echo "If the failure comes from another teammate's change, tell the lead instead of touching their files."
    } >&2
    exit 2
  fi
done

exit 0
