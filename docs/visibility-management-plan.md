# MenuAll 表示管理 実装計画

- 文書バージョン: 0.1
- 作成日: 2026-09-04
- 対象: macOS 14以降

## Goal

MenuAllの一覧から、対応するメニューバー項目を「非表示から表示」と「表示から非表示」の両方向へ、1回の明確な操作で実際に切り替えられるようにする。元のメニューを開く操作とは分離し、変更の完了をOS上の観測結果で確認してからUIへ反映する。

この計画は従来の「他アプリの項目の位置変更・項目別の表示／非表示管理はMVP対象外」という定義を改訂する。新MVPには手動の表示／非表示切り替えを含める。一方、任意位置への並べ替え、永続ルール、条件別の自動切り替え、プロファイルは引き続き対象外とする。

## Target Files

| 領域 | 主な対象 | 変更目的 |
| --- | --- | --- |
| 状態モデル | `MenuAll/Models/MenuBarItemSnapshot.swift`、`MenuAll/Models/MenuBarVisibilityChange.swift` | 観測状態、要求状態、可否、処理中、結果を分離する |
| 変更境界 | `MenuAll/Visibility/MenuBarVisibilityChanging.swift`、`MenuAll/Visibility/MenuBarVisibilityChangeCoordinator.swift` | 実装差し替え、直列化、検証、timeout、rollbackを担う |
| メニューバー制御 | `MenuAll/Visibility/MenuBarSectionController.swift`、`MenuAll/Visibility/CGEventMenuBarVisibilityChanger.swift` | MenuAll所有の境界項目と公開のCore Graphicsイベントで表示状態を変更する |
| 項目照合 | `MenuAll/Visibility/WindowServerMenuBarItemMatcher.swift` | AX項目とWindowServer上の対象を安全に照合し、曖昧一致を拒否する |
| 競合検出 | `MenuAll/Visibility/MenuBarManagerConflictDetector.swift` | Ice等の同種アプリ起動中は変更操作を無効化する |
| 組み込み | `MenuAll/App/AppDelegate.swift`、`MenuAll/Discovery/MenuBarDiscoveryService.swift` | 実装の組み立て、再取得、変更後の一覧更新を行う |
| UI | `MenuAll/UI/MenuAllPopoverView.swift` | 元メニューを開く操作と「メニューバーに表示」トグル、進行、理由、取り消しを提供する |
| テスト境界 | `MenuAll/Support/LaunchEnvironment.swift` | Releaseへ影響しない決定的なUIテスト条件を注入する |
| Unitテスト | `MenuAllTests/*Visibility*Tests.swift`、`MenuAllTests/MenuBarManagerConflictDetectorTests.swift` | 成功、失敗、timeout、rollback、競合、照合をTDDで固定する |
| UI E2E | `MenuAllUITests/MenuAllUITests.swift` | 両方向の切り替え、非対応、失敗、元メニュー操作との分離を確認する |
| 文書 | `README.md`、`docs/technical-spike-results.md`、`docs/e2e-test-plan.md` | 新MVPの範囲、未検証事項、実機手順を同期する |

実装時にファイルを統合または分割しても、上記の責務境界は維持する。

## Steps

1. 先に失敗するUnitテストを追加し、表示要求、処理中、成功確認、timeout、rollback、同時操作の拒否、非対応理由の契約を固定する。
2. `MenuBarVisibilityChanging`を境界として、UIとOS操作を分離する。観測値が要求値に一致するまでは成功として扱わない。
3. MenuAll自身が所有する境界ステータス項目を用意し、対象項目を境界の左右へ移す最小の制御を実装する。利用者へ任意の並べ替えUIは提供しない。
4. AX情報とWindowServer情報を照合する。所有元、位置、候補数から対象を一意に特定できない場合は操作せず、理由付きの`unsupported`にする。
5. 公開APIのCore Graphicsイベントで変更を行い、2秒以内を目安に再観測する。未達、権限喪失、対象消失時は元の位置へrollbackし、一覧を再取得する。
6. Ice等の同種管理アプリを検出し、起動中は変更トグルを無効化する。MenuAllから他アプリを終了、設定変更、アンインストールはしない。
7. ポップアップに「メニューバーに表示」トグルを追加する。元メニューを開くボタンは独立させ、処理中は多重操作を防ぎ、成功後に項目を該当セクションへ移し、取り消しを提示する。
8. 決定的なfakeを使ったUI E2Eを先に追加し、非表示→表示、表示→非表示、失敗、非対応、元メニュー操作の非干渉を検証する。
9. MenuAllがテスト用に所有する専用fixture項目だけを使い、実機で両方向の変更とrollbackを検証する。起動用のMenuAllアイコンは対象にしない。その後、利用者が許可した非破壊的な対象へ範囲を広げる。
10. Unit、UI E2E、Debug／Releaseビルドを全て通し、ノッチ付きMacと署名・公証済み配布物で最終確認する。

