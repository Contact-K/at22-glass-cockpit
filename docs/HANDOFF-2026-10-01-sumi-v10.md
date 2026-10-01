# 引き継ぎ 2026-10-01 — Sumi v10 に作り替えた

`docs/design/sumi-v10/PLAN.md` の段0〜5を全部入れた。旧筐体（黒い金属・レール・会話サイドバー・Canvas 盤面・エゴビュー）は消して、
`AT22 Cockpit Sumi v10.dc.html` の画面・メニュー・モーダル・動きに置き換えてある。

## 0. まず最初に

**`swift build`：未ビルド。** このセッションは Linux（Ubuntu 24.04）で、SwiftUI が無い。
SwiftUI 側の新しいファイル（下の表の7本）は**一度もコンパイラの型検査を通っていない**。
やったのは `swiftc -parse`（構文だけ。全ファイル通過）と、読み直しによる点検だけ。最初の macOS ビルドでは数件〜十数件のエラーが出る前提で見てほしい。

```
swift build
<README の自己チェック行>
swift run AT22 --shot /tmp/a.png 1440 900 --gate
swift run AT22 --shot /tmp/b.png 1440 900 --mode structure
swift run AT22 --shot /tmp/c.png 1440 900 --mode memory
```

**p0：通った（Linux・Swift 6.0.3）。** Docker Hub の `swift:6.0-noble` の層を取って chroot で回した。

```
$ swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift \
    Sources/AT22/Structure.swift Sources/AT22/Category.swift Sources/AT22/Memory.swift \
    Sources/AT22/Gate.swift Sources/AT22/Launcher.swift Sources/AT22/Snowman.swift \
    Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
p0: savesOnlyInsideMemory は Linux では飛ばす（replaceItemAt が未実装）
p0: 実 transcript のリプレイはスキップ（引数にパスかセッションディレクトリを渡すと実行）
p0: ok
```

- Linux の swift-corelibs-foundation は `FileManager.replaceItemAt` で既存ファイルを置換できない（「ファイルが無い」を返す。小さな再現で確認）。
  これを通る2か所（`savesOnlyInsideMemory` 全体と、`gateVerdictWritesOnlyInsideMemory` の「承認モードの上書き」2行）だけ `#if os(Linux)` で飛ばした。**macOS では今まで通り全部走る。**
- 実 transcript のリプレイは手元に transcript が無いので回していない。Mac で `/tmp/p0check <jsonl>` を1回。

## 1. 作ったもの

| ファイル | 中身 |
|---|---|
| `Palette.swift`（全面書き換え） | Sumi のトークン（青 #1212EE・深紺・ピンク、light/blue の2スコープ、状態色、余白 4–96、18°）。書体ヘルパ `mono / display / brush / bodyJP`、起動時の書体登録 |
| `SumiParts.swift` | `SumiClock`（時計。`--shot` の固定時刻と、窓が隠れた時の停止をここ1か所で扱う）、斜め板 `Plate`、`RegMark` `Barcode` `Starburst` `Ruler` `WaveLines`、`SumiButton`、`InkLoader`（v10 の MOTIF と SDF の混ぜ方をそのまま移植）、鶴の `Mascot` |
| `SumiMotion.swift` | `DotWipeLayer` と `WipeTitle`（遷移）、`FlightLayer`（決定のドット）、`MenuDots`（メニューの面）、`InkTank`＋`Suminagashi`（墨流し） |
| `CockpitView.swift` | 根。画面だけの状態を持つ `Stage`（遷移・メニュー・モーダル・門・ドット）、鍵、重なり順、`housekeeping` の周回、`findCLIs`、滴下の周回、地（五角形・青・白線） |
| `Talk.swift` | 01 TALK。見出し・会話ログ・門のカード（書換欄・`gateFailed`）・処理中の箱・入力欄。未選択の時は過去の回の一覧 |
| `Panels.swift` | 上帯・鶴のボタン・04 ACTIONS・05 PLAN・下帯・モーダル（Tasks / FILE / AGENT / Sessions / New session / Keys）・02 STRUCTURE（流し組み）・03 SPARRING（md 編集） |
| `SumiMenu.swift` | メニュー。葉は実データ |

`Cockpit.swift` に足した純関数（SwiftUI 抜き・p0 で検査）: `actionRows(chips:gates:now:)` `planWindow(tasks:size:)` `headline(rows:hasSession:)` `turnTrail(agent:read:thought:wrote:)` `writeWeight(added:removed:)`。
`CockpitLayout` から `plainLine` `hotThreshold`（旧 `hugeThreshold`）`maxReadTicks` を移した（呼び出し元と p0 の検査ごと）。
`actionRows` は計画表の引数に `now` を1つ足してある（門の待ち秒を行に出すため）。

