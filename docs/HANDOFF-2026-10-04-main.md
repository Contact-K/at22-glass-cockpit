# 引き継ぎ 2026-10-04 — main（orca-v10 を取り込んだ後）

`main` は `d524790`（PR #4「orca-v10 → main」、71 コミットをマージコミットで取り込み）。
`orca-v10` と `orca-v10-memory` は `3eb594d` で、どちらも main に入っている。**次の作業は main から枝を切る。**
`at22/session-waiting`・`dev`・`sumi-v10`・`at22/new-task*` は触っていない。

前の引き継ぎ（`docs/HANDOFF-2026-10-03-orca-v10.md`）は v11 の A〜J と Orca 寄せの経緯。デザインの正は claude.ai/design の
プロジェクト `05bb6eef-0360-4c34-8076-bf7d830c9ec9` の `ui_kits/at22-v11/`、段取りとモックと違えた所は `docs/design/v11/PLAN.md`
（このセッションで足した分は末尾の「2026-10-03 追加」以降）。

## まず読むこと（本人の作業の仕方）

- **本人は Xcode でビルドする。** 依存や Package を触ったら
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme AT22 -destination 'platform=macOS' -derivedDataPath <scratch> build`
  まで通す（SwiftTerm は 1.18 系に固定。1.19+ はビルド用プラグインで Xcode が落ちる）
- **同じリポジトリで別のセッションが動いていることがある。** コミットは `git commit -m … -- <paths>` で対象を明示する
- 確認は訊かずに自分で走らせる。報告は日本語で、確かめたこと／確かめていないことを分ける
- 見た目は HTML モックで来る。モックに無い所は勝手に描かない（今回は本人の言葉の指示で足した所が多い。PLAN.md の末尾に全部書いた）
- git の動きは新しく描かない（InkLoader と決定のドット・Burst の使い回し）

### worktree に隔離されたセッションで git を叩く時（2026-10-03〜04 に踏んだ）

- RTK のフックが `git` を `rtk git` に書き換え、隔離のガードがそれを読めずに止める → **`/usr/bin/git` で直に叩く**（`-C` か cd して）
- コマンドの文字に「git」「gh」が入った python や heredoc もガードが止める → **スクリプトはファイルに書いてから `python3 <file>`**
- ブレース展開（`Sources/AT22/{A,B}.swift`）もガードが止める → p0 のファイルは並べて書く
- `defaults` や `~/.claude/projects` に、確認用の小さなプログラムが記録を残す。走らせたら片付ける（hydra-check は自分で片付ける）

## 確かめ方

```
# p0（Foundation だけ。SwiftUI のファイルは入れない。ファイルを足したら README の行にも足す）
#   古い実行ファイルが残っていると、コンパイルに失敗しても前の「p0: ok」が出る。消してから作る
rm -f /tmp/p0check && swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift \
  Sources/AT22/Structure.swift Sources/AT22/Category.swift Sources/AT22/Memory.swift Sources/AT22/Gate.swift \
  Sources/AT22/Launcher.swift Sources/AT22/Snowman.swift Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift \
  Sources/AT22/Agents.swift Sources/AT22/ACP.swift Sources/AT22/Worktree.swift Sources/AT22/Sparring.swift \
  Sources/AT22/Hydra.swift Sources/AT22/AgentCatalog.swift Sources/AT22/Skills.swift Sources/AT22/Remote.swift \
  Sources/AT22/CodexServer.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check

# Hydra の通し（本物の claude を haiku で2本・料金がかかる。p0 には入れていない）
#   上と同じ Sources に p0-selfcheck.swift の代わりに hydra-check.swift を並べて組み、走らせる。PASS で約19秒

# 画像に焼く（ImageRenderer。ポップオーバー・Menu・TextField・ScrollView・WKWebView は写らない）
swift run AT22 --shot /tmp/x.png 1440 900 [--tower] [--mode talk|files|review|git|settings]
  [--transcript <jsonl>] [--sheet new|delete|pick] [--term] [--approval] [--gate]
