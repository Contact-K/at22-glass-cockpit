# AT22 Glass Cockpit

Claude Code が今どのファイルを読み書きしていて、サブエージェントが何体どう動いているかを見るための macOS アプリ。

バイブコーディングでは、開発の速度に人間の理解が追いつかなくなる。AT22 は Claude Code が残す transcript を読んで、エージェントの動きとコードの変化を1枚の画面に出す。

## 既定では読むだけ

AT22 は初期状態では **読み取るだけ** で、

- ファイルを書き換えない（**例外は記憶DBだけ**。後述）
- Claude Code の動作に一切干渉しない（フックも設定も触らない）
- ネットワークに接続しない。何も外部に送らない
- **セッションを起こさない**（連携は既定オフ。後述）

他人の作業ログを扱うソフトなので、ここは仕様として固定している。

**記憶DBだけは書く。**壁打ちモードで人間が手を入れた分を `~/.claude/projects/<プロジェクト>/memory/` 配下へ保存する。書き込みはこの1箇所に限られ、置き場の外へは弾く。コードにも transcript にも触らない。門（後述）の答えも同じ置き場・同じガードを通る。

**連携を有効にすると、`claude` を起こす。**設定で明示的に有効化した時だけ、AT22 は Claude Code のセッションを起動できるようになる。その時も：

- **AT22 は認証情報を一切持たない。**API キーも OAuth トークンも保存しない。起こすのは**あなたが既にログイン済みの `claude` コマンド**で、通信するのはそのプロセスであって AT22 ではない
- 起こす時のセッションIDは AT22 が採番する（`--session-id`）。transcript の在り処が確定するので、起こした先をそのまま画面で追える
- `claude` の場所はログインシェルに訊いて突き止める。見つからなければ起動のUI自体が出ない
- 人間の承認なしにファイルを書き換える段（Lv.4 / Lv.5）を選ぶ時は、一度だけ確認が入る

第三者依存はここでも増えない（`Foundation.Process` だけ）。

読む先は2つ。`~/.claude/projects/` 配下の transcript と、**稼働中セッションのプロジェクトディレクトリのソース**（依存グラフを作るため。読む拡張子とスキップするディレクトリは `Sources/AT22/Structure.swift` に列挙してある）。どちらも読むだけで、開いて中身を出すことはしない。

## 見えるもの

画面は **Sumi v10**（`docs/design/sumi-v10/`）。青 `#1212EE` × 白の2色に、差し色のピンク `#FF3DCC` を小さく1色だけ。角丸も影も無い。

```
┌ 青帯: AT22_ GLASS COCKPIT ✳ ▮▮▮ SESSION / SPEND ……… [GATE 門 Wake W6? 応答する↵] 日付 ＋ ┐
│ 白い五角形（右端が尖る）                │ 青い面＋墨流し                       │
│  鶴   01 // TALK 会話                   │  ┌ 04 // ACTIONS 誰が・何を・どこに ┐ │
│ (左下) 大見出し                         │  │ C0 司令塔 model  LV  CTX ▮▮▮ 68% │ │
│  M     会話ログ（自分＝青い矢羽／C0＝枠）│  │ ├ W5 ◼ WRITE 書込中 → file      │ │ ×最大4
│        門のカード（Allow/Rewrite/Reject）│  └ +2 DONE · QUIET n FILES ────────┘ │
│        // ASK C0 [入力] [送る ↵]         │  ┌ 05 // PLAN 計画        17 / 21 ┐ │ 5行
└ 青帯: 05 // PLAN [01][02]…[21] 目盛 ───────────── 波線 W5 · 書込中   V0.1.0 · Σ ┘
```

画面は3つ。**鶴（左下）を押すか `M`** でメニュー、**`a` `b` `c`** で直接移る（ドットが波紋に広がって覆い、大見出しが出てから次の画面を見せる）。

