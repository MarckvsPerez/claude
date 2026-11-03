#!/usr/bin/env bash
# PreToolUse for Bash, Monitor and the desktop app's terminal: enforces the user's rules
# instead of trusting the model to remember them.
#
#   1. Commit and push        → deny. The user reviews, commits and pushes.
#   2. Database writes        → deny if the target is remote, ask if it can't be shown to be
#                               local, nothing if it is verified local.
#   3. Destructive changes    → ask (reset --hard, clean -f, rm -rf outside the project…).
#
# Returns the decision as JSON on stdout and exits 0. No output = no decision: the action
# follows the normal permission flow. It scans the full command text, quoted parts included
# (sh -c "git push" is blocked too); the price is a false positive on `echo "git push"`.
# It can't see through shell aliases.

set -uo pipefail

INPUT="$(cat)"
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
[[ -n "$CMD" ]] || exit 0
PROJECT="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}"

RULE="This is the user's rule (CLAUDE.md), enforced by the guardrails plugin."

decide() { # decide <deny|ask> <reason>
  jq -nc --arg d "$1" --arg r "$2 $RULE" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

has() { grep -Eiq -- "$1" <<<"$CMD"; }
SEP='(^|[[:space:];&|(`"'"'"'])' # command start: beginning, separator or quote

# --- 1. Commit and push ---------------------------------------------------------------
GIT_OPTS='([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*'
if has "${SEP}git${GIT_OPTS}[[:space:]]+(commit|push)([[:space:];&|)\"']|\$)"; then
  decide deny "Claude does not commit or push. Leave the changes in the working tree and give the user the command to run themselves."
fi
if has "${SEP}gh[[:space:]]+(pr[[:space:]]+(create|merge)|repo[[:space:]]+(create|delete|sync))"; then
  decide deny "Claude does not create or merge PRs or modify remote repositories: that means pushing changes. Prepare the text and let the user run it."
fi

# --- 2. Database writes ---------------------------------------------------
DB_CLIENT="${SEP}(mysql|mariadb|psql|mongosh|mongo|redis-cli|sqlcmd|clickhouse-client|cqlsh)([[:space:]]|\$)"
MIGRATION='(sequelize(-cli)?[[:space:]]+db:(migrate|seed)|prisma[[:space:]]+(migrate[[:space:]]+(dev|deploy|reset)|db[[:space:]]+(push|execute|seed))|knex[[:space:]]+(migrate|seed)|typeorm[[:space:]].*migration:(run|revert)|drizzle-kit[[:space:]]+(push|migrate)|npm[[:space:]]+run[[:space:]]+(migrate|db:[a-z:-]+|seed)|flyway[[:space:]]+(migrate|clean)|liquibase[[:space:]]+update|artisan[[:space:]]+(migrate|db:seed)|rails[[:space:]]+db:|alembic[[:space:]]+(upgrade|downgrade))'
SQL_WRITE='\b(insert[[:space:]]+into|update[[:space:]]+[`"a-z0-9_.]+[[:space:]]+set|delete[[:space:]]+from|alter[[:space:]]+(table|database|user)|drop[[:space:]]+(table|database|schema|index|view|user)|create[[:space:]]+(table|database|schema|index|view|user)|truncate|replace[[:space:]]+into|grant[[:space:]]|revoke[[:space:]]|rename[[:space:]]+table|kill[[:space:]]|set[[:space:]]+global|load[[:space:]]+data|flush)\b'
NOSQL_WRITE='\.(insert(One|Many)?|update(One|Many)?|delete(One|Many)|replaceOne|drop|dropDatabase|remove|createIndex|bulkWrite)\(|\b(flushall|flushdb|del|hset|hdel|expire|lpush|rpush|sadd|srem|zadd)[[:space:]]'

IS_CLIENT=false; IS_MIGRATION=false; WRITES=unknown
has "$DB_CLIENT" && IS_CLIENT=true
has "$MIGRATION" && IS_MIGRATION=true

if $IS_CLIENT || $IS_MIGRATION; then
  if $IS_MIGRATION || has "$SQL_WRITE" || has "$NOSQL_WRITE"; then
    WRITES=yes
  elif has '(<[[:space:]]*[^<[:space:]]+|--execute=?[[:space:]]*@|source[[:space:]]+[^[:space:]]+\.sql|-f[[:space:]]+[^[:space:]]+\.sql)'; then
    WRITES=unknown # SQL from a file: its content can't be seen
  else
    WRITES=no
  fi
fi

if [[ "$WRITES" != "no" ]] && ($IS_CLIENT || $IS_MIGRATION); then
  # Where does it go? remote / local / unknown
  TARGET=unknown
  if has "${SEP}(ssh|autossh|kubectl[[:space:]]+exec|gcloud|aws[[:space:]]+ssm|heroku|fly[[:space:]]+ssh|railway[[:space:]]+run)([[:space:]]|\$)"; then
    TARGET=remote
  elif has "${SEP}docker([[:space:]]+compose)?[[:space:]].*exec[[:space:]]" && ! has '(DOCKER_HOST=|--context[[:space:]=]|[[:space:]]-H[[:space:]])' && [[ -z "${DOCKER_HOST:-}" ]]; then
    TARGET=local # container on this machine's Docker
  else
    HOSTS="$(grep -Eio -- '(-h[[:space:]]*|--host[=[:space:]]+)[^[:space:]]+|([a-z+]+)://[^[:space:]]+' <<<"$CMD" \
      | sed -E 's#^(-h[[:space:]]*|--host[=[:space:]]+)##; s#^[a-z+]+://([^@/]*@)?##; s#[:/?].*$##' | tr -d "\"'")"
    ENV_HOSTS="$(grep -Eio -- '\b(DB_HOST|MYSQL_HOST|PGHOST|DATABASE_HOST|[A-Z_]*DB_HOST)=[^[:space:]]+' <<<"$CMD" | cut -d= -f2- | tr -d "\"'")"
    ALL_HOSTS="$(printf '%s\n%s\n' "$HOSTS" "$ENV_HOSTS" | sed '/^$/d')"
    if [[ -n "$ALL_HOSTS" ]]; then
      TARGET=local
      while IFS= read -r h; do
        case "$h" in 127.0.0.1 | localhost | ::1 | 0.0.0.0) ;; *) TARGET=remote ;; esac
      done <<<"$ALL_HOSTS"
    elif $IS_CLIENT && ! $IS_MIGRATION; then
      TARGET=local # client without a host: local socket
    fi
    # A local host can be a tunnel: check who serves the port.
    if [[ "$TARGET" == "local" ]]; then
      PORTS="$(grep -Eio -- '(-P[[:space:]]*|--port[=[:space:]]+|-p[[:space:]]+)[0-9]+|:[0-9]{2,5}\b' <<<"$CMD" | grep -Eo '[0-9]+$')"
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        LISTENER="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 {print $1}')"
        case "$LISTENER" in
          ssh | autossh | sshpass | kubectl | gcloud | cloud_sql* | cloud-sql* | socat | session-m*) TARGET=remote ;;
        esac
      done <<<"$PORTS"
    fi
  fi

  case "$TARGET" in
    remote) decide deny "This command writes (or may write) to a remote database. Only local database writes are allowed: write the SQL or script for the user to run." ;;
    unknown) decide ask "This command writes to a database and it cannot be shown to be local (a migration without an explicit host, or SQL from a file). Confirm only if it targets your local database." ;;
  esac
  [[ "$WRITES" == "unknown" ]] || exit 0 # verified local and explicit write: allowed
