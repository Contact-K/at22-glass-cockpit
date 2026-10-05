#!/bin/bash
# AT22 の門（4段の承認＋壁打ち）。サブエージェントや別のエージェントを起こす前に呼び、人の答えを待つ。
#
#   gate.sh <call> <to> <risk> [dispatch] [name] [base]  < 指示文
#   gate.sh --wait <id>                                   （待ちの続き）
#
#   call      この指示の印（短い英数字。Agent の呼び出しごとに変える）
#   to        起こす相手の名前（例: fixer / Explore）
#   risk      high か low。Lv.2 は high だけ止める
#   dispatch  claude / codex / grok / hermes を書くと、AT22 が worktree を作ってそのエージェントを起こす（采配）
#   name      采配の worktree の名前（省略すると to）
#   base      采配の分岐の基点（省略すると HEAD）
#
# 出力の最初の行が答え:
#   verdict: allow    そのまま出す
#   verdict: deny     出さない（見送ったことを記録して次へ）
#   verdict: revise   書き換えられた。3行目以降（frontmatter の後）が新しい指示
#   pending: <id>     まだ答えが無い（終了コード 3）。`gate.sh --wait <id>` をもう一度呼ぶ
# 采配を許可されたら、続けて `=== result` の後にワーカーの最初の返事が出る。
set -uo pipefail

slug=$(pwd | sed 's/[^a-zA-Z0-9]/-/g')
root="$HOME/.claude/projects/$slug/memory/gate"
mkdir -p "$root"
# Claude の Bash 道具は1回 10 分まで。それより少し短く待って、残りは --wait で続ける
wait_for=${AT22_GATE_WAIT:-540}

await() {   # <file> <seconds>
    local file="$1" until=$(( $(date +%s) + $2 ))
    while [ ! -f "$file" ]; do
        [ "$(date +%s)" -ge "$until" ] && return 1
        sleep 2
    done
}

answer() {  # <id>
    local id="$1"
    if ! await "$root/$id.verdict" "$wait_for"; then
        echo "pending: $id"
        exit 3
    fi
    cat "$root/$id.verdict"
    if grep -q '^dispatch:' "$root/$id.md" && grep -Eq '^verdict: (allow|revise)' "$root/$id.verdict"; then
        if ! await "$root/$id.result" "$wait_for"; then
            echo
            echo "pending: $id   # ワーカーの最初の返事待ち。gate.sh --wait $id で続ける"
            exit 3
        fi
        echo
        echo "=== result"
        cat "$root/$id.result"
    fi
    exit 0
}

if [ "${1:-}" = "--wait" ]; then
    answer "${2:?id が要る}"
fi

call="${1:?call が要る}"; to="${2:-$1}"; risk="${3:-high}"
dispatch="${4:-}"; name="${5:-}"; base="${6:-}"
level=$( { tr -d ' \n' < "$root/LEVEL"; } 2>/dev/null || true)
level=${level:-normal}

# 段ごとの止め方（AT22 の Gate.Level.stops と同じ）。采配はここで判定せず門を立てる（Lv.3/4 は AT22 が自動で許可する）
if [ -z "$dispatch" ]; then
    case "$level" in
        plan)    echo "verdict: deny"; echo "# 壁打ち: 指示を出さない段"; exit 0 ;;
        each)    ;;
        normal)  if [ "$(printf '%s' "$risk" | tr '[:upper:]' '[:lower:]')" != "high" ]; then
                     echo "verdict: allow"; echo "# Lv.2: risk が high ではないので止めない"; exit 0
                 fi ;;
        *)       echo "verdict: allow"; echo "# Lv.3/4 ($level): 止めない"; exit 0 ;;
    esac
fi

id="$(date +%Y%m%d%H%M%S)-$call"
body=$(cat)
{
    echo "---"
    echo "call: $call"
    echo "to: $to"
    echo "risk: $risk"
    echo "issued: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -n "$dispatch" ]; then echo "dispatch: $dispatch"; fi
    if [ -n "$name" ]; then echo "name: $name"; fi
    if [ -n "$base" ]; then echo "base: $base"; fi
    echo "---"
    printf '%s\n' "$body"
} > "$root/$id.md"

answer "$id"