| キー | 効き |
|---|---|
| `M` | メニュー（↑↓ 選ぶ・→ / Enter 開く・← 戻る・Esc / M 閉じる） |
| `a` `b` `c` | 01 WORK / 02 STRUCTURE / 03 SPARRING。壁打ちに未保存があると移らない |
| ⇧⌘T | 06 Tasks（下帯のティックを押しても同じ） |
| ⇧⌘G | 門を許可。←→ で選んで Enter、または 1–3 |
| ⌘Return / Return | 送る。生成中は「止める」に変わる |
| Esc | 手前から順に畳む（板 → 書換欄） |

**01 TALK 会話**

司令塔とのやり取り。人の発言は右寄せの青い矢羽、司令塔の返答は 2px の枠で、枠の頭に**そのターンの足跡**（`C0 // READ → WRITE → REPLY`）と参照したファイルが付く。サブエージェントを呼んだ行（`CALL // Explore → …`）と、門に答えた印（`GATE // W6 → ALLOWED`）も時刻順に混ざる。

大見出しは「いま誰が動いていて、誰が待っているか」の定型文（`W5 writes. W6 waits for you.`）。処理中は破線の箱に段の並び（SEARCH → WRITE …）と経過秒が出る。

セッションを選ぶまでは、ここが**セッションの選び口**（実行中・履歴・Codex）。上帯の十字か `＋ NEW SESSION` で新しいセッションを起こす（連携が有効な時だけ。無効なら設定への口を出す）。

**止まった指示（門）**

司令塔がサブエージェントを起こす直前に人間が口を挟むための仕組み。止まっている間は上帯に札（`GATE 門 · 1 件止まっています / Wake W6?`）が立ち、会話の末尾に門のカードが出る。**Allow（許可して起動）／ Rewrite（書き換えて発行）／ Reject（却下）** で答える。答えると押したボタンがドットに崩れて PLAN の行へ渡る。

**答えを書けなかった時は必ずカードに出す。**黙って消すと司令塔は待ち続ける。

**止めているのは AT22 ではない。**AT22 は Claude Code に干渉しないので、司令塔が自分から待ちに入り、AT22 が置いた答えで抜ける。

```
司令塔:  memory/gate/<id>.md を書く → until [ -f <id>.verdict ]; do sleep 2; done → 従う
AT22 :  門を見せる → 人間が答える → memory/gate/<id>.verdict を書く
```

書き込みは記憶DBと同じ置き場・同じガードを通る。AT22 が書ける範囲は増えない。

**どこで止めるかは承認モードで決まる**（メニューの Settings ▸ Approval、ACTIONS の見出しに `LV.3 気にかけてる` と出る）。

| Lv | 名前 | 止める指示 | 起こす時の `--permission-mode` |
|---|---|---|---|
| 1 | 壁打ち | —（指示を出さない） | `plan` |
| 2 | 隣で見てる | 全部 | `acceptEdits` |
| 3 | 気にかけてる | 高リスクだけ | `acceptEdits` |
| 4 | 任せてる | 止めない | `bypassPermissions` |
| 5 | 留守番 | 止めない（無人） | `bypassPermissions` ＋ `--bg` |

Lv.2 と Lv.3 の `--permission-mode` が同じなのは意図的で、**段の違いは門が持つ**。値は `memory/gate/LEVEL` に書かれ、**司令塔も同じファイルを読む**ので、アプリの設定ではなくファイルが正。Lv.4 / Lv.5 を選ぶ時は一度だけ確認が入る。

**04 ACTIONS 誰が・何を・どこに**

司令塔（C0）の見出し（モデル・承認レベル・文脈）と、**最大4行**。門で待っているもの → 動いているもの → 止まっているがまだ終わっていないもの、の順に選び、指揮系統の順（C0 の行 `│`、配下 `├`、最後 `└`）に並べる。終わったものは件数（`+2 DONE`）に畳む。行の左の墨の四角（InkLoader）がいまの動作（書込・読取・考え中・待機）を描き、門で待つ行はピンクの四角が点滅する。行を押すと、触っているファイルの `// FILE` か、エージェントの板が開く。

