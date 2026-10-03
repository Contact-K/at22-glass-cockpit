#!/bin/zsh
# AT22 の 07 REVIEW / 08 GIT を試すための使い捨てリポジトリを作る。何度でも作り直せる。
#
#   ./scripts/git-playground.sh          # /tmp/at22-git-test に作って AT22 に登録
#   ./scripts/git-playground.sh --clean  # 消して登録も外す
#
# 送り先（origin）は同じ場所の裸のリポジトリなので、push しても GitHub には何も行かない。
# そのぶん PR（gh）は試せない。登録は UserDefaults に書くので、AT22 を閉じてから走らせ、終わったら起動し直す。
set -euo pipefail

ROOT=/tmp/at22-git-test
REPO="$ROOT/playground"
# Xcode / swift run から起こした時の UserDefaults。package.sh の .app は com.contactk.at22
DOMAIN=${AT22_DOMAIN:-AT22}

unregister() {
  local current
  current=$(defaults read "$DOMAIN" projects 2>/dev/null | sed -n 's/^ *"\(.*\)",*$/\1/p' | grep -vx "$REPO" || true)
  defaults delete "$DOMAIN" projects 2>/dev/null || true
  [[ -n "$current" ]] && defaults write "$DOMAIN" projects -array ${(f)current}
  return 0
}

if [[ "$DOMAIN" == AT22 ]] && pgrep -xq AT22; then
  echo "AT22 が起動中です。閉じてから走らせてください（登録の書き込みが上書きされるため）。" >&2
  exit 1
fi

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$ROOT"
  unregister
  echo "消しました: $ROOT（登録も外した）"
  exit 0
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"
git init -q --bare -b main "$ROOT/remote.git"
git init -q -b main "$REPO"
cd "$REPO"
git config user.name "AT22 Test"
git config user.email "test@example.invalid"
seq 1 40 | sed 's/^/line /' > notes.txt
printf 'struct Greeting {\n  let text = "hello"\n}\n' > Greeting.swift
git add . && git commit -qm "base"
git remote add origin "$ROOT/remote.git"
git push -q -u origin main

# AT22 が作るのと同じ置き場・枝の名前の worktree（.claude/worktrees/try · at22/try）
echo ".claude/worktrees/" >> .git/info/exclude
git worktree add -q -b at22/try .claude/worktrees/try main
cd .claude/worktrees/try
git config user.name "AT22 Test"
git config user.email "test@example.invalid"
# 未コミットの変更: 2 ハンクの変更・1 ハンクの変更・追跡外の新規ファイル
sed -i '' 's/^line 3$/LINE 3 changed/; s/^line 30$/LINE 30 changed/' notes.txt
printf 'struct Greeting {\n  let text = "hello, AT22"\n}\n' > Greeting.swift
printf 'struct Fresh {}\n' > Fresh.swift

unregister
defaults write "$DOMAIN" projects -array-add "$REPO"

cat <<EOF
作りました: $REPO
  worktree  .claude/worktrees/try（枝 at22/try）
  変更      notes.txt（2 ハンク）· Greeting.swift（1 ハンク）· Fresh.swift（追跡外）
  送り先    $ROOT/remote.git（ローカル。GitHub には行かない）

AT22 を起動 → 管制塔の「playground」の try のタイルに入る → 07 REVIEW / 08 GIT
外で確かめる:  git -C $REPO/.claude/worktrees/try status -sb
              git -C $ROOT/remote.git log --oneline at22/try
EOF
