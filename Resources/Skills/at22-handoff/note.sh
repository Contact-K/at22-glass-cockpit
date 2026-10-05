#!/bin/bash
# AT22 の記憶DB のノートの置き場を出す。1行目: このセッションのノート、2行目: SHARED.md
#   note.sh <セッションID>
# 記憶DB はリポジトリ本体のもの（worktree の中から呼んでも本体を引く。AT22 の Worktree.root と同じ）
set -uo pipefail
session="${1:?セッションID が要る}"
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$common" ] && [ "${common%/.git}" != "$common" ]; then base="${common%/.git}"; else base=$(pwd); fi
slug=$(printf '%s' "$base" | sed 's/[^a-zA-Z0-9]/-/g')
dir="$HOME/.claude/projects/$slug/memory/sessions"
echo "$dir/each/$session.md"
echo "$dir/SHARED.md"