右の青い面には墨流しが動いていて、**2.6 秒ごとに ACTIONS の行の高さへ墨が落ちる**（書込＝青、それ以外＝ピンク）。

呼び名は C0（司令塔）と W1, W2 …（配下）。番号は ID の並びで振る（働くたびに番号が入れ替わらないように）。

**文脈（CTX）** … 長引いたセッションで推論が鈍るのは時間ではなく**文脈の量**で起きるので、`message.usage` の実測（`input` ＋ `cache_read` ＋ `cache_creation`）で 20 升を埋める。自動圧縮（`compact_boundary`）で減る。85% を超えると赤くなり、入力欄の枠も赤くなる。窓の大きさはモデル名からは決められない（1M 版でも `message.model` は `claude-opus-5` としか書かれない）ので、200k を超えて動いていること自体を 1M 版の証拠にする。切れ目は `Sources/AT22/Snowman.swift`。**これはハルシネーションそのものの検知ではない。**

**消費（SPEND）** … 上帯の `SPEND 1.2M`。入力 × 1.0 + キャッシュ書き × 1.25 + キャッシュ読み × 0.1 + 出力 × 5.0 の重みで積んだ代理指標（重みは公式の価格比。レートリミットの実際の式は非公開）。エージェントの板には「そのセッションの消費の何割を食ったか」が出る。分母は**そのセッションの全履歴**（畳んだ分・消した分も含む）。

**フラグ（⚑）** … 同じエージェントが同じファイルを3回以上読み、一度も書いていない時に ACTIONS の行のファイル名に付く。実 transcript 2478組の分布から決めた値（当てはまるのは全体の1.4%）。しきい値は **⌘,（設定）** で 2〜6 回に変えられる。

**05 PLAN 計画**

計画段階で積まれたタスク（`TaskCreate` / `TaskUpdate`）の**5行の窓**。最初の未完了から始め、進行中の行だけ青く反転する。下帯のティックは同じ並びを最大21升で出し、進行中は白い斜め板、済みは薄い面、これからは破線。

**06 Tasks（⇧⌘T）** … 計画したすべてのタスクを見返す板。こちらは**完了も畳まない**。絞り込みは ALL / TODO / NOW / DONE。読み取り専用で、編集は Claude Code 側が担う。

**02 STRUCTURE 構造**

ファイル名の流し組み。**字の大きさが書込量**（0–5 の6段、16 + 4×段 pt）、書込量の上位 2% は二重下線。名前の左肩の刻印が役割（実・検・ノ・設・資・中黒）。**ホバーで関係（使っている／使われている）だけが浮かび、無関係は沈む。**押すと `// FILE` の板に、説明・定義した型の数・被参照の数・書き込み履歴・読んだ相手・依存が出る。メニューの Structure ▸ Files / Ties / Hot spots で絞り込める。

依存は `import` では引けない（Swift の単一モジュールにはファイル間の import が無い）ので、**どのファイルが宣言した名前を、どのファイルが使っているか**で引いている。説明は「ファイル名と同じ名前の型に付いた `///`」か「import 直後の本物のファイルヘッダ」。無ければ宣言している型に落とす。

**03 SPARRING 壁打ち**

記憶DB（`~/.claude/projects/<プロジェクト>/memory/`）の1本を **md のまま編集**する。上の札でノートを選び、SAVE（⌘S）で保存する。

保存は**一時ファイルに書いてから置き換え、直後に読み返して確かめる**。人間とエージェントが同じファイルを書くので、壊れた状態を残さない。編集中にエージェントが書き換えていたら上書きせずに止め、**読み直すか上書きするか**を人に返す。書きかけがある間は別のノートにも別の画面にも移らない。

```
memory/
  PROJECT.md              前提・計画全体の仕様
  sessions/
    HANDOFF.md            セッション全体のメモ（引き継ぎ用）
    <セッションID>/
      *.md                セッションごとのメモ
```

書式は Claude Code が既に書いている frontmatter（`name` / `description` / `metadata.type` / `originSessionId`）をそのまま使う。

**メニュー（M）**

