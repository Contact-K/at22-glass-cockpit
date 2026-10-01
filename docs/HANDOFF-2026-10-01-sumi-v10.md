# 引き継ぎ 2026-10-01 — Sumi v10 を実装に落とした

`docs/design/sumi-v10/AT22 Cockpit Sumi v10.dc.html` を、`PLAN.md` の段 0–5 の順に実装した。
今の筐体（黒い金属・レール・会話サイドバー・Canvas 盤面・エゴビュー）は全部消し、v10 の画面に置き換えた。

## 0. 最初に読むこと

**未ビルド。** このセッションは Linux（クラウド）で、`swift build` も `--shot` も回していない。
SwiftUI を含むファイルは一度も本物のコンパイラを通っていない。**最初にやることは Mac での `swift build`。**

確かめられたのは次の4つだけ:

| 何を | 結果 |
|---|---|
| p0（README の自己チェック行、Swift 6.1.3 / Linux） | **`p0: ok`**（下に出力） |
| SwiftUI の**代役**モジュールでの型検査（Swift 6 モード） | エラー 0。ただし代役の署名は私の推測なので、本物の SDK との食い違いは拾えていない（§5） |
| InkLoader の絵（14 状態 × q を 201 点）を JS の元と突き合わせ | **全部一致** |
| 墨流しの1コマの重さ（同じコードを Linux で計測） | release 2.5ms / debug 56ms（96 格子）。debug は 48 格子に落とした（§3） |

```
$ swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift \
    Sources/AT22/Structure.swift Sources/AT22/Category.swift Sources/AT22/Memory.swift \
    Sources/AT22/Gate.swift Sources/AT22/Launcher.swift Sources/AT22/Snowman.swift \
    Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift \
    p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
p0: 実 transcript のリプレイはスキップ（引数にパスかセッションディレクトリを渡すと実行）
p0: ok
```

（警告 4 件はどれも元からある「戻り値を使っていない」の類）

### 並行していたセッション

作業中に、**別のセッション（`session_01XLvC5gR5ZPP3eGgiytPAhE`）が同じ作業の段0を `origin/sumi-v10` に押していた**
（`5e049b1 Sumi v10 段0: 書体と Palette の土台`）。同じ予約が二重に走ったのだと思う。

- 書体とライセンスのファイルはバイト単位で同じだった
- `Palette.swift` は API が違う（あちらは `Palette.mono(_:)`、こちらは `Font.mono(_:)` / `Palette.Light` / `Palette.Blue`）。
  第1〜4段の画面がこちらの API を使っているので、**こちらの版を残して merge した**（`df71c4e`）。履歴は書き換えていない
- あちらのセッションがこの後も押してくると、`sumi-v10` で衝突する。**どちらを残すかは持ち主が決めてほしい**

---

## 1. 入れたもの

| 段 | 中身 | 主なファイル |
|---|---|---|
| 0 | 書体（Departure Mono / Fraunces 可変 / DotGothic16）、Sumi のトークン、起動時の書体登録、Cockpit の純関数 | `Resources/Fonts/` `Palette.swift` `Cockpit.swift` |
| 1 | 静止レイアウト一式とモデルへのつなぎ。古い6ファイルを削除。p0 を建て直し | `CockpitView.swift` `Talk.swift` `Panels.swift` `Snapshot.swift` `AT22App.swift` `p0-selfcheck.swift` |
| 2 | InkLoader（15 状態）、鶴（瞬き・つつく・羽づくろい・片足・処理中は畳んで InkLoader）、点滅、門のカードの選択と揺れ、メニュー一式 | `SumiParts.swift` `SumiMenu.swift` |
| 3 | DotWipe ＋ 遷移の大見出し、決定のドット（門 → PLAN → ACTIONS、返答 → 鶴から枠へ）、メニューのドット成長 | `SumiMotion.swift` |
| 4 | 墨流し（Stam Stable Fluids・96 格子・30Hz）。2.6 秒ごとに ACTIONS の行の高さへ墨を落とす | `SumiMotion.swift` |
| 5 | `package.sh` に書体のコピー、README の画面の説明と自己チェック行 | `package.sh` `README.md` |

