# dateback

dateback は、**実際にフレンドと近距離で会った時点までの投稿が、その相手に解放される SNS** です（NovaHack 2026 向けに開発中）。

フレンドになっただけでは、相手の過去の投稿がすべて見えるわけではありません。実際に近くで会うことで、その時点までの投稿だけが閲覧できるようになります。それ以降に投稿されたものは、次にまた会うまで見えません。

## いちばん大事な仕様

**viewer から見た author の投稿は、閲覧可能時刻より前のものだけ見える。**

- BLE は「実際に会ったこと」をアプリへ知らせる**トリガ**でしかない。
- 閲覧可能範囲の **source of truth はバックエンド**（Cloudflare Workers + D1）。
- Flutter 側で投稿時刻と `visible_until` を突き合わせて判定する処理は書かない。API はその時点で閲覧可能な投稿だけを返す。

詳しい仕様は [仕様書.md](仕様書.md) を参照。

## 現在の主な UX

### メインナビゲーション

```text
Camera ← Home → Profile
```

- 起動時は Home
- 右フリックで Camera、左フリックで Profile へ
- ボトムナビは Camera / Home / Profile の3つ
- Camera 表示中はボトムナビを隠す
- フレンド追加は独立タブではなく、Home 右上・フレンド一覧からのシート
- Profile から Friends 一覧・Settings Drawer を開ける

### BLE 近接検知

- フォアグラウンド限定の MVP（バックグラウンド・アプリ終了時は対象外）
- 既存フレンドとの近接が成立すると、双方の閲覧可能範囲（visible range）を更新
- **新しく閲覧可能になった投稿が1件以上あるときだけ**交換成功のアニメーションを再生
- 近接イベントが成立しても新規投稿が0件のときは、成功アニメーションを出さない

### 投稿

- **35mm**: 静止画、3:2 で撮影・投稿
- **8mm**: 約2秒・無音の動画
- 投稿には撮影日の date burn-in を焼き込んで表示
- キャプション・コメント・ハッシュタグは無し。リアクションは「いいね」のみ
- 投稿失敗時は 再試行 / 端末へ永続化した下書き(Draft) / 破棄 を選べる

### テーマ

- Light / Dark / System の3種類（Quiet Analog デザイン）

## 初回起動フロー

```text
Login → Consent / Permissions → Tutorial → Home
```

初回セットアップで確認する権限は次の4つ。

- Camera
- Bluetooth
- Location
- Notifications

マイク（Microphone）は使いません。

- Google ログインは実装済み
- Apple ログインは現時点で UI のみ（「近日対応」。実際の認証処理は未実装）
- 初回チュートリアルの完了状態は Firebase Auth の **uid ごと**に端末へ永続化する(同じ端末で別アカウントに切り替えた場合、そのアカウントは必ず Consent/Tutorial を通る)

## 技術構成

| | |
|---|---|
| アプリ | Flutter / Dart。現在は **Android が主対象**（iOS 向けの設定は未整備で、iOS 対応は完了していない） |
| 認証 | Firebase Authentication。Google ログイン実装済み、Apple は未実装（UI のみ） |
| API | Cloudflare Workers（TypeScript） |
| DB | Cloudflare D1 |
| 画像・動画 | Cloudflare KV |
| 近距離検知 | BLE（`flutter_blue_plus` + `flutter_ble_peripheral`、フォアグラウンド限定） |
| テーマ | Light / Dark / System（`shared_preferences` へ永続化） |

### `lib/` の構成

```text
lib/
  api/        Cloudflare Workers を叩くクライアント（BloomApi）
  device/     端末の傾き検知（TiltWatcher）
  drafts/     投稿失敗時の下書き（Draft）のローカル永続化
  models/     API レスポンスのモデル
  proximity/  近距離検知（BLE 実装とダミー実装）
  screens/    画面（tabs/ 配下に Camera・Home・Profile 本体）
  settings/   表示テーマ以外のローカル設定（横向きカメラ起動・撮影地自動追加など）
  theme/      デザイントークンとテーマ切替
  widgets/    共通ウィジェット
workers/      Cloudflare Workers のバックエンド
```

