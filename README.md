# MenuAll

MenuAllは、画面外やノッチの裏に隠れたmacOSのメニューバー項目を、ひとつの小さなポップアップから確認・操作するアプリです。「MenuAllを押すと全部見える」に加え、対応する項目を表示／非表示へすばやく切り替えられる、手動操作に絞ったMVPです。

## MVPの範囲

含まれる機能:

- 取得可能なメニューバー項目の列挙
- 「隠れている」「表示中」「表示位置を確認できない」の分類
- 一覧から元項目のメニューまたは操作を呼び出す機能
- 対応する項目を「メニューバーに表示」トグルで非表示から表示、表示から非表示へ切り替える機能
- 変更結果の再確認、失敗時の復元、直前操作の取り消し
- アプリの起動・終了と定期更新による一覧の自動更新
- 権限案内、取得失敗時の通知、取得できた項目の部分継続
- 表示形式、ログイン時起動、システム項目表示の設定

MVPに含まれない機能:

- 任意位置へのドラッグ並べ替え
- 項目ごとの永続ルール、プロファイル、条件別の自動切り替え
- 画面キャプチャに依存する認識
- macOSの非公開APIを使った挙動の再現
- クラウド同期、アカウント、外部通信

## 権限

他アプリのメニューバー項目を取得・操作し、対応項目の表示状態を変更するため、macOSのアクセシビリティ権限が必要です。初回起動時の案内から「システム設定 > プライバシーとセキュリティ > アクセシビリティ」を開き、MenuAllを許可した後に権限を再確認してください。

macOSや対象アプリから安全に対象を一意に特定できない項目、固定システム項目は、理由を表示して切り替えを無効にします。IceやBartenderなど同じ配置を管理するアプリの起動中も競合を避けるため無効になります。MenuAllがそれらのアプリを終了または設定変更することはありません。

取得した項目情報は端末内だけで処理し、分析SDK、外部送信、クラウド保存は使用しません。

## 開発環境

- macOS 14以降
- Xcode 26.6
- Swift 6
- AppKit + SwiftUI
- ApplicationServices Accessibility API

外部パッケージとネットワーク接続は使用しません。

## ビルド

```bash
xcodebuild \
  -project MenuAll.xcodeproj \
  -scheme MenuAll \
  -configuration Debug \
  build
```

Xcodeから起動する場合は、`MenuAll` Schemeを選択してください。Dockには常駐せず、メニューバーにMenuAllアイコンが表示されます。

Releaseビルド:

```bash
xcodebuild \
  -project MenuAll.xcodeproj \
  -scheme MenuAll \
  -configuration Release \
  build
```

## テスト

モデルテストとUI E2Eをまとめて実行します。

```bash
xcodebuild test \
  -project MenuAll.xcodeproj \
  -scheme MenuAll \
  -destination 'platform=macOS,arch=arm64'
```

実際のAccessibility権限、ノッチ、他アプリのメニュー操作、表示／非表示の切り替えを伴う検証は、[E2Eテスト計画](docs/e2e-test-plan.md)に従って実施します。表示管理の実装順序と安全境界は[表示管理 実装計画](docs/visibility-management-plan.md)を参照してください。

## 現在の検証状況

Unitテスト131件、Debug／Releaseビルド、静的解析、従来範囲のUI E2E、Mac miniでの列挙・元メニュー操作、Iceを一時終了した状態での独立動作は確認済みです。表示／非表示の実変更は安全側の実装とヘッドレス検証まで完了していますが、実項目を動かすE2Eは未実行です。ノッチ付きMacでの検証とDeveloper ID署名・公証も未完了です。詳細は[技術スパイク結果](docs/technical-spike-results.md)を参照してください。

## ライセンス

[MIT License](LICENSE)