### 1-1. `Cockpit.swift` に足したもの（足しただけ・SwiftUI 抜き）

`actionRows(chips:gates:cells:now:limit:)` / `planWindow(tasks:size:)` / `headline(rows:)` /
`turnTrail(_:replied:)` / `writeWeight(added:removed:)` / `agentLabels(_:)` / `gateLabel(chips:index:)`、
それと盤面から移した `maxReadTicks` / `plainLine(_:)`。型は `ActionRow` と `PlanWindow` の2つ。
p0 に1関数1検査ずつ足してある（`writeWeightStepsAtFixedLines` ほか6本）。

**計画の関数一覧から外れたもの:** `agentLabels` / `gateLabel` / `plainLine` / `maxReadTicks`。
前の2つは「W5 / W6」の呼び名を ACTIONS・見出し・門のカードで揃えるため、後の2つは消した `CockpitLayout` の
置き場の付け替え（`AT22App` の設定画面と門の本文が使う）。

### 1-2. 残した振る舞い

- セッションの選択と履歴 … セッションを選ぶまでは 01 TALK がセッションの選び口になる（`Talk.swift` `SessionPicker`）。
  メニューの Sparring ▸ Sessions からも選べる
- 新規セッション … 上帯の十字、選び口の `＋ NEW SESSION`、Sessions ▸ New session → 板（`Panels.swift` `NewSessionModal`）。
  連携が無効・CLI が無い時は理由と設定への口を出す。Lv.4/5 は確認が入る
- 送る／止める … 入力欄の右のボタン（Return / ⌘Return）。生成中は「止める ■」に変わる。失敗は欄の上に出す
- 門 … Allow / Rewrite / Reject（⇧⌘G、←→ Enter、1–3）。**書けなかった時はカードに赤で出す（`gateFailed`）**
- 記憶DBの保存 … 一時ファイル → 置換 → 読み返し。衝突したら「読み直す／上書き」。書きかけがある間はノートも画面も移らない
- タスク一覧（⇧⌘T・絞り込み4種・ホバーで詳細）、エージェントの板（指示・内訳・触ったファイル）、`// FILE` の板
- 設定画面（⌘,）は OS の Form のまま。`CockpitLayout.maxReadTicks` → `Cockpit.maxReadTicks`、色は Sumi へ付け替え
- 「非アクティブを消す」「クリア」「思考も出す」は Work の葉へ移した。モデルの選び直しは Settings ▸ Models、承認レベルは Settings ▸ Approval

---

## 2. v10 のうち入れていない・推測で埋めたもの