## Dependencies

- macOS Accessibility権限。列挙、対象特定、変更後の再観測に必要となる。
- AppKitの`NSStatusItem`。MenuAll自身の項目と表示／非表示の境界を構成する。
- Core Graphicsの公開API（`CGEvent`、WindowServerの取得可能なウィンドウ情報）。非公開APIには依存しない。
- 対象項目を一意に照合できること。同一アプリが複数項目を持つ場合や情報不足時は対応を保証しない。
- Ice、Bartender等が同じ配置を同時に管理していないこと。競合検出時は安全のため変更機能を停止する。
- 画面構成、macOSバージョン、対象アプリ実装によって取得できる情報が異なるため、公開APIで安全に保証できない対象は理由付き`unsupported`とする。

## Test Plan

### Unit / TDD

- 要求状態と観測状態の対応、変更不要時のno-op、位置不明の拒否。
- 1操作ずつの直列化と、多重操作時の安全な拒否。
- 成功観測、遅延観測、timeout、観測失敗、rollback成功、rollback失敗。
- AX項目とWindowServer項目の一意照合、候補なし、複数候補、対象消失。
- Ice等の競合検出、システム固定項目、情報不足項目の理由付き非対応。
- MenuAll所有境界の初期状態、長さ変更、終了時の後始末。

### 自動UI E2E

- 非表示項目のトグルをオンにすると、確認完了後に表示中セクションへ移る。
- 表示中項目のトグルをオフにすると、確認完了後に非表示セクションへ移る。
- 変更中表示と多重操作防止、失敗時の元セクション維持、エラー表示、取り消し。
- 位置不明、固定システム項目、競合中の項目はトグルが無効で、理由をVoiceOverでも取得できる。
- 元メニューを開く操作では表示状態が変わらない。

### 実機E2E

- 開始位置を記録し、最初はMenuAllが所有する専用fixtureだけで表示→非表示→表示を実行する。起動用のMenuAllアイコンは対象にしない。
- 各操作後にメニューバー上の実状態とMenuAllの分類が2秒以内に一致することを確認する。
- 意図した項目以外の順序・状態が変わっていないことを確認する。
- 失敗注入時に元の位置へ戻ること、アプリ再起動後もメニューバーが破損しないことを確認する。
- Ice等の起動中にトグルが無効化され、終了後の再読み込みで有効性が再判定されることを確認する。
- ノッチ付きMac、複数ディスプレイ、Developer ID署名・公証済みビルドでも同じ主要フローを実行する。

## Rollback Plan

1回の操作では、対象ID、変更前の観測状態、元座標、隣接項目、操作IDを一時保持する。成功確認前に異常が起きた場合は逆方向の操作を実行し、元状態を再観測する。復元にも失敗した場合は成功を装わず、変更機能を停止して再読み込みと具体的な復旧案内を表示する。

リリース単位では、表示変更の組み込みを無効化しても既存の列挙・分類・元メニュー操作が利用できる構成を保つ。重大な回帰があれば表示変更機能を無効化したビルドへ戻し、保存済みの永続ルールは作らないためデータ移行を不要とする。

## Definition of Done

- 対応対象で非表示→表示、表示→非表示がそれぞれ1回の明確な操作で完了する。
- UI上の成功はOS上の再観測後にだけ確定し、失敗時は元状態が維持または復元される。
- 元メニューを開く操作と表示切り替えが誤操作なく分離されている。
- Ice等との競合中、位置不明、一意照合不能、固定システム項目は理由付きで操作不可になる。
- 1項目の失敗で一覧全体、他項目の閲覧、元メニュー操作が利用不能にならない。
- Unit、UI E2E、Debug／Releaseビルドが合格し、テスト件数と実機証拠が技術スパイク結果に記録される。
- MenuAll所有の専用fixtureで実機の両方向切り替えとrollbackが合格する。
- ノッチ付きMacと署名・公証済みビルドの主要フローが合格する。未完了の場合はリリース判定を「追加検証」と明記する。
