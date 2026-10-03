# AT22 Glass Cockpit

Claude Code が今どのファイルを読み書きしていて、サブエージェントが何体どう動いているかを見るための macOS アプリ。

バイブコーディングでは、開発の速度に人間の理解が追いつかなくなる。AT22 は Claude Code が残す transcript を読んで、エージェントの動きとコードの変化を1枚の画面に出す。

## 既定では読むだけ

AT22 は初期状態では **読み取るだけ** で、

- ファイルを書き換えない（**例外は記憶DB、人が押した時のワークスペースの作成・削除とステージ・記帳・送出、人が ⌘S を押した時のエディタの保存だけ**。後述）
- Claude Code の動作に一切干渉しない（フックも設定も触らない）
- ネットワークに接続しない。何も外部に送らない（送出と PR は押した時に git / gh が自分の認証で送る）
- **セッションを起こさない**（連携は既定オフ。後述）

他人の作業ログを扱うソフトなので、ここは仕様として固定している。

**記憶DBだけは書く。**壁打ちで決めたことを「HANDOFF に書く」で足した分を `~/.claude/projects/<プロジェクト>/memory/` 配下へ保存する。書き込みはこの1箇所に限られ、置き場の外へは弾く。コードにも transcript にも触らない。門（後述）の答えも同じ置き場・同じガードを通る。

**ワークスペース（git worktree）は、人が押した時だけ作る・消す。**管制塔の ＋ で、そのリポジトリに `<repo>/.claude/worktrees/<名前>` を `git worktree add` で作り（枝は `at22/<名前>`、基点はコミットで固定）、そこでエージェントを起こす。git の書き込みは押した時だけ：

- 作る時、`.claude/worktrees/` を本体の `git status` から隠すために `.git/info/exclude` に1行足す（既に無視されていれば何もしない）
- 消す前に未コミットの変更を並べて見せる。**変更がある時は確認を取ってから**でないと消さない。リポジトリ本体と、`git worktree list` に無い場所はどうやっても消さない
- 枝は `git branch -d` で消す。マージされていなければ git が断るので、残して伝える（中身を見てから消せる）
- ソースを書くのはエージェントと、FILES で ⌘S を押した人だけ（下）
- 登録したリポジトリと各ワークスペースの基点は UserDefaults に置く。ファイルの置き場は増やさない

登録していなくても、動いているセッションの在り処（`git rev-parse`）からリポジトリを見つけて管制塔に並べる。端末や `claude -w` で始めた作業もそのまま出る。見ていない間にターンが終わった・承認を求めてきたセッションの数が Dock のバッジに出る。アプリが後ろにある時は通知も出す（`package.sh` で組んだ .app の時だけ）。

- **競走** … 新規の板でエージェントを2体以上選ぶと、同じ基点のコミットから1本ずつ worktree を作って同じ指示を送る。管制塔で1組に束ね、⋯ の **採る** で勝ちを残す。負けは未コミットの変更の数を見せてから変更ごと消す（枝は `-d` なので、コミットを積んだものは残る）
- **采配** … 司令塔が門に `dispatch: grok` などを書くと、許可した時だけ AT22 がワークスペースを作ってそのエージェントを起こし、最初のターンの結果を `<id>.result` に書き戻す（書式は [docs/orchestrator-gate.md](docs/orchestrator-gate.md)）
- **レビューと出荷** … 07 REVIEW と 08 GIT。ハンクのステージ・コミット・push・PR は**押した時だけ**（PR は `gh` が自分の認証で作る）

**ソースを書くのは、人が ⌘S を押した時だけ。**FILES のエディタで人が直して保存した時に限る。開いた後に外で書き換えられていたら上書きしない。

**端末の中で人が打ったものは人の操作。**AT22 は端末に何も打ち込まない（タイルの「端末」で続きを開く時の `claude --resume` の1行だけ）。

**連携を有効にすると、`claude` / `codex` / `grok` / `hermes` を起こす。**設定で明示的に有効化した時だけ、AT22 はエージェントのセッションを起動できるようになる。その時も：