| どこ | 何を | なぜ／どう決めたか |
|---|---|---|
| `Talk.swift` | 入力欄の上の質問チップ（`ASKS`） | 計画どおり入れていない（デモの台本で実データが無い）。その分、入力欄を 34pt 下げた |
| `SumiMenu.swift:191` | メニュー背後の**鶴の形に切り抜いた墨流し** | 既定どおり、無地の深紺の鶴（pitch 64）で済ませた |
| `Cockpit.swift:2318` | 門の見出し `Wake W6?` の **W6** | 門で待っている相手はまだ起きていないので台帳に居ない。「配下の数＋1」を先回りして当てている |
| `Cockpit.swift:2308` | W1, W2 … の番号 | ID の並びで振る（働くたびに入れ替わらないように）。**起きた順ではない** |
| `Cockpit.swift:2394` | 大見出しの定型文 | `W5 writes.` / `W5 and W6 are both at work.` / `N agents are at work.` / `W6 waits for you.` / 何も無ければ `All quiet. Ask C0.` |
| `Cockpit.swift:2291` | 書込量の重み 0–5 | 旧 tier の切れ目 1 / 10 / 100 に、300 / 1000 を足した（経験則） |
| `Talk.swift` `entries` | 返答の枠の頭 `C0 // SEARCH → THINK → REPLY` | v10 は台本の段。実データには段が無いので、**その前の人の発言からの司令塔の読み書き**で `READ / WRITE` を並べた |
| `Talk.swift:469` `BusyBox` | 処理中の箱の段と 12 コマのゲージ | 段は同じく読み書きから。何段で終わるか分からないので、ゲージは 1 秒 1 コマで回すだけ |
| `CockpitView.swift:350–363` | 決定のドットの行き先 | 門は PLAN のどの行にも結びついていないので、**進行中の行（無ければ先頭）→ ACTIONS の最後の行**へ飛ばす |
| `CockpitView.swift:588` | 会話に挟む `GATE // W6 → ALLOWED` | 画面だけの記録（再起動で消える）。v10 が足していた「#1 許可して起動」の人の発言は**作っていない**（transcript に無い言葉を捏造しないため） |
| `CockpitView.swift:311` | 墨を落とす x | 五角形の尖り（W-394）に沿った縁と ACTIONS の左端の中ほど。v10 は tan18° で縁を近似していて尖りの位置と少しずれていたので、実際の多角形で取った |
| `Panels.swift:53` | ACTIONS の下端 | `+2 DONE` だけ（v10 の `· W4 R1` の名前の列は出していない） |
| `Panels.swift:199` | PLAN の下端 | `N DONE · 読み取り専用…`（v10 の `#1–16` は連番の時しか言えないので数だけ） |
| `Panels.swift:258` | 下帯右の `V0.10 · Σ` | バンドルの版（`V0.1.0 · Σ`）。`swift run` だと `VDEV · Σ` |
| `Panels.swift:762` | 02 STRUCTURE に並べる数 | 最大 160 件（400 件並べると小さい字が読めない） |
| `Panels.swift:813` | 二重下線（hot） | 書込量の上位 2%（最低1件） |
| `SumiMenu.swift` `tree` | メニューの葉 | 計画どおり実データ。足したもの: Work ▸ Tasks / Thinking / Clear idle / Clear、Files ▸ All / Tests、Settings ▸ Preferences（⌘,）。Keys の葉は説明だけ（押しても何もしない） |
| `Panels.swift` `AgentModal` `NewSessionModal` | `// AGENT` `07 // New session` の板 | v10 に無い。06 Tasks と同じ板の形で作った |
| `SumiParts.swift:603` | 鶴が脚を伸ばし直す時刻 | 元は InkLoader の1周を待つ。ここは処理が終わった瞬間から伸ばす |
| `CockpitView.swift:137` | 窓の幅が 1440 でない時 | 右の列（540）は右端に固定、会話の欄の幅は `W − 780`（最小 380）、下帯のティック数は幅で決まる |

---

## 3. 意図的な割り切り（`// ponytail:` を付けた所）

- `SumiMotion.swift` 墨流し … CPU の配列で 96 格子。重ければ Metal へ。**デバッグビルドだけ 48 格子・温め 10 コマ**
  （96 格子だと debug の1コマが 56ms、初回の温めで 2 秒止まる）
- `SumiMenu.swift:60` メニューの一覧の葉は 12 件で切る
- `Talk.swift:42` 会話に流すのは直近 200 件
- `Palette.swift:111` 書体のファミリー名は `nonisolated(unsafe)`（起動時に1回書くだけ）
- `Cockpit.swift:2307` W 番号は起きた順ではない

---

## 4. Mac で目で確かめてほしいこと

まずビルドと3枚の画像:

