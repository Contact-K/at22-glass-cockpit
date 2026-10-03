# 引き継ぎ 2026-10-03 — orca-v10（Sumi v11 ＋ Orca 寄せ）

ブランチ `orca-v10`（push 済み、最新 `ed2dd27`）。`main` `dev` `at22/session-waiting` は触っていない。
デザインの正は claude.ai/design のプロジェクト `05bb6eef-0360-4c34-8076-bf7d830c9ec9` の `ui_kits/at22-v11/`
（DesignSync の `get_file`、認可が切れたら `/design-login`）。段取りと「モックと違えた所」は `docs/design/v11/PLAN.md`。

## まず読むこと（本人の作業の仕方）

- **本人は Xcode でビルドする。** `swift build` が通っても Xcode で落ちることがある。依存を変えたら
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme AT22 -destination 'platform=macOS' -derivedDataPath <scratch> build`
  まで通す（SwiftTerm は 1.18 系に固定。1.19+ はビルド用プラグインで Xcode が全部落ちる）
- **同じリポジトリで別のセッションが動いていることがある**（アプリから起こした new-task 系の claude、本人のテスト）。
  コミットは必ず対象を明示する: `git commit -m … -- <paths>`。索引ごと commit すると、アプリの REVIEW で
  人がステージした分まで巻き込む（`867a5a1` に `even-terminal-*.log` が3本混ざった。追跡を外すかは本人未回答）
- 確認は訊かずに自分で走らせる。報告は日本語で、何を確かめて何を確かめていないかを分けて書く
- git の動きは新しく描かない（InkLoader と決定のドット・Burst の使い回し）

## 確かめ方

```
# p0（SwiftUI 非依存。ファイルを足したら README の行にも足す）
swiftc -parse-as-library Sources/AT22/{Transcript,Cockpit,Structure,Memory,Gate,Launcher,Backend,CodexLauncher,Agents,ACP,Worktree,Snowman,Category,Sparring,Hydra,AgentCatalog,Skills}.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check

# 画像に焼く（ImageRenderer。ポップオーバー・Menu・TextField・ScrollView は写らない）
swift run AT22 --shot /tmp/x.png 1440 900 [--tower] [--workspaces] [--mode talk|files|spar|review|git|settings]
  [--review <worktree>] [--transcript <jsonl>] [--menu root|project|workspace|jump] [--sheet new|delete|pick]
  [--term] [--ripple back:n|fwd:n|side:n] [--approval] [--gate]
```

画面収録の権限は無い。触り心地は本人に見てもらう。

## この日に入ったもの（v11 の A〜J の後）

- 端末（SwiftTerm）・FILES（⌘S の時だけ書くエディタ）・REVIEW（ハンク／一括ステージ・指摘を1通で送る）・
  GIT（記帳→送出→PR、送出はドットと Burst）・SETTINGS・SPARRING（plan モードの claude と話す）
- 鍵: 入力欄・エディタ・端末に焦点がある間は修飾無しの鍵を横取りしない
- 波紋: 管制塔→会話は白い面の手前の青い所全体（モックは「<」の窓だけだが本人の指示）、戻りは画面全体、
  メニューのタブ移動は右の「<」の窓だけを右端から左へ。2色目は淡い青 `#A3A3FF`
- 鶴は実ピクセルで升を丸める（ポイントで丸めると尾が崩れる）。メニューの前に出す
- 重さ: 墨流しの計算を裏の直列キューへ、範囲の for を while に（debug の CPU 70% → 30%）
- **05 PLAN は `PLAN:` / `NOW: n` / `DONE: n` 行で持つ。** Opus / Sonnet 5.5 には TaskCreate が無い（haiku だけ）。
  約束は `--append-system-prompt`（`Sparring.planProtocol`）。番号は最新の PLAN の並びで振り直し、済んだ手順は戻さない
- 壁打ち: 板を UserDefaults（`sparBoards`）に残し、開き直したら transcript から読み直す。繋ぎ直しても plan モード。
  返事の下に札（質問の選択肢／質問が無ければ「次に」の型）。計画は司令塔が積んだのを見てから確定してドット
- 段: 設定で選ぶと**いまの会話にも**効く（LEVEL に書いて次に送る時に繋ぎ直す）。Lv.4/5 は一度だけ確認
- HANDOFF に書く: 無ければ `memory/sessions/HANDOFF.md` を作る
- 門の手順をスキル化: `Resources/Skills/at22-gate`（SKILL.md ＋ gate.sh）。設定 06 Skill で `~/.claude/skills` に入れる
- **Hydra**: 司令塔が返事の ```` ```hydra ```` で別エージェントに並列に任せる → head ごとに采配の門 →
  許可で worktree を作って起こす（Lv.4/5 は自動）→ 最初の報告を司令塔への次のメッセージで返す。マージは人
- **モデルとエフォート（Orca にならう）**: 一覧は CLI から（claude は `list_models` の control_request で API ターン無し、
  grok は `grok models`）。「最新（別名）」「固定の版」、エフォートはモデルの段だけのスライダー（本人の指定。Orca は段ボタン）。
  選択の板は `SumiPicker` 系の自前ポップオーバー（標準 Menu はシステムのゴシックになる）
- **スキルの取り込み（Orca にならう・変換しない）**: `Skills.discover`。入力欄の「／」で `/名前`（codex は `$名前`）、
  設定で共有（`~/.agents/skills` と `~/.grok/skills` にリンク）
- 管制塔: 静かな worktree を畳むのは子が 7 本以上の時だけ。ACTIONS は空きがあれば終わった配下も DONE で並べる

## 確かめていないこと（本人に触ってもらう）

- モデル／エフォートの板（ポップオーバーは撮れない）、スキルの「／」の板
- Hydra の通し（本物の司令塔が囲みを書く → 起こす → 報告が返る）。p0 は読み取り・門の書式・報告文だけ
- 段をいまの会話に効かせた後の承認の出方、HANDOFF の実ファイル
- 壁打ちの持ち越し（今の版で始めた壁打ちが起動し直しで残るか）。消えた例は修正前の版で送られたものだった
- 管制塔で子の worktree を選んで切り替わるか（子が「静か」の1行に隠れていたのが原因と見ているが未確証）
- 端末のタブを足す・閉じる、⌃` が端末の中で効くか

## 残り・後で話す

- Hydra の頭打ち（ラウンド数・同時数・1体の道具回数）は 4体の上限だけ。Droppy は 3ラウンド・8体・160回/35分
- Codex は手元に無いので一覧は初期のまま（`codex app-server` の `model/list` で取れる）
- 会話の途中のモデル切替は繋ぎ直し方式（Orca は `/model` `/effort` を送る）
- 本人の「後で話す」: セットアップスクリプト、眠らせて `--resume`、活動フィード、Issues から worktree、内蔵ブラウザ、定期実行、リモート

## 関係する記憶（~/.claude/projects/-Users-konnotakuto-Swift-PRJS-AT22-Glass-Cockpit/memory/）

`user-builds-in-xcode` / `claude-5-5-has-no-taskcreate` / `at22-sumi-v10-handoff` / `git-actions-reuse-existing-motion` /
`design-mcp-cannot-fetch-binary-assets` / `no-permission-asks`
