# 門の司令塔側の手順書

> **2026-09-25 追記**：AT22 から起こした Claude Code では、Bash・Edit・Write などの**道具の実行**は
> AT22 の承認の板で直接訊かれる（`--permission-prompt-tool stdio`、Lv.2 は全部・Lv.3 は編集以外）。
> ただし**サブエージェントを起こす Agent ツールはどの権限モードでも訊かれない**（claude 2.1.282 で実測）ので、
> 「ワーカーを起こす前に指示に口を挟む」のは、今もこの門だけが担う。

## 何のための仕組みか

司令塔がサブエージェントを起こす直前に、人間が指示に口を挟むための仕組み。**止めているのは AT22 ではなく司令塔自身**。AT22 は Claude Code に干渉しないので、司令塔が自分から Bash の待ちループに入り、AT22 が置いた答え（verdict）でループを抜ける。AT22 は記憶DB（`~/.claude/projects/<プロジェクト>/memory/gate/`）に答えを書くだけで、司令塔の制御には干渉しない。

## やりとりの流れ

```
司令塔サイド:  承認モードを読む
             ↓
          判断：止まるか
             ↓
          [止まる場合]
             ↓
         gate/<id>.md を書く
             ↓
    until [ -f <id>.verdict ]; do
      sleep 2
    done        ← ここで待つ
             ↓
          答えを読む
             ↓
       allow / deny / revise で分岐

AT22 サイド:  門の md を発見・表示
             ↓
         人間が答える
             ↓
      gate/<id>.verdict を書く
```

## 司令塔がやること

### 1. 承認モードの確認

memory ルートから `gate/LEVEL` ファイルを読む。無ければ既定の `normal` を使う。

```bash
MEMORY_ROOT="$HOME/.claude/projects/<project-slug>/memory"
LEVEL_FILE="$MEMORY_ROOT/gate/LEVEL"

if [ -f "$LEVEL_FILE" ]; then
  LEVEL=$(cat "$LEVEL_FILE" | tr -d ' \n')
else
  LEVEL="normal"
fi
```

### 2. この指示で止まるかを判断

指示のリスクレベルと現在のモードで判定する。以下の条件が全部 **true** の場合だけ、門を立てる：

| レベル | リスク値で止まるか |
|---|---|
| `plan` | 止めない（そもそも指示を出さない） |
| `each` | **すべての指示で止まる** |
| `normal` | `risk` が `high` の場合だけ |
| `auto` | 止めない |
| `unattended` | 止めない |

```bash
stops_gate() {
  local level="$1"
  local risk="$2"
  
  case "$level" in
    plan)       return 1 ;;  # false
    each)       return 0 ;;  # true
    normal)     [ "$(echo "$risk" | tr '[:upper:]' '[:lower:]')" = "high" ] ;;
    auto|unattended) return 1 ;;
    *)          return 1 ;;
  esac
}

if stops_gate "$LEVEL" "$INSTRUCTION_RISK"; then
  # 以下に続く
else
  # 指示を出す（門を立てない）
  exit 0
fi
```

### 3. 門の markdown を書く

`memory/gate/<id>.md` を作成する。frontmatter は以下のキーを含める：

**必須キー：**
- `call` — Agent ツールの tool_use id（**これが無いと AT22 が捨てる**）

**任意キー：**
- `by` — 出した司令塔のエージェント ID
- `to` — 起こそうとしている相手（指定なければ `call` と同じ）
- `risk` — `high` / `low` など
- `issued` — ISO8601 形式の発行時刻

本文は指示そのもの。

```bash
GATE_ID="some-uuid-or-token"
GATE_FILE="$MEMORY_ROOT/gate/$GATE_ID.md"

mkdir -p "$(dirname "$GATE_FILE")"

cat > "$GATE_FILE" <<'EOF'
---
call: tool-use-id-from-claude
by: orchestrator-agent-id
to: target-worker
risk: high
issued: 2025-08-01T12:34:56Z
---
The full instruction text goes here.
This is what the orchestrator is about to send to the worker.
EOF
```

### 4. 答えを待つ

答えのファイル名は、元の md と同じ名前で `.verdict` 拡張子：

```bash
VERDICT_FILE="${GATE_FILE%.*}.verdict"

# 最大タイムアウト（例：5分）
TIMEOUT=300
START=$(date +%s)

until [ -f "$VERDICT_FILE" ]; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Gate timeout after ${TIMEOUT}s" >&2
    exit 1
  fi
  
  sleep 2
done
```

### 5. 答えを読んで判定

答えのファイルは frontmatter に `verdict:` キーを含む：

```bash
# 答えを読む
VERDICT=$(grep "^verdict: " "$VERDICT_FILE" | cut -d' ' -f2)

case "$VERDICT" in
  allow)
    # そのまま指示を発行する
    issue_instruction
    ;;
  deny)
    # 発行せず記録して次へ
    log_denied
    exit 0
    ;;
  revise)
    # 書き換えた指示で発行
    # 本文の frontmatter 以後が新しい指示
    REVISED=$(sed '1,/^---$/d' "$VERDICT_FILE")
    issue_instruction_with_text "$REVISED"
    ;;
  *)
    echo "Unknown verdict: $VERDICT" >&2
    exit 1
    ;;
esac
```

## プロジェクトパスの求め方

司令塔が実行している時点での `cwd`（作業ディレクトリ）から、記憶DB のパスを導く。

Claude Code の `~/.claude/projects/<project-slug>` の `<project-slug>` は、`cwd` のパス文字列を以下の規則で変換して得られる：