- **AT22 は認証情報を一切持たない。**API キーも OAuth トークンも保存しない。起こすのは**あなたが既にログイン済みの CLI**（`claude` / `codex` / `grok` / `hermes`）で、通信するのはそのプロセスであって AT22 ではない。設定の「ログイン」は、各 CLI 自身のログイン（`claude auth login` / `codex login` / `grok login` / `hermes setup`）を Terminal で起こすだけで、トークンはその CLI が持つ
- Claude Code は stream-json、Codex は `codex exec`、Grok と Hermes は ACP（Agent Client Protocol、`grok agent stdio` / `hermes acp`）で話す。どれも同じ会話欄・同じ盤面に出る。ACP は Gemini CLI や OpenCode なども話す共通の口
- Claude Code を起こす時のセッションIDは AT22 が採番する（`--session-id`）。transcript の在り処が確定するので、起こした先をそのまま画面で追える。Codex / Grok は相手が返したIDを台帳（UserDefaults）に残し、アプリを閉じても続きに繋げる
- CLI の場所はログインシェルに訊いて突き止める。見つからなければそのエージェントの起動UI自体が出ない
- AT22 から起こした Claude Code は、道具の承認を AT22 に訊く（`--permission-prompt-tool stdio`）。Lv.2 は道具ごとに全部、Lv.3 は編集以外を、会話の末尾のカードで許可・書換・却下する。書き換えて許可すると、**書き換えた入力の方が実行される**。サブエージェントの起動（Agent ツール）はどの段でも訊かれないので、そこは今まで通り門が止める
- 人間の承認なしにファイルを書き換える段（Lv.4 / Lv.5）を選ぶ時は、一度だけ確認が入る。Grok は Lv.4 / Lv.5 の時だけ `--always-approve` で起こし、それ以外はあなた自身の既定の権限モードに従う（`grok agent` に段を細かく渡す口が無いため）

git と gh は `Foundation.Process` で叩く。外部のパッケージは端末の SwiftTerm だけ。

読む先は3つ。`~/.claude/projects/` 配下の transcript と、`~/.claude/sessions/` 配下のセッション状態（Claude Code 自身が書く「動いているか・承認待ちか」）と、**稼働中セッションのプロジェクトディレクトリのソース**（依存グラフを作るため。読む拡張子とスキップするディレクトリは `Sources/AT22/Structure.swift` に列挙してある）。どれも読むだけで、開いて中身を出すことはしない。

端末で起こしたセッションが承認ダイアログで止まると、司令塔の箱が琥珀色の枠になり「承認待ち · 直前の作業」と出る。フックは使わない（Claude Code がセッション状態に書く値を読むだけ）ので、どのサブエージェントが待っているかまでは出ない。

## 見えるもの

画面は **Sumi v11**（claude.ai/design の `ui_kits/at22-v11`、段取りは `docs/design/v11/PLAN.md`）。青 `#1212EE` × 白の2色に、差し色のピンク `#FF3DCC` を小さく1色だけ。角丸も影も無い。

土台は **00 管制塔**。全部の worktree をタイルで並べ、押すと白い面が右から滑ってきてその worktree の画面（01〜10）に入る。**⌘0 / Esc** で管制塔へ戻る。

