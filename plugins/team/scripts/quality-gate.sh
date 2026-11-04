#!/usr/bin/env bash
# Mechanical check for the TaskCompleted hook: no task closes with the project's checks
# failing. Exits with 2 to send the failure back to the agent.
#
# Configured in .claude/team.json → gate:
#   ignore: patterns (shell globs) of files that don't trigger checks
#   checks: [{ name, when: [patterns], run: "command", cwd: "optional/subfolder" }]
#     {files} in `run` becomes the changed files that match `when` (quoted, relative to `cwd`),
#     so lint touches only what changed. Slow, whole-project checks (build, full suite) go in
#     gate.final instead: the reviewer runs those once, at the end of the change.
# Without team.json or without checks, it does nothing.
#
# The scope comes from the files changed in the working tree, which the whole team shares. In a
# workspace (a root that is not a repo), from each child repo, prefixed with its folder.
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

# Changed files in a git repo (tracked changes and untracked files), one per line.
repo_changes() { # repo_changes <dir>
  { git -C "$1" diff --name-only HEAD; git -C "$1" ls-files --others --exclude-standard; } 2>/dev/null
}
# True when <dir> is the top of a git repo, not just somewhere inside one (a stray repo in
# $HOME would otherwise swallow every folder under it).
is_repo_root() { # is_repo_root <dir>
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$top" == "$(cd "$1" && pwd -P)" ]]
}
# A workspace is a folder that isn't a repo root and holds several repos (usually symlinks
# to them), directly or one level down (group/front, group/back). Each repo's changes are
# listed with its path as prefix, so `when`, `owns` and `cwd` are written "repo-api/*",
# "repo-api", "group/front"…
workspace_repos() {
  local dir sub
  for dir in */; do
    dir="${dir%/}"
    if is_repo_root "$dir"; then echo "$dir"; continue; fi
    for sub in "$dir"/*/; do
      sub="${sub%/}"
      [[ -d "$sub" ]] && is_repo_root "$sub" && echo "$sub"
    done
  done
}
REPOS=""
is_repo_root . || REPOS="$(workspace_repos)"
if [[ -z "$REPOS" ]]; then
  CHANGED="$(repo_changes . | sort -u | sed '/^$/d')"
else
  CHANGED="$(
    while IFS= read -r repo; do
      repo_changes "$repo" | sed "/^\$/d; s|^|$repo/|"
    done <<<"$REPOS" | sort -u
  )"
fi

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

# Changed files that match a check's `when` and still exist, shell-quoted and relative to
# its `cwd`, to replace {files} in `run` (lint only what changed instead of the whole repo).
files_for() { # files_for <check index> <cwd>
  local when file rel out=""
  when="$(jq -r ".gate.checks[$1].when // [] | .[]" "$CONFIG")"
  while IFS= read -r file; do
    [[ -z "$file" || ! -f "$file" ]] && continue
    matches_any "$file" "$when" || continue
    rel="$file"
    if [[ -n "$2" ]]; then
      [[ "$file" == "$2/"* ]] || continue
      rel="${file#"$2"/}"
    fi
    out+=" $(printf '%q' "$rel")"
  done <<<"$RELEVANT"
  printf '%s' "${out# }"
}

for i in "${TO_RUN[@]}"; do
  NAME="$(jq -r ".gate.checks[$i].name // \"check $i\"" "$CONFIG")"
  RUN="$(jq -r ".gate.checks[$i].run" "$CONFIG")"
  CWD="$(jq -r ".gate.checks[$i].cwd // empty" "$CONFIG")"
  CWD="${CWD%/}"
  if [[ "$RUN" == *"{files}"* ]]; then
    FILES="$(files_for "$i" "$CWD")"
    [[ -n "$FILES" ]] || continue # only deletions: nothing to lint
    RUN="${RUN//\{files\}/$FILES}"
  fi
  if ! (cd "$ROOT/${CWD:-.}" && bash -c "$RUN") >"$LOG" 2>&1; then
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