```
swift build
swift run AT22 --shot /tmp/w.png 1440 900 --transcript <path.jsonl> --gate
swift run AT22 --shot /tmp/s.png 1440 900 --transcript <path.jsonl> --mode structure
swift run AT22 --shot /tmp/m.png 1440 900 --transcript <path.jsonl> --mode memory
```

`docs/design/sumi-v10/screenshot-v10b.jpg` と HTML を並べて読む。そのあと実機（`swift run AT22`）で:

1. **書体が効いているか。** 見出しが Fraunces、ラベルが Departure Mono、和文が DotGothic16 か。
   `swift run` は `#filePath` から `Resources/Fonts` を辿る。どれか効いていなければ標準エラーに何も出ないまま代わりの書体になるので、目で見るしかない
2. **Fraunces の光学サイズ。** 可変書体の `opsz` 軸が字の大きさに追従しているか（132pt の遷移の見出しが細すぎ／太すぎないか）
3. **起動直後にキーが効くか。** `a` `b` `c` `m` は根に焦点がある時しか来ない。入力欄が最初に焦点を取ると、文字がそちらへ入ってしまう
4. **五角形と墨流し。** 尖りが W-394・中央の高さにあるか、尖りの左に墨がはみ出していないか、白と青の 3px の縁
5. **墨流しの動きと重さ。** 墨がゆっくり対流し、2.6 秒ごとに ACTIONS の行の高さへ墨が落ちるか（書込＝青、それ以外＝ピンク）。
   アクティビティモニタで、**窓を隠した時・メニューを開ききった時に CPU が落ちるか**
6. **メニュー（M）。** 斜線 → ドットが線から離れる順に育つ → 項目が線に沿って並ぶ。↑↓→← と Enter、パンくず、BACK、
   下層で面が深くなり白帯が横切るか。閉じる時にドットが遠い方から縮むか
7. **DotWipe。** `a` / `b` / `c` で波紋 → 大見出し（1文字ずつ下から迫り上がる）→ 差し替え → 縮んで次が見えるか
8. **門。** `--gate` で焼いた絵と、実際に `memory/gate/<id>.md` を置いた時。Allow / Rewrite / Reject で
   **`<id>.verdict` が書かれること**、書けない置き場で赤い文が出ること、⇧⌘G、←→ Enter、1–3、ボタンからドットが PLAN へ飛ぶこと
9. **InkLoader と鶴。** ACTIONS の行の墨の四角が状態の絵に崩れて戻るか、鶴が処理中に畳まれて InkLoader になり、終わると脚を伸ばすか
10. **送る／止める・セッションの選び口・新規セッションの板・⇧⌘T・行を押して `// FILE`・壁打ちの保存（衝突も）**
11. **ScrollView の自動送り。** 新しい発言・門のカード・処理中の箱が出た時に、ログが下端まで送られるか
12. **窓を 1200×760 まで縮めた時。** ACTIONS と PLAN が重ならないか、会話の欄と五角形の尖りが重ならないか

---

## 5. 代役の型検査で拾えないもの（ビルドで最初に出そうな所）

型検査は本物の SDK ではなく、私が書いた代役の `SwiftUI` モジュールに対して通しただけ。食い違いが出るとしたらここ:

- `onPreferenceChange` の閉包の隔離（Xcode 16 で `@Sendable` になった）… `CockpitView.swift` で `[book]` を捕まえて
  `MainActor.assumeIsolated` の中で書いている。`@MainActor` の閉包なら警告で済むはず
- 自作の `Shape` の `path(in:)` … 全部 `nonisolated` にしてある
- `Path { p in … }.trim(from:to:).stroke(…)`、`GraphicsContext.blendMode = .clear`（鶴の目の抜き）
- `TimelineView(.animation(minimumInterval:paused:))` を `Ticker` で包んで、`--shot` の時は時刻を直接渡している
- `Layout`（`FlowLayout`）のベースライン揃え

---

## 6. 触った時に連動するところ

