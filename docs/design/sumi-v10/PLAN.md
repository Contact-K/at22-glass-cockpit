# AT22 を「Cockpit Sumi v10」に作り替える

## Context

claude.ai/design の `AT22 Cockpit Sumi v10.dc.html`（1440×900、SUMI_ デザインシステム）を実装に落とす。
いまの実装は「5a／Cockpit Mock」の黒い金属筐体（レール＋会話サイドバー＋Canvas 盤面）で、v10 とは構成そのものが違う。

決定済み（ユーザー回答）:
- **今のレイアウトとデザインは全て廃棄。v10 に全て合わせる**（盤面・エゴビュー・金属の質感・サイドバーは消す）
- 動きは**全部入れる。段階を切る**
- 書体は手で `Resources/Fonts/` に置いてもらう。質感（墨流し等）はコードで描く

資料は全部このディレクトリ（`docs/design/sumi-v10/`）にある。`README.md` の表を参照。
v10 の HTML が正。部品（Barcode / DotWipe / DotDecide / InkLoader / Starburst / Suminagashi / WaveLines / RegMark / Ruler / Button / 鶴の Mascot）は `components/*.js` を読んで Swift に写す。

**クラウド（Linux）で実装する場合:** SwiftUI を含む `swift build` と `--shot` は回せない。回せるのは p0（非 SwiftUI のファイルだけをコンパイルする自己チェック）まで。
ビルドしていないものは `docs/HANDOFF-2026-10-01-sumi-v10.md` に**「未ビルド」と明記**し、目で確かめてほしい点を列挙する（8/4 の `HANDOFF-2026-08-04-design5a.md` と同じやり方）。
`Cockpit.swift` など p0 が食うファイルに `import SwiftUI` を足さないこと。作業ブランチは `sumi-v10`、`dev` と `main` には触らない。

## v10 の画面（実装する形）

```
┌ 青帯 56: AT22_ GLASS COCKPIT ✳ ▮▮▮ SESSION/SPEND ……… [GATE 門 Wake W6? 応答する↵] 日付 ＋ ┐
│ 白い五角形（右端が W-394 で尖る）        │ 青＋墨流し（尖りの右）            │
│  鶴   01 // TALK 会話                   │  ┌ 04 // ACTIONS 誰が・何を・どこに ┐│
│ (左下) 大見出し Fraunces 52             │  │ C0 司令塔 model  LV  CTX ▮▮▮ 68% ││
│  M     会話ログ（自分=青い矢羽／C0=2px枠）│  │ ├ W5 ◼ WRITE 書込中 → file      ││ ×最大4
│        門カード（Allow/Rewrite/Reject）  │  └ +2 DONE · QUIET n FILES ────────┘│
│        // ASK C0 [入力] [送る ↵]         │  ┌ 05 // PLAN 計画        17 / 21 ┐│ 5行
└ 青帯 44: 05 // PLAN  [01][02]…[21] 目盛 ───────── 波線 W5 · 書込中  V0.x · Σ ┘
```
タブは 01 WORK / 02 STRUCTURE（書込量で字が育つファイル名の流し組み・ホバーで関係）/ 03 SPARRING（md 編集欄）。
切替は鶴（M）のメニューと `a` `b` `c`。重なり: メニュー、DotWipe＋大見出し、タスク（⇧⌘T）、`// FILE`。

## ファイルの出入り

**消す**: `Chrome.swift` `Texture.swift` `CockpitCanvas.swift` `CockpitLayout.swift` `ConversationSidebar.swift` `TaskList.swift` `_to_delete/`、および p0 の盤面幾何の検査（`agentRowsHangFromTheRail` ほか `CockpitLayout.*` を見ているもの全部）。

**触らない**: `Transcript` `Structure` `Memory` `Gate` `Snowman` `Category` `Launcher` `CodexLauncher` `Backend`。`Cockpit.swift` は足すだけ（下の純関数）。

**書く**（`Sources/AT22/`）:
| ファイル | 中身 |
|---|---|
| `Palette.swift`（全面書き換え） | Sumi トークン: `blue #1212EE` `navy #08085C` `pink #FF3DCC`、light/blue 両スコープの fg/fg2/fg3/line/bg2/bg3、status 色、余白 4–96、角丸 0。`Font` ヘルパ `mono / display / brush / bodyJP`。起動時の書体登録（`CTFontManagerRegisterFontsForURL`） |
| `SumiParts.swift` | RegMark・Barcode・Starburst・Ruler・WaveLines・矢羽/斜め板の `Shape`（18°）・primary/secondary ボタン・`InkLoader`（4×4 墨の四角、v10 が使う状態: write search think reply transfer wait reread handoff build upload duplicate error overload done idle）・`Mascot`（鶴: idle / one / busy で畳む） |
| `SumiMotion.swift` | `DotWipe`（cover→hold→reveal）＋遷移の大見出し、決定のドット（`runDots` の 24fps コマ送り）、メニューのドット成長、`Suminagashi`（Stam stable fluids、格子 96、30Hz、`drop()`） |
| `CockpitView.swift` | 根。青帯2本・五角形・タブ・キー（`a b c m` ⇧⌘T ⇧⌘G Esc ←→ Enter 1–3）・モーダルの重なり順。既存の `CockpitKeys` / Esc の畳み順 / `findCLIs` / `housekeeping` ループはここへ移す |
| `Talk.swift` | 01 TALK: 見出し・ログ・門カード（書換欄、`gateFailed` の表示は残す）・busy 箱・入力欄 |
| `Panels.swift` | 04 ACTIONS・05 PLAN・下帯のティック・タスク/FILE/エージェント/新規セッションのモーダル・02 STRUCTURE・03 SPARRING |
| `SumiMenu.swift` | P5 風メニュー（斜線 → ドット → 項目、選択は白い板＋刃、下層は色が深くなり白帯が横切る、パンくず） |

