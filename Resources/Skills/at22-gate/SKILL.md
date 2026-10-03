---
name: at22-gate
description: AT22 Glass Cockpit の5段階の承認（門）。サブエージェント（Agent ツール）を起こす前、または別のエージェント（codex / grok / hermes）に仕事を回す前に必ず使う。指示を AT22 の承認カードに出し、人の許可・却下・書き換えを受け取ってから出す。
---

# AT22 の門（5段階の承認）

AT22 から見られているセッションで、**ワーカーを起こす直前に人が指示へ口を挟む**ための手順。
止めるのは AT22 ではなくあなた自身で、AT22 は答えのファイルを置くだけ。道具（Bash・Edit など）の承認は
AT22 が別に訊くので、ここで扱うのは**サブエージェントの起動と、別のエージェントへの采配だけ**。

## 段（`~/.claude/projects/<slug>/memory/gate/LEVEL`、無ければ normal）

| Lv | 値 | 名前 | 門 |
|---|---|---|---|
| — | `plan` | 壁打ち（段とは別のトグル） | 指示を出さない（計画と相談だけ） |
| 1 | `each` | 隣で見てる | すべての指示で止まる |
| 2 | `normal` | 気にかけてる | `risk: high` の指示だけ止まる |
| 3 | `auto` | 任せてる | 止まらない |
| 4 | `unattended` | 留守番 | 止まらない（人がいない） |

段の判定・門の書き出し・答え待ちは同梱の `gate.sh` がやる。**自分で判定しない・ファイルを手で書かない。**

## 手順

Agent ツールを呼ぶ前に、毎回これを1回だけ実行する（Bash 道具の timeout は 600000 にする）:

```bash
bash ~/.claude/skills/at22-gate/gate.sh <call> <to> <risk> <<'EOF'
<ワーカーに渡す指示の全文>
EOF
```

- `<call>`: この呼び出しの短い印（`w1`, `fix-2` など。毎回変える）
- `<to>`: 起こす相手（`Explore`, `fixer` など）
- `<risk>`: ファイルを書く・消す・外へ送る・時間やお金がかかるなら `high`、読むだけなら `low`

出力の1行目で分ける:

- `verdict: allow` → 書いた指示のまま Agent ツールを呼ぶ
- `verdict: revise` → 2つ目の `---` より後の本文を**新しい指示として**そのまま使う
- `verdict: deny` → 起こさない。見送ったことを一言伝えて、別の進め方を考える
- `pending: <id>`（終了コード 3）→ まだ答えが無い。`bash ~/.claude/skills/at22-gate/gate.sh --wait <id>` をもう一度呼ぶ。**勝手に先へ進まない**

## 別のエージェントに回す（采配）

自分で Agent ツールを呼ぶ代わりに、AT22 に worktree を作ってもらい別のエージェントを起こす:

```bash
bash ~/.claude/skills/at22-gate/gate.sh <call> <to> high grok <worktree名> <基点> <<'EOF'
<指示>
EOF
```

- 4つ目は `claude` / `codex` / `grok` / `hermes`。采配は段にかかわらず必ず人に訊く
- 許可されると、続けて `=== result` の後にワーカーの最初の返事（`status` / `workspace` / `branch` / `session` と本文）が出る
- 変更はワーカーの worktree（`<リポジトリ>/.claude/worktrees/<名前>`・枝 `at22/<名前>`）に残る。
  マージ・push・PR は人が AT22 の 07 REVIEW / 08 GIT で決める。あなたからは頼まない

## してはいけないこと

- 門を通さずに Agent ツールを呼ぶ（Lv.3/4 でも `gate.sh` は呼ぶ。止まらずにすぐ `allow` が返る）
- `pending` のまま先へ進む、答えを推測する
- `gate/` のファイルを自分で書き換える・消す
