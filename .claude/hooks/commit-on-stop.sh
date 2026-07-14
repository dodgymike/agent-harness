#!/usr/bin/env bash
# One commit per turn (instead of one commit per Write/Edit).
#
# Fires on Stop (main agent end-of-turn) and SubagentStop (a Task subagent finishing),
# so each turn/task produces ONE commit instead of one commit per Write/Edit. Stages all
# changes (respecting .gitignore) and commits them together.
#
# Guard: refuses to auto-commit when an untracked, NON-ignored file larger than 25 MB
# would be staged — that almost always means a build artifact, model weight, or dataset
# leaked into the tree. In that case it commits nothing and tells you to .gitignore it
# or move it to /tmp, so a giant blob never lands in history by accident.
set -u

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# --- >25 MB untracked-file guard -------------------------------------------------
limit=$((25 * 1024 * 1024))
big=""
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  sz=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$sz" -gt "$limit" ]; then
    big="${big}  ${f} ($((sz / 1024 / 1024)) MB)\n"
  fi
done <<EOF
$(git ls-files --others --exclude-standard)
EOF

if [ -n "$big" ]; then
  printf 'commit-on-stop: refusing auto-commit — large untracked file(s) present:\n%b' "$big" >&2
  printf 'Add them to .gitignore or move to /tmp, then commit manually.\n' >&2
  exit 0
fi

# --- one commit for everything staged this turn ----------------------------------
git add -A 2>/dev/null || exit 0
git diff --cached --quiet 2>/dev/null && exit 0  # nothing to commit

n=$(git diff --cached --name-only | wc -l | tr -d ' ')
git commit -q \
  -m "Session update: ${n} file(s)" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" 2>/dev/null
exit 0