## セットアップ（クイックスタート）

1. Flutter・Android SDK など前提ツールを用意する(バージョンは [docs/SETUP.md](docs/SETUP.md) 参照)
2. このリポジトリを clone する
3. 依存を取得する

   ```bash
   flutter pub get
   ```

4. Firebase 固有の設定(Google ログイン用の SHA-1 登録など)を行う → **[docs/SETUP.md](docs/SETUP.md)**
5. アプリを起動する

   ```bash
   flutter run
   ```

**clone しただけでは、環境によっては動きません。** はまりやすい落とし穴(Firebase の SHA-1 登録など)は [docs/SETUP.md](docs/SETUP.md) にまとめてあります。

既定では本番の Worker（`https://bloom-api.example.workers.dev`）につながります。ローカルの Worker に接続する方法も [docs/SETUP.md](docs/SETUP.md) を参照してください。

Docker で Android ビルドを行う場合は [docs/DOCKER.md](docs/DOCKER.md) を参照してください。

## 開発時の重要ルール

- **閲覧可否はバックエンドが決める。** アプリ側で投稿時刻と `visible_until` を独自判定しない。
- **BLE 検出のたびに API を乱発しない。** 既存の cooldown・dedupe(クライアント側・サーバー側とも)を尊重する。
- **main へ直接 push しない。** feature branch を切って PR にする。
- **`google-services.json` を不用意に commit しない。** ローカル固有の設定(自分の SHA-1 など)が混ざっていないか確認する。
- **内部の `Bloom*`(`BloomApi`・`BloomColors` など)は現時点では内部コードネームとして残っている。** ユーザー向けの名称はすでに `dateback` に統一済みだが、内部識別子の大規模 rename は機能変更と同時に行わない。

## 現在の実装状況

### 実装済み

- Camera / Home / Profile の3画面ナビゲーション
- Light / Dark / System テーマ切替
- BLE 近接検知の基盤(常時スキャン・beaconId ローテーション追従)
- フレンド追加シート(Home・フレンド一覧から起動)
- 通知画面でのフレンド申請の承認・拒否
- Own Post Viewer(自分の投稿を見るビューアーの共通化)
- 投稿成功・失敗のフロー
- 投稿失敗時の下書き(Draft)のローカル永続化基盤
- Settings Drawer(表示テーマ・横向きカメラ起動・撮影地設定など)
- 初回起動の Consent / Tutorial フロー
- 35mm 撮影の 3:2 センタークロップ
- 8mm 撮影の無音化

### 未実装・既知の制約

- Apple ログイン(UI のみ、実際の認証は未実装)
- 他ユーザーのプロフィール専用画面
- 利用規約・プライバシーポリシーの実 URL
- アカウント削除の実 API
- いいねした人の件数・一覧の UI/API(B1)
- 撮影地(位置情報)機能そのもの(B2)
- camera プラグインの制約により、物理的な広角・超広角・望遠レンズの正確な列挙・切替は未実装
- 8mm 動画ファイルそのものの 3:2 クロップ(プレビューのみ 3:2 で、保存ファイルはセンサーのネイティブ比率のまま)
- 35mm の複数フィルター切替

### 実装済み・実機検証待ち

BLE・端末の傾き検知・権限まわりは実装済みだが、Android 実機での総合的な動作確認がまだ済んでいない。

- BLE による実機同士の近接検知・交換
- 横向きでの Camera 自動起動(傾きの向きの判定)
- カメラ・Bluetooth・位置情報・通知の権限リクエストの実機挙動

## 開発者向けドキュメント

| ドキュメント | 内容 |
|---|---|
| [仕様書.md](仕様書.md) | 何を作っているか、閲覧権限などの詳しい仕様、実装状況 |
| [docs/SETUP.md](docs/SETUP.md) | 別の端末で動かすための手順、Firebase の SHA-1 登録、既知の落とし穴 |
| [docs/DOCKER.md](docs/DOCKER.md) | Docker で Android ビルドを行う手順 |
| [workers/README.md](workers/README.md) | バックエンド(Cloudflare Workers)のエンドポイント一覧と閲覧制御の仕組み |