書体: `Resources/Fonts/` に Departure Mono（rektdeckard/departure-mono の `public/assets/`、リポジトリの LICENSE は MIT）・Fraunces 可変・DotGothic16（google/fonts、OFL）を置いた。
**青柳衡山T は未配置**（`AoyagiKouzanT.ttf` を置けば次の起動から効く。無い間は游明朝 → ヒラギノ明朝 → システムの serif）。
登録は `Palette.registerFonts()`（.app の `Contents/Resources/Fonts` → `#filePath` から辿った `Resources/Fonts`）。`package.sh` にコピーを足した。

既存の振る舞いの行き先:

| 旧 | 新 |
|---|---|
| 会話サイドバーの履歴・新規 | メニュー Sparring ▸ Sessions（過去の回＋All sessions＋New session）、Sessions / New session のモーダル、未選択時の一覧 |
| 送る／止める（⌘Return） | 入力欄の「送る ↵」が処理中は「止める ■」。Return でも送る |
| GatePanel（⇧⌘G 許可・書換・却下・gateFailed） | 門のカード（←→ Enter 1–3、⇧⌘G はそのまま） |
| MemoryEditor（衝突時の読み直す／上書き、未保存で離れない） | 03 SPARRING。未保存の間は a/b/c とメニューで画面を離れない |
| TaskPanel（⇧⌘T） | 06 Tasks（全件・畳まない） |
| FileHistory / AgentDetail | // FILE / // AGENT |
| LevelKnob（Lv.4/5 は確認） | ACTIONS の `LV.n` メニュー、Settings ▸ Approval（同じ確認の alert） |
| モデル切替 | Settings ▸ Models（走っている間は切り替えない） |
| 「非アクティブを消す」「クリア」 | Work ▸ Clear idle / Clear |
| 「思考も出す」 | Settings ▸ Thinking（`showThinking` を反転） |
| 設定ウィンドウ（⌘,） | そのまま（OS の Form）。`maxReadTicks` は `Cockpit` へ、色は新 Palette へ付け替え |

## 2. v10 から外したもの・推し量ったもの

- **入力欄の上の質問チップ（`ASKS`）は入れていない**（PLAN の決定どおり。デモの台本で実データが無い）
- **門の題は `Wake G1?`**（`Talk.swift:414`、`Panels.swift:63`）。v10 の `W6` は起こす相手の短縮IDだが、門の時点ではまだ居ないエージェントなので、門の通し番号 `G1` にした。相手の名前（`to`）はカードの頭とメタ行に出る
- **ACTIONS の行の選び方**（`Cockpit.swift` の `actionRows`）: 門待ち（古い順）→ 動いている（ファイルを触っている者が先）→ 起きているだけ、で4行。右端の数字は門なら待ち秒、エージェントなら `N calls`（v10 の `+42 −7` はエージェント単位の行数を持っていないので出せない）
- **返答の頭の `SEARCH → THINK → WRITE`**（`Talk.swift:93`）は、直前の人の発言から返答までに「最後に触られた」ファイルと thinking の有無から決める。同じファイルを何度も触ると最後の1回でしか数えない
- **処理中の箱**（`Talk.swift:538`）は `THINK → REPLY` の2段だけ。stdout の途中の文（`streaming`）が来ていれば REPLY。12 升は経過時間で回しているだけで、進み具合ではない
- **PLAN の門の印**（v10 の #18 `W6 · 門`）は出していない。タスクと門を結ぶ情報が transcript に無い
- **下帯の升**は 42pt で収まる数だけ（1440 幅で 21）。それを超えるタスクは `planWindow` の窓で切る（`Panels.swift:382`）
- **STRUCTURE** は先頭 160 本まで（`Panels.swift:977`）。見出しの `Thirteen files, three ties.` は「表示中の本数」と「表示中のファイル同士の依存の本数」。Structure の葉（Sources / Docs / Config / Ties / Hot spots）は指示どおり `FileCategory`・依存のあるもの・上位2%で絞る（＋ All で外す）
- **門に答えた行**（`GATE // G1 → ALLOWED`）はこのセッションの間だけ画面に残す（答えはファイルに書くだけで、transcript に戻ってこない）
- **鶴の形の墨流し**（メニュー背後）は、鶴の絵（pitch 64）をそのままマスクにした。v10 の canvas → dataURL の手順は踏んでいない
- **波線**（下帯）は何かが動いている時だけ流す（`SumiParts.swift:204`）。v10 は常時。何も起きていない間まで 24fps で回さないため
- **墨流しの格子**: release は 96、`swift run`（debug）は 48（`CockpitView.swift:91-98`）。Linux 実測で最適化なしは1歩 24ms（30Hz で1コアの7割）、`-O` は 1.5ms
- **メニューの Preferences** は `NSApp.sendAction("showSettingsWindow:")` で開く（`SumiMenu.swift:129`）。静的関数から `openSettings` に届かないため。macOS 15 で効かなければ ⌘, を使う
- **v10 の `steps()` の遷移**は全部 `steps(_:_:)`（jump-start）で近似。`transition: left 120ms steps(3)`（メニュー項目の位置の移動）は付けず、瞬時に移る
- フルスクリーンの v10 は 1440×900 固定だが、ここでは右端から 376pt に右の列、五角形の尖りは `W-394`、左の会話は `min(660, W-780)` 幅、PLAN は窓が低いと上へ詰める（`RightColumn`）