| キー | 効き |
|---|---|
| `M` / 鶴 | メニュー（3階層: 画面 → プロジェクト → ワークスペース。←→ で上り下り） |
| ⌘J | ワークスペースへ飛ぶ。あなた待ち → 作業中 → 完了 → 待機 の順、⌘1〜⌘6 で直に |
| ⌘0 | 管制塔 ⇄ 会話 |
| ⌃` | 端末を引き出す・しまう |
| ⌘P | ファイルを開く（FILES） |
| ⇧⌘T | 06 Tasks |
| Esc | 手前から順に畳む（板 → 端末 → 管制塔へ） |

**00 管制塔** … プロジェクトごとに worktree のタイル。名前・枝・エージェントの状態（あなた待ち／作業中／完了／失敗／待機）・最新の一言・差分量・競走の束。静かなものは畳む。右列は**門と承認の窓**（その場で許可・却下できる）。上帯の ＋ で新しいワークスペース（リポジトリ・分岐元・名前・エージェント・最初の指示・承認の段の6段。2体以上で競走）、タイルの ⋯ で枝を生やす・端末・消す・競走の勝者を採る。

**01 TALK 会話** … 司令塔とのやり取り。道具の承認と門は同じカードで **Allow / Rewrite / Reject**（Bash はコマンドと cwd、編集は差分で読める形に。JSON も見られる）。別の worktree で待っているものはカードの下に並び、押すとそこへ飛ぶ。右列は 04 ACTIONS（誰が・何を・どこに）と 05 PLAN（`TaskCreate` の窓・読み取り専用）。

**02 FILES 構造とファイル** … 右列に木（`.gitignore` を尊重・いま触られているものに墨・書込量の目盛り・ホバーで使う→／使われる←）と `git grep` の検索、下に開いたファイルの関係（使う・使われる・書込・読み）。左は**手で介入する時のパーキングブレーキ**のエディタ: 1ファイル・行番号・⌘F・⌘S・未保存の印。ハイライト・タブ・自動保存は無い。保存の前に読み直し、開いた後に外で書き換えられていたら上書きせず、読み直すか上書きかを訊く。REVIEW の ↗ や ACTIONS の行からはその行で開く。

依存は `import` では引けない（Swift の単一モジュールにはファイル間の import が無い）ので、**どのファイルが宣言した名前を、どのファイルが使っているか**で引いている。

**03 SPARRING 壁打ち** … 書き始める前に計画を練る場所。**読むだけのセッション**（claude の `--permission-mode plan`）をその worktree に起こし、型（PROPOSE 案を出して / OBJECT 反論して / BREAK DOWN 分解して / DECIDE 決めて）を付けて話す。返事の末尾の `STEP:` / `DECIDE: … // 理由` / `ASK: …？ [a | b]` を「採れる案」と「問い」として拾う。手順を採ると右の暫定プランに積まれ、■ 合意したものだけ **05 PLAN に送る**（司令塔に `TaskCreate` で積んでもらう1通）。決めたことは次の壁打ちに前提として渡り、**HANDOFF に書く**で記憶DBのノートに足す。

**07 REVIEW 差分** … 基点からの差分を1ファイルずつ。行を押して指摘を溜め、**1通にまとめて**エージェントへ送る。ハンクごとに **STAGE / 外す**（`git apply --cached`）。右列は変わったファイル（見た・ステージ数・指摘数）とコミット。

**08 GIT 記帳と送出** … 01 Commit（ステージした分だけ）→ 02 Push → 03 Pull request の3段。右列は遠くの枝とコミット（未送出にピンクの点）、PR と CI の状態（`gh pr view`）。どれも押した時だけ git を叩く。送り終わるとピンクの波紋が出て、鶴が片足で立つ。