- `RectBook` の鍵（`act:<i>` `act:last` `plan:<i>` `plan:current` `gateBtn:<0|1|2|rw>` `crane` `c0last`）…
  ドットの出発点・行き先と墨を落とす高さはこの名前で引く。部品の側の `.reportRect` と揃えること
- `Wipe.cover / hold / reveal` … タブの差し替え（`swapAt`）と大見出しの引き（`outAt`）がこの3つから決まる
- `MenuDots.lineX / tan18` … メニューの斜線、ドットの成長、項目の並び（`310 + y × tan18°`）が全部この線に乗る
- `InkTank.defaultRes` … 落とす墨の半径は格子の割合なので、格子を変えても見た目の大きさは変わらない
- 書体のファミリー名は**ファイルの中の名前**を読む（`SumiFonts.register`）。ファイル名の頭（`DepartureMono` `Fraunces`
  `AoyagiKouzan` `DotGothic16`）で役割を決めるので、**青柳衡山T は `AoyagiKouzan…` で始まる名前で置くこと**

---

## 7. 読み直しで直したもの（別の目で全ファイルを読ませた結果）

- 会話が 200 件に達すると自動で下へ送られなくなっていた → 最後の項目の ID と `streaming` の長さで送る（`Talk.swift`）
- 壁打ちで書きかけのまま、エージェントが新しい HANDOFF を足すと欄が別ノートへ移って**書きかけが消えた** →
  書き始めた時点でそのノートに留める（`Panels.swift` `SparringScreen`）。メニューからセッションを替える操作も、書きかけがある間は受けない
- 新規セッションの板の「起こす」と入力欄の「送る」が両方 ⌘Return だった → 板が開いている間は「送る」を止める
- 02 STRUCTURE の ScrollView が下帯の下まで伸びていた → 高さを渡した
- 門に答えた直後に Enter をもう一度押すと、出たばかりの次の門を見ないまま許可していた → 次の門が出てから 0.6 秒は鍵を受けない
- **アイドル時の CPU** … 窓が隠れている間・メニューが面を覆いきった間は、画面の時計（InkLoader・鶴・点滅・墨流し）を全部止める
  （`EnvironmentValues.motionPaused`）。PLAN の済みの行の `done` は描き終わったら止まる
- セッションを替えただけで鶴からドットが飛んでいた／メニューを開いた1コマだけ項目が見えていた／一覧が縮むと選択が外へはみ出した
- 空の入力欄で Return を押すと古いエラーが出ていた
- 書換欄で Esc を押すと畳む（`onExitCommand`）。メニューは ↑↓ の長押しで送れる（`.repeat`）
- Sessions に「All sessions」（セッションの選び口へ戻る）を足した。前は一度選ぶと一覧を全部見る口が無かった

## 8. まだ残っている（前の画面から落ちたもの・v10 との差）

| 何 | 前はどこに | いま |
|---|---|---|
| 入力欄の複数行（`axis: .vertical`, 1–5 行） | `ConversationSidebar.swift:290` | 1行。Return で送るため |
| 書換欄の複数行（TextEditor） | `Chrome.swift` GatePanel | 1行の TextField |
| 記憶ノートの「表示／編集」の切替と書式リボン | `CockpitCanvas.swift` MemoryEditor | 常に md の編集欄（v10 の形） |
| 未保存の時にタブが沈む印 | `Chrome.swift` TabBar | 移れないだけで、印は出ない |
| 入力欄で Esc を押して根へ焦点を戻す | — | 戻らない。`a b c m` を使うには欄の外を押す |
| メニューの項目の位置・大きさの 120ms steps(3) の動き | v10 | 一気に移る |
| 上帯の門の札を WORK で押した時にログを門まで送る | v10 `jumpGate` | 何もしない（カードは常にログの末尾に出ている） |

ホバーで選択が移ると項目の大きさが変わるので、カーソルの下で隣と行き来する（ちらつく）かもしれない。実機で見てほしい。