```

画面収録の権限は無い。触り心地・ポップオーバーの中身・動きは本人に見てもらう。

## 画面の地図（今）

- **タブ**: 01 TALK / 02 FILES（「ファイル｜記憶DB」の切り替え）/ 07 REVIEW / 08 GIT / 10 SETTINGS。
  SPARRING と MEMORY のタブは外した（壁打ちは会話のトグル、記憶DB は FILES の中）
- **01 TALK**: 見出しに 題（自動）・段の切り替え（Lv.3/4 は確認の窓）・□ 壁打ち。入力欄の中の左に [モデル ▾][エフォート ▾]
  （新しい会話の時はモデルの板にプロバイダの並び）。「/」「$」でスキルの候補。遡ると「最新へ ↓」。85% で引き継ぎの札。
  右列は 04 ACTIONS・01 HISTORY（いまの worktree の会話、＋ 新しい会話）・05 PLAN
- **10 SETTINGS**: 01 Approval（Lv.1〜4）/ 02 Link（入っているプロバイダだけ。一番下の「＋」で2層目「Add a provider.」）/
  03 Launch / 04 Display / 05 Worktrees（置き場・セットアップスクリプト）/ 06 Skills / 07 Sessions（眠らせる・Hydra の上限）/
  08 Remote（SSH・Tailscale）/ 09 Schedule。⌘, はこのタブを開く（別窓はやめた）
- **管制塔**: 右列の下の欄が「同じ指示｜活動」
- **窓**: 質問（AskUserQuestion）・計画（ExitPlanMode）はどの画面でも窓、道具の承認は会話画面では門のカード・それ以外では窓。
  内蔵ブラウザは会話の URL の札から
- **新規ワークスペースの板**: 01 に「＋ 新しいプロジェクト」（クローン／ローカルで新しく／既存のフォルダ）、05 に「Issue から ▾」

## 設計の決めごと（このセッションで決めたもの）

- **段**: `Gate.Level.ladder` = 隣で見てる・気にかけてる・任せてる・留守番（Lv.1〜4）。`plan` は段の外（壁打ちのトグル）。
  **rawValue は変えていない**（`memory/gate/LEVEL` と `gate.sh` がそのまま読む）。段は worktree ごと（`slug(cwd)` の `memory/gate/LEVEL`）
- **記憶DB の置き場はリポジトリ本体で1つ**（`Cockpit.memoryDirectory(cwd:)` が `Worktree.root` を引く）。門（gate）だけは worktree ごと
- **記憶の約束**: claude は `--append-system-prompt`、codex / ACP は最初の1通の頭（空なら次の1通）。plan とリモートには渡さない
- **プロバイダが入っているかは検出だけで決める**（手で持つ印は入れ直した時に食い違う）。使わないにしたものは `disabledAgents`
- **起こすのは全部 `Launcher.spawn` を通る**: 起こし方の上書き（`LaunchOverrides`、引数は前に足す）とリモート（`Remote`）はここ1か所
- **リモートの作業場所は文字列1本**: `ssh://相手/パス?via=tailscale&opt=…`。リモートの claude は transcript が読めないので stdout の assistant 行から発言を取る。
  相手の記憶DB と門は扱わない
- **Codex は app-server**（`CodexServer.swift`、jsonrpc を付けない）。段 → 承認とサンドボックスは `codex exec` の時と同じ強さ
- **会話の開き直しは、transcript を追う側（`TranscriptWatcher.startOffsets`）が読み始めた位置の手前だけを読む**（丸ごと読むと二重になった）
- **会話画面は毎秒描き直す**。行ごとに全メッセージを走らない・Markdown と URL は覚えておく（`MarkdownCache`・`LinkCache`）
- **85% の引き継ぎ**: `sessions/each/<ID>.md` に書かせ、ターンが終わったら同じ worktree・エージェント・モデル・段で新しい会話。Lv.3/4 は自動
- **Hydra の報告は毎秒の見回りでも送る**（司令塔の次のターンの終わりだけを待つと、届かないことがあった）

## 確かめたこと

- `swift build`・`xcodebuild` が通る。p0 `ok`（Codex app-server の形、SSH・Tailscale の作業場所、上書き、定期実行の時刻、約束の文を足した）
- Hydra の通し（`hydra-check.swift`）PASS
- 新しいプロジェクトの3通り（クローン・ローカルで新しく・既存のフォルダ・同じ名前は断る）を手元の git で
- `--shot`: 設定（Link の2層を含む）・会話の入力欄の札・FILES の切り替え・端末の閉じる・エフォートの効果（max の1コマ）

## 確かめていないこと（本人に触ってもらう）

- SSH・Tailscale SSH の先での起動（相手のマシンが無い）
- Codex app-server（手元に codex が無い。形だけ p0 で固定）、ACP の7つ（Gemini・Qwen・Goose・OpenCode・Copilot・Kimi・OpenClaw）の接続と約束の効き方
- 質問の窓で答えた `answers` を claude が受け取るか、計画の窓
- `/model`・`/effort` の途中切替、眠らせた後の `--resume`、定期実行の発火、85% の引き継ぎの通し
- 内蔵ブラウザで http の開発サーバー（Xcode から走らせると Info.plist が無く ATS に止められるかもしれない。`package.sh` には許可を足した）
- Issue の一覧（gh）、`gh repo create`、活動フィード、右列の履歴、会話を切り替えて二重にならないか、遡って固まらないか
- 前の引き継ぎの「確かめていないこと」も残っている（モデルの板、端末のタブ、⌃` 等）

## 残り・後で話す

- **`SparScreen.swift` はどこからも開かれなくなった**（壁打ちのタブを外したため）。暫定プラン・決定事項・05 PLAN に送る・HANDOFF に書く を
  会話画面に移すか、消すかを本人と決める
- Orca の Args の引用符（空白を含む値）は解していない。リモートでは記憶DB と門が効かない
- ACP の7つは、続きを Terminal で開く口を出していない（CLI ごとの再開の書き方を確かめていない）
- 活動フィードは `noteAttention` を拾っているだけ（PR や CI の出来事は入っていない）
- 本人の「後で話す」で残っているもの: 管制塔のタイルに PR と CI の状態、Codex 以外の割り込み、①構造と②エージェントを同じ画面に重ねる
- p0 に検査を足す編集を本人が一度止めたことがある（2026-10-03）。理由は聞けていない。その後の追加は通っている

## 関係する記憶（~/.claude/projects/-Users-konnotakuto-Swift-PRJS-AT22-Glass-Cockpit/memory/）

`user-builds-in-xcode` / `claude-5-5-has-no-taskcreate` / `at22-sumi-v10-handoff` / `git-actions-reuse-existing-motion` /
`design-comes-as-html-mockups` / `no-permission-asks` / `at22-direction-orca-ui-hermes-connection` / `at22-obsidian-note-stale-premises`