**09 TERMINAL 端末** … チャットが主・端末は脱出口。下帯の `09 // TERM` か ⌃` で下から引き出す。worktree ごとにログインシェルを起こし、切り替えても生かしたまま持つ（アプリが閉じるまで）。2本以上は左右に並ぶ。管制塔のタイルの「端末」は AT22 の接続を閉じてから、中の端末で `claude --resume` する。

**10 SETTINGS 設定** … 新しいワークスペースの既定（承認の段・エージェント）、思考の表示、止まったエージェントを畳む・まっさらに。CLI の場所とログインは ⌘, の窓。

**止まった指示（門）**

司令塔がサブエージェントを起こす直前に人間が口を挟むための仕組み。**止めているのは AT22 ではない。**AT22 は Claude Code に干渉しないので、司令塔が自分から待ちに入り、AT22 が置いた答えで抜ける。**答えを書けなかった時は必ずカードに出す。**黙って消すと司令塔は待ち続ける。

```
司令塔:  memory/gate/<id>.md を書く → until [ -f <id>.verdict ]; do sleep 2; done → 従う
AT22 :  門を見せる → 人間が答える → memory/gate/<id>.verdict を書く
```

| Lv | 名前 | 止める指示 | 起こす時の `--permission-mode` |
|---|---|---|---|
| 1 | 壁打ち | —（指示を出さない） | `plan` |
| 2 | 隣で見てる | 全部 | `default`（道具ごとに承認を訊く） |
| 3 | 気にかけてる | 高リスクだけ | `acceptEdits` |
| 4 | 任せてる | 止めない | `bypassPermissions` |
| 5 | 留守番 | 止めない（無人） | `bypassPermissions` ＋ `--bg` |

値は `memory/gate/LEVEL` に書かれ、**司令塔も同じファイルを読む**ので、アプリの設定ではなくファイルが正。Lv.4 / Lv.5 を選ぶ時は一度だけ確認が入る。壁打ちのセッションは起こしてもこのファイルを書き換えない。

**文脈（CTX）** … `message.usage` の実測（`input` ＋ `cache_read` ＋ `cache_creation`）で 20 升を埋める。85% を超えると赤くなる。切れ目は `Sources/AT22/Snowman.swift`。**これはハルシネーションそのものの検知ではない。**

**フラグ（⚑）** … 同じエージェントが同じファイルを3回以上読み、一度も書いていない時に ACTIONS の行に付く。しきい値は ⌘, で 2〜6 回。

**思考の本文は残らない。**実測で全12セッション458件すべて `thinking` は空で、`signature` だけが記録されている。出るのは「いつ考えたか」だけなので、既定では畳んである（10 SETTINGS で出す）。

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

外部依存は **SwiftTerm 1.18 系**（端末のため）1つだけ。1.19 以降はビルド用プラグインが付き、Xcode で「信頼して有効化」を押すまで組めなくなるので上げない。Swift 6 と Command Line Tools で通る（Xcode は不要）。

## 開発

自己チェック（SwiftUI 非依存・ターゲット外）:

```
swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift \
  Sources/AT22/Structure.swift Sources/AT22/Category.swift Sources/AT22/Memory.swift \
  Sources/AT22/Gate.swift Sources/AT22/Launcher.swift Sources/AT22/Snowman.swift \
  Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift \
  Sources/AT22/Agents.swift Sources/AT22/ACP.swift Sources/AT22/Worktree.swift \
  Sources/AT22/Sparring.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
```

Foundation だけで組んであるので Linux でも通る（`FileManager.replaceItemAt` が Linux で常に失敗するので、
既存ノートの上書きを確かめる2箇所だけは `#if os(macOS)` で外してある）。

**SwiftUI 非依存のファイルを足したら、この行にも足すこと。** 足し忘れると
`cannot find type ... in scope` で落ちる（`Backend.swift` と `CodexLauncher.swift` で一度やった）。

見え方を画像に焼いて確かめる:

swift run AT22 --shot /tmp/x.png 1440 900                             # 01 TALK
swift run AT22 --shot /tmp/x.png --tower --workspaces                 # 00 管制塔（見本のワークスペース）
swift run AT22 --shot /tmp/x.png --transcript <path.jsonl> --gate     # 実データ＋門を1つ立てた状態
swift run AT22 --shot /tmp/x.png --mode review --review <worktree>    # 07 REVIEW（files / git / spar も）
swift run AT22 --shot /tmp/x.png --mode talk --term                   # 端末の引き出し
swift run AT22 --shot /tmp/x.png --menu root|jump  /  --sheet new|delete|pick
swift run AT22 --shot /tmp/x.png --ripple back:9                   # 管制塔⇄会話の波紋の途中のコマ（fwd:n・side:n も）

`--shot` は窓を開かずに PNG を1枚吐いて終わる。`ImageRenderer` は `TimelineView` / `ScrollView` /
`TextField` の中身を組まないので、焼く時だけ**時刻を固定**し、会話のログは素の VStack に、
入力欄は文字だけに差し替えてある。動き（墨流し・ドット・InkLoader・鶴）は1コマしか写らない。

書体は `Resources/Fonts/` から起動時に登録する（`swift run` はソースの場所から辿り、配布物は
`AT22.app/Contents/Resources/Fonts`。`package.sh` がコピーする）。青柳衡山T（`AoyagiKouzanT.ttf`）も同梱している
（ライセンスは `LICENSE-AoyagiKouzanT.txt`）。節番号の横の小さな和文ラベルに効く。

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
