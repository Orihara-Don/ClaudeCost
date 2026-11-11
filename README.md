# ClaudeCost

Claude Code の利用料金の推計を、macOS のメニューバーとウィジェットに表示するアプリです。

- 金額は Claude Code のローカルログ（`~/.claude/projects`）のトークン数 × 公開単価で計算した**推計値**です。実際の請求額とはずれることがあります。
- 集計するのは、そのMacで動いた Claude Code の利用分だけです。
- 外部とは通信しません。

Windows 版は [windows/README.md](windows/README.md) を見てください。

## 必要なもの

- macOS 14 以降
- Xcode（26.2 で確認済み）
- Apple ID を登録した Xcode（無料の Personal Team で動きます）
- [Homebrew](https://brew.sh/)

## ビルド手順

1. XcodeGen を入れます。

   ```bash
   brew install xcodegen
   ```

2. ソースを取得して、個人設定ファイルを作ります。

   ```bash
   git clone https://github.com/Orihara-Don/ClaudeCost.git
   ```

   ```bash
   cd ClaudeCost && cp Local.xcconfig.example Local.xcconfig
   ```

3. `Local.xcconfig` を自分の値に書き換えます。Team ID は次のコマンドで確認できます。Xcode の Settings > Apple Accounts でサインインしていないと表示されません。

   ```bash
   defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -E 'teamID|teamType'
   ```

4. Xcode プロジェクトを生成します。`project.yml` を変更したときも、これを実行します。

   ```bash
   xcodegen generate
   ```

5. Release 版を作って `/Applications` に入れます。

   ```bash
   xcodebuild -project ClaudeCost.xcodeproj -scheme ClaudeCost -configuration Release -archivePath build/ClaudeCost.xcarchive -destination 'generic/platform=macOS' -allowProvisioningUpdates archive
   ```

   ```bash
   ditto build/ClaudeCost.xcarchive/Products/Applications/ClaudeCost.app /Applications/ClaudeCost.app
   ```

6. `/Applications/ClaudeCost.app` を開きます。

開発するときは、`ClaudeCost.xcodeproj` を Xcode で開いて `ClaudeCost` スキームで実行してください。テストは Cmd+U で実行できます。

## 使い方

- メニューバーの金額をクリックすると、内訳のパネルが開きます。
- デスクトップを右クリックして「ウィジェットを編集」を選ぶと、「Claude Code 費用」のウィジェットを置けます。
- メニューバーでの表示と非表示は、macOS の「システム設定」の「メニューバー」で切り替えます。隠している間も集計は続きます。
- 止めるときは、パネルか設定画面の「終了」を使います。

## 設定で確認してほしいこと

- **リージョナル料金（×1.1）:** 既定でオンです。Bedrock の global エンドポイントを使っている場合や、Bedrock を使っていない場合はオフにしてください。
- **単価:** Anthropic の公開価格を `App/Resources/prices.json` に入れています。設定の「prices.json を開く」から上書きできます。
- **USD/JPY レート:** 手入力です。自動では更新しません。

## データの場所

| ファイル | 内容 |
| --- | --- |
| `~/Library/Application Support/ClaudeCost/state.json` | 日別のトークン数、読み取り位置 |
| `~/Library/Application Support/ClaudeCost/prices.json` | 単価の上書き（作成した場合のみ） |

会話の本文は保存しません。アンインストールするときは、アプリを終了してから、`/Applications/ClaudeCost.app` と上記のフォルダを削除してください。

## ライセンス

[MIT License](LICENSE)

Anthropic の公式アプリではありません。Issue と Pull Request は受け付けていません。