fi

# --- 3. Destructive changes ----------------------------------------------------------
if has "${SEP}git${GIT_OPTS}[[:space:]]+(reset[[:space:]]+.*--hard|clean[[:space:]]+-[a-z]*f|checkout[[:space:]]+(--[[:space:]]|\.([[:space:]]|\$))|restore([[:space:]]+--worktree)?[[:space:]]+(\.|:/)|stash[[:space:]]+(drop|clear)|branch[[:space:]]+-D)"; then
  decide ask "This command discards working-tree changes or deletes git work, maybe someone else's. Confirm only if you know what will be lost."
fi
if has "${SEP}rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)"; then
  TARGETS="$(grep -Eo -- "${SEP}rm[[:space:]].*" <<<"$CMD" | head -n 1 | tr ' ' '\n' | grep -Ev '^(rm|-.*)?$' | tr -d "\"'")"
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    case "$t" in
      / | /* | ~* | '$HOME'* | ..*)
        case "$t" in
          "$PROJECT"/* | "${TMPDIR:-/nonexistent}"* | /tmp/* | /private/tmp/* | /private/var/folders/*) ;;
          *) decide ask "This command deletes recursively outside the project ($t). Confirm only if that is what you want." ;;
        esac ;;
      '*' | '.*') decide ask "This command deletes recursively with a broad wildcard ($t). Confirm only if that is what you want." ;;
    esac
  done <<<"$TARGETS"
fi

exit 0