**規則：文字と数字以外をすべてハイフンに置き換える**

```bash
project_slug() {
  local cwd="$1"
  # 文字（a-z, A-Z）と数字（0-9）以外をハイフンに置き換える
  echo "$cwd" | sed 's/[^a-zA-Z0-9]/-/g'
}

# 使用例：
CWD="$(pwd)"
SLUG=$(project_slug "$CWD")
MEMORY_ROOT="$HOME/.claude/projects/$SLUG/memory"
```

例えば：
- `/Users/alice/my-project` → `slug = Users-alice-my-project`
- `/home/dev/at22-glass-cockpit` → `slug = home-dev-at22-glass-cockpit`

## 既存スキルへの組み込み方

`token-saver-orchestrator` や `token-saver-codex` など、オーケストレーター系スキルでワーカーに指示を出す直前に、この門の判定を挟む。

**置き場所：** 実装ワーカーへ指示を出す `claude` のコマンドを組み立てる直前

**プロンプト断片（そのまま貼れる形）：**

```
## 門の確認と待ち

指示を出す前に、以下の判定を入れてください。

1. 承認モードを読む：`cat ~/.claude/projects/<プロジェクトスラッグ>/memory/gate/LEVEL` の内容（無ければ `normal`）
2. この指示がそのモードで止まるかを判定する：
   - `plan` なら止めない（ここまで来ない）
   - `each` なら必ず止める
   - `normal` なら `risk: high` の指示だけ止める
   - `auto` / `unattended` なら止めない
3. 止まる場合、`~/.claude/projects/<プロジェクトスラッグ>/memory/gate/<uuid>.md` に以下の形で門を書く：
   ```
   ---
   call: <tool-use-id>
   by: <your-agent-id>
   to: <target-worker>
   risk: high
   issued: <ISO8601-timestamp>
   ---
   <full-instruction>
   ```
4. `~/.claude/projects/<プロジェクトスラッグ>/memory/gate/<uuid>.verdict` が現れるまで、`until [ -f <file> ]; do sleep 2; done` で待つ
5. 答えを読んで：
   - `verdict: allow` なら、指示をそのまま発行
   - `verdict: deny` なら、発行を中止して記録
   - `verdict: revise` なら、本文（frontmatter 以後）を新しい指示に置き換えて発行

プロジェクトスラッグ = `cwd` の文字列で「文字と数字以外をハイフン」に変換した値
```

## 注意点

1. **答えが来ないと永久に待つ** — ループにタイムアウトを入れるか、手動で `~/.claude/projects/<project-slug>/memory/gate/` のファイルを削除して司令塔を再起動する
2. **無人モード（Lv.5）では門が立たない** — `unattended` レベルを選ぶと、全指示が門を立たずに通る。人間不在の想定なので、門を選ぶべき段階なら Lv.3 か Lv.4 を選ぶ
3. **`gate/` は記憶DB の一覧には出ない** — AT22 のツール UI 上では `gate/` フォルダは非表示。実際のファイルシステムには書かれているので、Finder や terminal から直接操作できる
4. **frontmatter の `call` が無い門は捨てられる** — AT22 が司令塔と結びつけられないので、画面に出す価値がない。必ず `call:` に tool-use id を入れる

## 采配 ── AT22 にワーカーを起こしてもらう

門の書式に `dispatch:` を足すと、「自分で Agent ツールを呼ぶ」代わりに **AT22 がワークスペース（git worktree）を作って、そこで別のエージェントを起こす**。人が板で許可したときだけ動く（答えるのは人のクリックだけ、は門と同じ）。

**足すキー：**
- `dispatch` — 起こすエージェント。`claude` / `codex` / `grok` / `hermes`（知らない名前なら普通の門として扱う）
- `name` — ワークスペースの名前。置き場は `<リポジトリ>/.claude/worktrees/<name>`、枝は `at22/<name>`。省略すると `to`
- `base` — 分岐の基点（枝・コミット）。省略すると `HEAD`

リポジトリは**板で門を見ていたセッション（＝司令塔）の作業ディレクトリ**から引く。worktree の中で動いている司令塔なら、本体のリポジトリに作る。

```bash
cat > "$GATE_FILE" <<'EOF2'
---
call: w1
by: orchestrator-agent-id
to: fixer
dispatch: grok
name: fix-readme
base: main
---
README の手順を直して。終わったら何を変えたかを一文で。
EOF2
```

**答えは2段階で来る：**
1. `<id>.verdict` — 門と同じ。`allow` / `revise` なら AT22 がワークスペースを作り始めている（`revise` の本文がワーカーへの指示になる）。`deny` なら何も作らない
2. `<id>.result` — ワーカーの**最初のターン**が終わったら書かれる。2ターン目以降では書き直さない

```
---
status: done            # done / failed / stopped（人が止めた）
at: 2026-09-26T08:08:09Z
workspace: /path/to/repo/.claude/worktrees/fix-readme
branch: at22/fix-readme
agent: grok
session: b8ce8741-…     # AT22 の会話欄・サイドバーで開ける
---
ワーカーの返事（最後の 4000 字まで）
```

作れなかった・起こせなかったときも `status: failed` と `error:` を書く（待たせ続けない）。

```bash
RESULT_FILE="${GATE_FILE%.*}.result"
until [ -f "$RESULT_FILE" ]; do sleep 5; done
STATUS=$(grep "^status: " "$RESULT_FILE" | cut -d' ' -f2)
```

変更はワーカーの worktree に残る。マージ・push・PR は人が AT22 のレビューのタブで決める（司令塔からは頼めない）。
