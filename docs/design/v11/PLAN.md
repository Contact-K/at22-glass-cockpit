# Sumi v11 — 実装の段取り

正は claude.ai/design のプロジェクト `05bb6eef-0360-4c34-8076-bf7d830c9ec9`（SUMI_ デザインシステム）の
`ui_kits/at22-v11/`。`index.html`（既定の Tweaks）・`HANDOFF.md`（採否の記録）・`V11*.jsx` 9本。
DesignSync の `get_file` で読める（認可が切れていたら `/design-login`）。**採否は HANDOFF.md が正**。

既定の Tweaks（`V11_DEFAULTS`）: 端末=下から引き出す / ⌘J=斜線の世界 / 静かな worktree=畳む / 新規=斜線の板（段式）/
STRUCTURE=FILES と統合 / メニュー=線からドット / REVIEW=1ファイル。

git 操作の動きは**新しく描かない**（InkLoader と決定のドットの使い回し。メモリ git-actions-reuse-existing-motion）。
ただし v11 のモックが描いている PUSH の合図（ピンクの波紋 Burst・鶴の片足）はモックの指定なので入れる。

## 画面の骨格（v10 から変わる所）

- **2つの姿**: 管制塔（青が全面・左に白い三角「01 TALK ▸」）と会話（v10 の白い五角形「<」）。
  境界は XC=1046p, XT=146+754p で補間（p=0 管制塔 / 1 会話）。切替は白い面が 0.5s・24fps で横に滑る＋右側のドット波紋。
  戻る口は会話側の「◂ 00 TOWER」の切り欠き・Esc・⌘0
- **上帯**: `AT22_ GLASS COCKPIT ✳` ＋ 05 PLAN のティック帯（840）＋ 日付 ＋ ＋（新規）。セッション/門は撤去
- **下帯**: 左＝端末の帯（最終行・押すと引き出す・⌃`）、右＝門待ち（鶴 wait＋GATE·n/道具）＋「一個前 → 現在地」
- **右列**: 2枠（top76 h404 / top494 h346）は全タブ共通。枠は動かさず中身だけ差し替え
- **タブ**: 01 TALK / 02 FILES（構造とファイル）/ 03 SPARRING / 07 REVIEW / 08 GIT / 10 SETTINGS
- **メニュー**: 白い面にドットが育つ（線から）。階層 root（プロジェクト）→ proj（worktree）→ ws（タブ）。パンくず
- **⌘J**: 斜線の世界の一覧（あなた待ち→作業中→完了→待機）、⌘1–6 / ⌘P クイックオープン / ⌘0 管制塔⇄会話

## 段（各段で swift build 警告0・p0・--shot）

| 段 | 中身 | 主なファイル |
|---|---|---|
| A | 骨格: 2つの姿と切替、上帯・下帯、右列の枠、タブの差し替え、キー | `CockpitView.swift` |
| B | 管制塔: 木（純関数 `Cockpit.towerLanes` を p0 で）、ノード・枝・競走の枠・静かな列、⋯メニュー、右列（門の窓・同じ指示） | `Tower.swift`（新規）・`Cockpit.swift` |
| C | メニュー（白い面・3階層）・⌘J・⌘1–6 | `SumiMenu.swift` |
| D | 新規（斜線の6段）・削除・採る の板 | `Tower.swift` |
| E | TALK の承認カード（bash/diff/acp/gate・JSON・書換・他の件）・畳んだ形 | `Talk.swift` |
| F | REVIEW（指摘を溜めて1通・ハンクのステージ）・右列 CHANGES/NOTES | `Review.swift`（新規）・`Worktree.swift` |
| G | GIT（記帳→送出→依頼・REMOTE/COMMITS）・PR の状態 | `Review.swift`・`Worktree.swift` |
| H | FILES（エディタ・木と関係・検索・⌘P・衝突） | `Files.swift`（新規） |
| I | 端末（SwiftTerm・下から ∧ の波紋で引き出す・2分割） | `Terminal.swift`（新規）・`Package.swift` |
| J | SPARRING（4つの型・暫定プラン・決定事項）・SETTINGS | `SparScreen.swift`・`Sparring.swift`・`Settings.swift` |

**2026-10-03 時点で A〜J はすべて `orca-v10` に載った**（動き: DotWipe・TabRipple・Pull・Burst・決定のドット）。
モックと違えたところ:

- 置き場（10 SETTINGS の 03 Worktrees）は表示だけ。各リポジトリの `.claude/worktrees` で固定（Worktree.location）
- 端末の2分割は「いまのタブと隣」。モックは先頭の2本
- SPARRING の返事は claude（plan モード）の末尾の `STEP:` / `DECIDE:` / `ASK:` の行から拾う（モックは台本）
- 05 PLAN に送る＝司令塔に TaskCreate で積んでもらう1通（PLAN 自体は読み取り専用のまま）
- 旧 03 SPARRING の記憶DBエディタは外した。記憶DBへの書き込みは「HANDOFF に書く」だけ

モックにあってデータが無いものは、作らずに HANDOFF に書く（例: タスク番号は transcript に無い → 最初の指示の一致で束ねる）。

**2026-10-03 追加（本人の指示・モック無し）**（枝 `orca-v10-memory`）:

- 段の選択に Lv.1 壁打ちを戻した（v11 で4段の直書きにした時に落ちていた）。10 SETTINGS と新規の板の両方
- **04 MEMORY 記憶** のタブを足した（鍵は k。m はメニュー）。上の「記憶DBエディタは外した」は撤回ではなく、編集はせず一覧＋清書だけ
  - 貯める: AT22 が起こす・繋ぐ claude（plan 以外）に `Memory.protocolText` を渡し、節目ごとに `memory/sessions/each/<ID>.md` と `SHARED.md` に書いてもらう
  - 置き場はリポジトリ本体の `~/.claude/projects/<slug>/memory`（worktree ごとに分けない。Claude Code の自動記憶と同じ所）
  - 清書: claude を1本起こし PROJECT.md だけを書かせる（`Memory.composeTools`）。門の段も選択中の会話も動かさない
- 01 TALK: 見出しに「履歴 ▴」（一覧に戻る）。一覧は「＋ 新しい会話」（いまの worktree）と「＋ 新しいワークスペース」に分けた
- 03 SPARRING: 「＋ 新しい壁打ち」と「過去の壁打ち ▾」。過去の板は `sparShelf`（UserDefaults）に20枚まで、選ぶと今の板と入れ替え
- 10 SETTINGS を再編し、⌘, の別窓（ThresholdSettings）を取り込んで設定を1か所にした。⌘, はこのタブを開く。
  行は 01 Approval（Lv.1〜5）/ 02 Agents（既定＋各 CLI の場所・ログイン、場所の欄は見つからない時か手で書いた時だけ）/
  03 Launch（起こすかどうか）/ 04 Skills / 05 Display（参照回数の閾値を含む）/ 06 Worktrees
- 途中だったものを仕上げた: 作れなかったワークスペースの「再試行」（タイルの ⋯、同じ分岐元・エージェント・指示・段で作り直す）／
  置き場の設定（10 SETTINGS 05 Worktrees。空ならリポジトリの中、書けば `<根>/<リポジトリ名>/<名前>`）／
  会話の題（起こした時点で最初の指示から付ける。grok・hermes も台帳から。`[壁打ち…]` の頭は落とす）／
  壁打ちの「HANDOFF に書く」も本体の記憶DBへ。設定の並びは Approval / Agents / Launch / Display / Worktrees / Skills
