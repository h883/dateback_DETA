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
- Own Post Viewer では ♥ 件数を表示し、タップすると いいねした人一覧(avatar + username)をシートで見られる
- Settings の「撮影地を自動で追加」が ON のときだけ、撮影地(市区町村程度の粗い地域名)を投稿に付与できる(緯度経度そのものは送らない)

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
| アプリ | Flutter / Dart。現在は **Android が主対象**。iOS は scaffold(`ios/`)と最低限の runtime permission(Camera・Bluetooth・Location)の usage description はあるが、Firebase の iOS 設定が未着手のため現状ではビルドしてもログインできない(詳細は下記「未実装・既知の制約」) |
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
- 投稿失敗時の下書き(Draft)のローカル永続化・一覧・再投稿・削除
  - Camera 画面(左ツール列)に、下書きが1件以上あるときだけ件数バッジ付きアイコンを表示(0件のときは常時表示しない)
  - タップすると下書き一覧シート(3:2 サムネイル・35mm/8mm の印・保存日時・`locationLabel` があれば表示)を開く
  - 下書きを選ぶと投稿前確認画面(`DraftPreviewScreen`)へ進み、投稿する/削除/戻る を選べる
  - 再投稿では位置情報を取り直さず、保存済みの `locationLabel` をそのまま送信
  - 投稿成功後にだけ下書き本体(メディア+manifest)を削除し、成功時は通常の投稿と同じ「✓ 投稿しました / 投稿を見る」体験へ合流する
  - 投稿失敗時は下書きを残したままエラーを表示し、再試行できる
- Settings Drawer(表示テーマ・横向きカメラ起動・撮影地設定など)
- 初回起動の Consent / Tutorial フロー
- 35mm 撮影の 3:2 センタークロップ
- 8mm 撮影の無音化
- Own Post Viewer の ♥ 件数表示・いいねした人一覧(B1)
  - like 件数は Post API のレスポンス(`likeCount`)にそのまま含まれる
  - ♥ をタップしたときだけ `GET /api/posts/:id/likers` を呼び、一覧(avatar + username)を遅延取得
  - likers の取得は既存の投稿閲覧権限制御をそのまま利用(投稿を見られる人だけが一覧も見られる)
- 撮影地(粗い地域名)の自動追加(B2)
  - Settings「撮影地を自動で追加」が ON のときだけ、35mm・8mm どちらでも撮影のタイミングで位置情報を取得
  - reverse geocoding で市区町村程度の粗い地域名へ変換してから送信(緯度経度そのものは送信・保存しない)
  - `Post.locationLabel`(nullable)として保存し、Home・Own Post Viewer に表示
  - 投稿失敗時の再試行・下書き(Draft)保存でも、撮影時に取得済みの `locationLabel` をそのまま使い、取り直さない
  - D1 migration `0005_post_location.sql` で `posts.location_label` を追加
  - Android debug build の最終 merged manifest に位置情報の permission(`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`)が含まれることを確認済み
- 他ユーザーのプロフィール専用画面(`OtherProfileScreen`)
  - avatar・username・bio(あれば)・閲覧可能な投稿の2列グリッドを表示(自分専用の編集・Settings・ログアウトは出さない)
  - 遷移元: フレンド一覧の行、いいねした人一覧の行、Home の投稿者 avatar / username(投稿本体のタップ・縦スワイプ操作とは独立)
  - 投稿グリッドのタップは既存の Own Post Viewer をそのまま再利用(他人の投稿として `isOwn: false`)
  - 表示する投稿は常にバックエンドがそのとき返す閲覧可能投稿のみ(`fetchUserPosts`。Flutter 側で `visible_until` は判定しない)
- 成立済みフレンドの解除
  - 他ユーザープロフィール画面の「フレンド解除」(控えめな赤系テキスト)→確認ダイアログ→`DELETE /api/friends/:uid`
  - 解除対象は呼び出し中ユーザーと指定 uid の間の **成立済み(accepted)** friendship のみ(pending 申請の取消/却下は既存の `DELETE /api/friends/requests/:uid` のまま別扱い)
  - 解除と同時に、その2人の間の `view_permissions` を **双方向とも** 削除し、投稿の閲覧権限が残らないようにする
  - `proximity_events`(「会ったことがある」履歴)は削除しない(投稿の閲覧権限には使われないため、他の判定へ影響を与えず履歴として保持する)
  - 成功後は前画面へ戻り、Friends 一覧はバックエンドから再取得して反映する(ローカルだけの解除状態は作らない)