`Snapshot.swift` は残して新しい根に合わせる（`--shot` に固定時刻を渡して TimelineView 無しで焼けるようにする）。
`AT22App.swift`: `darkAqua` 固定を `aqua` に、`minWidth/minHeight` を 1200×760、既定 1440×900。信号機の 78pt 逃がしは維持。設定ウィンドウ（⌘,）は OS の Form のまま。

## モデルへのつなぎ（既存 API を再利用）

- 上帯: `cockpit.selectedSession` / `spendTotal(session:)` / `cockpit.gates`（最古1件、`issued` からの秒）
- TALK: `cockpit.messages`、送信は `canSend` / `send(_:to:)` / `interrupt`、門は `answer(_:_:revised:)`
- ACTIONS: `snapshot(now:mode:).chips`（busy・門待ちを優先して最大4行）、CTX は `cockpit.reading.growth`、LV は `gateLevel`
- PLAN/ティック/タスク: `allTasks(session:)` と既存の `Cockpit.progressStrip`
- STRUCTURE: `snapshot.cards.flatMap(\.files)` ＋ `cockpit.structure.dependsOn / usedBy`、FILE モーダルは `writeHistory(of:)` `readCounts(of:)` `structure.notes`
- SPARRING: `cockpit.memory` / `saveNote(path:text:expectedText:overwrite:)`（衝突時の扱いは今の `MemoryEditor` のロジックを移す）
- メニューの葉は実データ: Work▸Agents=chips、Sparring▸Memory=ノート一覧、Sparring▸Sessions=`recentSessions`＋「New session」、Settings▸Approval=`setGateLevel`、Models=`setModel`

`Cockpit.swift` に足す純関数（SwiftUI 抜き・p0 から叩く）:
`actionRows(chips:gates:)`（最大4行の選び方と ├│└）、`planWindow(tasks:)`（5行）、`headline(...)`（"W5 writes. W6 waits for you." 型の定型文）、`turnTrail(...)`（`C0 // SEARCH → THINK → REPLY` と参照ファイル）、`writeWeight(added:removed:)`（0–5、流し組みの字の大きさ。`CockpitLayout` の tier 計算を移す）。

v10 のうち入れないもの: 入力欄の上の質問チップ（`ASKS`）— デモを動かすための台本なので実データが無い。

## 段階（各段で `swift build` と p0 を通す）

0. **書体と土台** — `Resources/Fonts/` に `DepartureMono-Regular.otf` `Fraunces[…].ttf` `DotGothic16-Regular.ttf` `AoyagiKouzanT.ttf`。OFL の3つは GitHub（rektdeckard/departure-mono、google/fonts）から自分で取る。青柳だけ手で置いてもらう（無い間は游明朝に落ちて動く）。`Palette.swift` 書き換え。
   読み込み元は `Bundle.main` の `Resources/Fonts` → 無ければ `#filePath` から辿った `Resources/Fonts`（`swift run` 用）。SwiftPM の `resources:` は使わない（手組みの .app と署名が面倒になる）。
1. **静止レイアウト** — 上の全画面・全モーダルを動き無しで組み、モデルにつなぐ。古いファイルを消す。p0 を建て直す。`--shot` を `screenshots/v10*.jpg` と見比べる。
2. **部品の動き** — InkLoader、鶴、点滅（steps(1)）、門カードの選択と揺れ、メニュー一式。
3. **遷移** — DotWipe＋大見出し（WORK/STRUCTURE/SPARRING）、決定のドット（門ボタン → PLAN 行 → ACTIONS 行、返答 → 鶴から枠へ）。
4. **墨流し** — 右の青い面。ACTIONS の行の高さへ 2.6 秒ごとに墨を落とす（書込=青、それ以外=ピンク）。窓が隠れたら止める。
   `// ponytail: CPU の配列で 96 格子。重ければ Metal へ`
5. **片付け** — `package.sh` に `Resources/Fonts` のコピーを足す、README（自己チェック行・画面の説明）、`docs/HANDOFF-2026-10-01-sumi-v10.md`、メモリ更新。

## 検証

- `swift build`、README の p0 自己チェック行（ファイル一覧は消した分を直す）＋実 transcript を渡したリプレイ
- `swift run AT22 --shot <scratchpad>/a.png 1440 900 --transcript <jsonl> --gate` を `--mode work|structure|memory` で3枚焼き、v10 のスクリーンショットと並べて読む
- `swift run AT22` で実機: M でメニュー（↑↓→←）、`a/b/c` で DotWipe、門に Allow/Rewrite/Reject（verdict ファイルが書かれること）、⇧⌘T、ファイルを押して `// FILE`、送信、壁打ちの保存。動きは `screencapture` の連写で確認
- アイドル時の CPU（墨流しとメニューが止まっている間に回り続けていないこと）
