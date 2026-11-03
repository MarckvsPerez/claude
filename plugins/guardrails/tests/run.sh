#!/usr/bin/env bash
# Guard tests. They never run the commands: they only feed the guard their text.
# Usage: plugins/guardrails/tests/run.sh

set -uo pipefail
GUARD="$(cd "$(dirname "$0")/.." && pwd)/scripts/guard.sh"
PROJECT="/Users/demo/project"
PASS=0
FAIL=0

decision() {
  local out
  out="$(jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | CLAUDE_PROJECT_DIR="$PROJECT" "$GUARD")"
  if [[ -z "$out" ]]; then echo none; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"; fi
}
expect() { # expect <deny|ask|none> <command>
  local got
  got="$(decision "$2")"
  if [[ "$got" == "$1" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: expected $1, got $got → $2"; fi
}

echo "== commit and push"
expect deny 'git commit -m "feat: something"'
expect deny 'git -C /repo commit --amend --no-edit'
expect deny 'git -c user.email=x@y commit -am wip'
expect deny 'cd app && git add . && git commit -m x'
expect deny 'git push -u origin main'
expect deny 'git push --force-with-lease'
expect deny 'sh -c "git push"'
expect deny 'gh pr create --fill'
expect deny 'gh pr merge 12 --squash'
expect none 'git status'
expect none 'git log --grep commit'
expect none 'git diff HEAD'
expect none 'git add -A'
expect none 'git commit-graph verify'
expect none 'gh pr view 12'
expect none 'npm run commitlint'

echo "== database"
expect deny 'mysql -h db.prod.example.com -u admin -e "DELETE FROM users"'
expect deny 'psql postgres://app@10.0.0.4:5432/app -c "UPDATE orders SET paid = true"'
expect deny 'ssh bastion "mysql -e \"DROP TABLE logs\""'
expect deny 'kubectl exec -it api-0 -- mysql -e "TRUNCATE sessions"'
expect deny 'DB_HOST=rds.amazonaws.com npm run migrate'
expect deny 'mongosh "mongodb+srv://u@cluster0.mongodb.net/app" --eval "db.users.deleteMany({})"'
expect ask 'npx sequelize-cli db:migrate'
expect ask 'npx prisma migrate deploy'
# SQL from a file against a remote host: it may write and that cannot be checked → treated as a remote write.
expect deny 'mysql -h prod.example.com app < seed.sql'
expect none 'mysql -h 127.0.0.1 -P 3399 app < seed.sql'
expect none 'mysql -h 127.0.0.1 -P 3399 -u root -e "INSERT INTO t VALUES (1)"'
expect none 'docker compose exec db mysql -uroot -e "DROP DATABASE sky_test_1"'
expect none 'docker compose --env-file env/.env.local exec backend npm run migrate'
expect none 'mysql -h db.prod.example.com -e "SELECT COUNT(*) FROM users"'
expect none 'psql -h 10.0.0.4 -c "EXPLAIN SELECT * FROM orders"'
expect none 'mysql -u root -e "CREATE DATABASE demo"'
expect none 'npm test'

echo "== destructive changes"
expect ask 'git reset --hard HEAD~1'
expect ask 'git clean -fd'
expect ask 'git checkout -- .'
expect ask 'git restore .'
expect ask 'git stash drop'
expect ask 'git branch -D feature/x'
expect ask 'rm -rf ~/Documents'
expect ask 'rm -rf /etc/nginx'
expect ask 'rm -rf ../other-repo'
expect ask 'rm -rf *'
expect none 'rm -rf node_modules dist'
expect none "rm -rf $PROJECT/build"
expect none 'rm -rf /tmp/claude-tests'
expect none 'rm file.txt'
expect none 'git restore --staged src/a.ts'
expect none 'git checkout -b feature/new'

echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
