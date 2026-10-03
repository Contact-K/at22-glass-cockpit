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
- 10 SETTINGS 02 Agents を Orca（`AgentsPane` / `AgentCatalogRow`）にならって組み直した: 入っている／入っていない に分け「↻ 探し直す」、
  行ごとに 既定にする・有効/無効（`disabledAgents`、選ぶ口に出さない）・Docs/Install ↗（インストールは走らせない）・▸ で場所の上書き。
  ログインは Terminal を開かず CLI の公式ログインを裏で起こし、出力の URL を「ブラウザで続ける ↗」に出す（hermes setup は対話式なので Terminal）。
  Orca の Args / Env の上書きは入れていない（起こす経路を全部触るため。要る時に Launcher.Config に足す）
- 01 TALK の見出しに「会話 ▾」: いまの worktree の会話（動いているもの＋過去5本）をその場で切り替える
- 10 SETTINGS 02 を「Link 連携」として2段に: 左でプロバイダ（使う／ほかのプロバイダ）、右に起こし方・使う/足す・既定・Docs・ログイン・モデル・場所。
  プロバイダに Gemini（`gemini --acp`）・Qwen Code（`qwen --acp`）・Goose（`goose acp`）・OpenCode（`opencode acp`）・
  Copilot（`copilot --acp`）・Kimi（`kimi acp`）を足した（起こし方は agentclientprotocol/registry の agent.json の実物）。
  初めからある4つ以外は「＋ 選べるようにする」（`addedAgents`）まで選ぶ口に出さない。モデルとログインは各 CLI 自身に任せる
- Link（1層目）は入っていて使うものだけを並べ、一番下に「＋ プロバイダを足す」。押すと設定の2層目「SETTINGS › LINK · Add a provider.」
  （メニューからは着かない。設定のタブを離れると1層目に戻る）。2層目は全プロバイダに Install/Docs ↗ と「＋ 足す」
- 2026-10-03 夜（本人の指示）:
  - 段は4つ（Lv.1 隣で見てる / Lv.2 気にかけてる / Lv.3 任せてる / Lv.4 留守番）。壁打ち（plan）は段の外のトグル。値は変えていない
  - タブから SPARRING と MEMORY を外した。壁打ちは会話画面の「□ 壁打ち」、記憶DB は 02 FILES の「ファイル｜記憶DB」。
    SparScreen.swift（壁打ちの板・暫定プラン・決定事項）はどこからも開かれなくなった（消すかは本人と相談）
  - 01 TALK: 見出しに題・段の切り替え（Lv.3/4 は確かめてから）・壁打ちのトグル。入力欄の中の左にモデルとエフォートの札を2つ。
    「/」（codex は「$」）を打つとスキルの候補を入力欄の上に出す（Return で1つ目を補う）。右列に 01 HISTORY（いまの worktree の会話・＋ 新しい会話）
  - Link の2層目は インストール済み／未導入（検出だけで決める）。OpenClaw（`openclaw acp`、Gateway は別に起こす）を足した
- 文脈 85%（Snowman の warning）での引き継ぎ: 司令塔に `sessions/each/<ID>.md` へ引き継ぎ（決めたこと・分かったこと・残り・次の一手、```state stage: handoff）を書かせ、
  ターンが終わったら同じ worktree・エージェント・モデル・段で新しい会話を起こしてそのノートから続ける（古い会話は閉じない、二度は引き継がない）。
  Lv.3/4 は自動、Lv.1/2 は会話画面の「引き継いで移る ▸」から。壁打ち中は書けないので何もしない
- 訊かれた時の窓（`Ask.swift`）: 質問（AskUserQuestion）は選択肢＋その他で答え、入力に `answers` を足して許可。計画（ExitPlanMode）は「この計画で進める／まだ」。
  質問と計画はどの画面でも窓、道具の承認は会話画面では門のカード・それ以外の画面では窓
- モデルの札: 新しい会話の時は板の上にプロバイダの並び（使えるものだけ）。会話が始まった後は変えられない旨を出す
- エフォートの札: high で縁が回り、xhigh で桃色に滲み、max で四角い火の粉（動きを減らす設定では止める）
- 会話のフリーズ: 毎秒の描き直しで、人の発言の行ごとに全メッセージを走り、Markdown を毎回解釈していた → 1回だけ求める・解釈を覚える。
  遡っている間は新しい発言で引き戻さず、「最新へ ↓」を出す
- 会話を切り替えると発言が二重: transcript を追う側が起動時に直近24時間分を頭から流し込んでいるのに、開き直しで丸ごと読み直していた。
  追う側がファイルごとに読み始めた位置（`TranscriptWatcher.startOffsets`）を持ち、開き直しはその手前だけを読む
- エフォートの効果を3段に: high＝縁が回る・滲む・火の粉（前の max）、xhigh＝縁が太く速く・地に墨・二重の滲み・火の粉が倍、max＝さらに四角い波紋・尾を引く火の粉・札が息をする
- 右列の履歴は並びを固定（初めて見えた順、新しい会話だけ上へ）。動いているもの順のままだと裏の状態で入れ替わり、選択の青が動いて見えた
- 2026-10-04: 保留にしていたエージェント周りを実装（リモート SSH・起こし方の上書き・Codex app-server・約束を全員に・眠らせて再開・定期実行・
  途中のモデル切替・Hydra の上限・内蔵ブラウザ・Issues から worktree・活動フィード・セットアップスクリプト）。
  Hydra は本物の claude（haiku）で通しを確かめた（`hydra-check.swift`）。報告が司令塔に届かない不具合を見つけて直した
- 08 Remote に「経由」（SSH ／ Tailscale SSH）と ssh の追加オプション（踏み台 -J・ポートなど）。Tailscale は `tailscale status --json` から相手を選べる。
  経由とオプションは作業場所の文字列（`ssh://相手/パス?via=tailscale&opt=…`）に乗せる。WireGuard などの VPN は繋がっていれば素の ssh で届く
- 新規ワークスペースの 01 Repository の一番下に「＋ 新しいプロジェクト」: リモートをクローン／ローカルで新しく（init と最初のコミット、GitHub にも）／既存のフォルダ。
  クローン・init・gh は手元のログインシェルで走らせる（認証も名前の設定も本人のもの）