## 3. Mac で目で確かめてほしいこと

焼いて見られるもの（`--shot` 3枚を `docs/design/sumi-v10/screenshot-v10b.jpg` と並べて）:

1. 五角形の白線と青い線が尖り（`W-394, H/2`）で合っているか、墨流しの窓の左辺がその尖りに沿って折れているか
2. 書体が効いているか（Departure Mono の大文字ラベル、Fraunces の 52pt 見出し、DotGothic16 の和文）。効いていなければ `Palette.registerFonts` の探し先
3. ACTIONS の行の4列（枝・ID・ローダー・本文）が揃っているか、CTX の 20 升
4. 下帯の升（済・いま・これから）と目盛り、`05 // PLAN` の幅 118pt
5. 門を立てた1枚（`--gate`）で、上帯の札・門のカード・ACTIONS の WAIT 行の3つが同時に出るか
6. 会話ログが焼いた画像で末尾6件になっているか（ScrollView の代わり）

実機でしか分からないもの:

7. `m` でメニュー: 斜線 → ドット → 項目の順に出るか。↑↓ で刃が伸び直すか、→ で白帯が横切って下層へ、← で戻るか、閉じる時に逆順で縮むか。鶴の形の墨流しが右下に出るか
8. `a` `b` `c` で DotWipe（押した所から波紋）と大見出しが出て、1.86 秒で戻るか。壁打ちに未保存がある間は動かないこと
9. 門で ←→ と 1–3、Enter。**Allow / Rewrite / Reject で `memory/gate/<id>.verdict` が書かれること**。書けなかった時にカードに赤字が残ること。押した後にドットがボタン → PLAN のいまの行 → ACTIONS の先頭へ渡るか
10. 返答が届いた時に鶴から返答の枠へドットが渡るか（位置がずれていたら `sumiAnchor` の測り方）
11. 処理中に鶴が四角に畳まれて InkLoader になり、終わって 0.6 秒後に脚が伸びるか。門待ちで片脚立ちになるか
12. ⇧⌘T、行やファイル名を押して `// FILE`、Esc の畳み順（FILE → AGENT → New → Sessions → Keys → Tasks → 書換欄）
13. 送る（Return / ⌘Return）と止める、履歴からの会話選び、新しい回の起動、壁打ちの保存と衝突（読み直す／上書き）
14. ACTIONS の行の高さに 2.6 秒ごとに墨が落ちるか（書込は青、他はピンク）。ポインタで水が揺れるか
15. **アイドル時の CPU**。窓を隠すと（他の窓で覆う・最小化）墨流しとローダーが止まること。墨流し以外にも InkLoader（ACTIONS 4行・鶴・PLAN の済）が常時 24fps で回っているので、重ければここを `sumiPaused` か fps で絞る
16. 信号機が青帯の上で `AT22_` に被っていないか（左 78pt 空け）

## 4. 段ごとのコミット

段0（書体と Palette）→ 段1（静止レイアウト・モデル・p0）→ 段2（部品の動き・メニュー）→ 段3・4（遷移・ドット・墨流し）→ 段5（package.sh・README・この文書）。
ファイル同士が参照し合うので、**途中のコミットは単独ではビルドできない**（最後のコミットで揃う）。
「メモリ更新」（PLAN の段5）はこのセッションから届く置き場が無いので行っていない。