白い斜線が引かれ、線から離れる順にドットが育って青い面になり、項目が線に沿って並ぶ。選んだ項目だけ白い板と刃。下層へ潜ると面の色が深くなり、白帯が横切る間に差し替わる。葉は全部実データ: Work ▸ Agents（エージェント）/ Gates / Tasks / Thinking（思考も出す）/ Clear idle / Clear、Structure ▸ Files / Ties / Hot spots、Sparring ▸ Handoff / Memory（ノート一覧）/ Sessions（New session ＋ 実行中・履歴・Codex）、Settings ▸ Approval / Models / Keys / Preferences。

**思考の本文は残らない。**実測で全12セッション458件すべて `thinking` は空で、`signature` だけが記録されている。出るのは「いつ考えたか」だけなので、既定では畳んである（Work ▸ Thinking で出す）。

## 動作要件

- **macOS 15 以降**
- **Apple Silicon**（Intel Mac には対応しない）

> **macOS 15 / 16 の実機では未検証。** 開発と動作確認は macOS 26 で行っている。
> macOS 15 を対象にビルドが通ること、および使用している API がすべて macOS 15 以下で導入されたものであることは確認しているが、実機で動かしてはいない。
> 15 や 16 で問題が出た場合は Issue で報告してほしい。必要なら最低バージョンを引き上げる。

## インストール

[Releases](../../releases) から `.dmg` をダウンロードし、マウントして `AT22.app` を `Applications` にドラッグする。

## ソースからビルド

```
swift build -c release --arch arm64
./.build/arm64-apple-macosx/release/AT22
```

依存パッケージは無い。Swift 6 と Command Line Tools だけで通る（Xcode は不要）。

## 開発

自己チェック（SwiftUI 非依存・ターゲット外）:

```
swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift \
  Sources/AT22/Structure.swift Sources/AT22/Category.swift Sources/AT22/Memory.swift \
  Sources/AT22/Gate.swift Sources/AT22/Launcher.swift Sources/AT22/Snowman.swift \
  Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift \
  p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
```

Foundation だけで組んであるので Linux でも通る（`FileManager.replaceItemAt` が Linux で常に失敗するので、
既存ノートの上書きを確かめる2箇所だけは `#if os(macOS)` で外してある）。

**SwiftUI 非依存のファイルを足したら、この行にも足すこと。** 足し忘れると
`cannot find type ... in scope` で落ちる（`Backend.swift` と `CodexLauncher.swift` で一度やった）。

見え方を画像に焼いて確かめる:

```
swift run AT22 --shot /tmp/cockpit.png 1440 900                 # 01 WORK
swift run AT22 --shot /tmp/x.png --transcript <path.jsonl> --gate # 実データ＋門を1つ立てた状態
swift run AT22 --shot /tmp/x.png --mode structure                 # 02 STRUCTURE（memory で 03 SPARRING）
```

`--shot` は窓を開かずに PNG を1枚吐いて終わる。`ImageRenderer` は `TimelineView` / `ScrollView` /
`TextField` の中身を組まないので、焼く時だけ**時刻を固定**し、会話のログは素の VStack に、
入力欄は文字だけに差し替えてある。動き（墨流し・ドット・InkLoader・鶴）は1コマしか写らない。

書体は `Resources/Fonts/` から起動時に登録する（`swift run` はソースの場所から辿り、配布物は
`AT22.app/Contents/Resources/Fonts`。`package.sh` がコピーする）。**青柳衡山T（`AoyagiKouzanT.ttf`）は
同梱していない**。持っている人が `Resources/Fonts/` に置けば、節番号の横の小さな和文ラベルに効く。
無い間は游明朝に落ちる。

実 transcript を渡すとリプレイして検査する:

```
/tmp/p0check ~/.claude/projects/<プロジェクト>/<セッションUUID>
```

配布物の作成:

```
./package.sh 0.1.0 --dry-run   # 証明書が無くても組み立てまで確認できる
./package.sh 0.1.0             # 署名・公証・DMG まで
```

## ライセンス

MIT