- 35mm の複数フィルター切替(v15 の filter swipe)
  - Camera の35mmプレビュー上を横スワイプすると、Neutral / Warm / Cool / Film Contrast の4種類を順番に切り替えられる(8mm には適用しない)
  - フィルター名は画面へ表示せず、現在位置を示す控えめな dots のみ
  - プレビューは `ColorFilter.matrix`、保存する JPEG は同じ 4x5 matrix を使った独自のピクセル処理([`applyColorMatrix`](lib/screens/tabs/photo_filter.dart))で焼き込むため、プレビューと投稿画像の見た目が一致する
  - シャッターを切った瞬間のフィルターをその1枚へ固定し、処理中にスワイプしても撮影結果には混ざらない
  - Camera 画面の横スワイプは、MainShell の Camera ← Home → Profile のタブ切替スワイプと衝突しないよう、フィルタースワイプ中だけ PageView 側の navigation を一時的に止める設計にしてある

### 未実装・既知の制約

- Apple ログイン(UI のみ、実際の認証は未実装)
- 利用規約・プライバシーポリシーの実 URL
- アカウント削除の実 API
- camera プラグインの制約により、物理的な広角・超広角・望遠レンズの正確な列挙・切替は未実装
- 8mm 動画ファイルそのものの 3:2 クロップ(プレビューのみ 3:2 で、保存ファイルはセンサーのネイティブ比率のまま)
- 閲覧権限の再伝播(仕様書の F-14)。「A→Bへ閲覧可能→BがCに再伝播」のような扱いは仕様として未決定のまま、意図的に未実装
- iOS: `Info.plist` に Camera / Bluetooth(Always・Peripheral)/ Location の usage description は追加済みだが、
  - `firebase_options.dart` に iOS 用の `FirebaseOptions` が無く、iOS では `Firebase.initializeApp` が必ず失敗する(`DefaultFirebaseOptions.currentPlatform` が iOS 分岐で明示的に `UnsupportedError` を投げる実装のまま)
  - `GoogleService-Info.plist` 自体が存在しない
  - Xcode プロジェクトの Bundle Identifier もまだ `com.example.workspace` のまま
  - 上記はいずれも Firebase Console 側でのiOSアプリ登録が前提のため、リポジトリ内の値だけでは解決できない
  - 後輩が別ブランチで進めている iOS 対応も、まだこのリポジトリの remote 上では確認できていないため未統合。統合でき次第この節を更新する

### 実装済み・実機検証待ち

BLE・端末の傾き検知・権限まわりは実装済みだが、Android 実機での総合的な動作確認がまだ済んでいない。

- BLE による実機同士の近接検知・交換
- 横向きでの Camera 自動起動(傾きの向きの判定)
- カメラ・Bluetooth・位置情報・通知の権限リクエストの実機挙動
- 撮影地(B2)の Android 実機での GPS 取得・reverse geocoding
- 位置情報の権限拒否・GPS/位置情報サービス OFF 時でも投稿・下書きが失敗せず続くこと
- Home・Own Post Viewer での撮影地表示の実機での見え方
- 35mm フィルタースワイプと、MainShell のタブ切替スワイプ(Camera ← Home → Profile)が実機のタッチ挙動で本当に衝突しないこと

## 開発者向けドキュメント

| ドキュメント | 内容 |
|---|---|
| [仕様書.md](仕様書.md) | 何を作っているか、閲覧権限などの詳しい仕様、実装状況 |
| [docs/SETUP.md](docs/SETUP.md) | 別の端末で動かすための手順、Firebase の SHA-1 登録、既知の落とし穴 |
| [docs/DOCKER.md](docs/DOCKER.md) | Docker で Android ビルドを行う手順 |
| [workers/README.md](workers/README.md) | バックエンド(Cloudflare Workers)のエンドポイント一覧と閲覧制御の仕組み |
