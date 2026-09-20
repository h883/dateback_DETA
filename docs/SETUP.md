# 開発環境のセットアップ

別の端末でこのリポジトリを動かすための手順。
**リポジトリを clone しただけでは動かない箇所が3つある**（Firebase の SHA-1、
Cloudflare のログイン、パスの制約）。そこだけ注意して読めばよい。

- [1. 前提のツール](#1-前提のツール)
- [2. 依存の取得](#2-依存の取得)
- [3. Firebase — 自分の SHA-1 を登録する](#3-firebase--自分の-sha-1-を登録する)
- [4. Cloudflare](#4-cloudflare)
- [5. 動かす](#5-動かす)
- [6. APK を作る](#6-apk-を作る)
- [7. 既知の落とし穴](#7-既知の落とし穴)

---

## 1. 前提のツール

動作を確認したバージョン。

| | バージョン |
|---|---|
| Flutter | 3.47.2（stable） |
| Dart | 3.13.2 |
| Android Gradle Plugin | 9.1.0 |
| Gradle | 9.3.1 |
| Kotlin | 2.4.0 |
| Node.js | 20 以上（Cloudflare 側） |

Android SDK は **API 37 のプラットフォームが必要**。`permission_handler_android`
が compileSdk 37 以上を要求するため、`android/app/build.gradle.kts` で
`compileSdk = 37` を明示している。Android Studio の SDK Manager で
`Android API 37` を入れておくこと。

`pubspec.lock` はコミットしてあるので、`flutter pub get` で同じ版が入る。

## 2. 依存の取得

```bash
flutter pub get
```

```bash
cd workers && npm install
```

Windows では `flutter pub get` が「Developer Mode を有効にしろ」と言う。
プラグインのシンボリックリンクに必要なので、設定から開発者モードを入れる。

```bash
start ms-settings:developers
```

## 3. Firebase — 自分の SHA-1 を登録する

**ここを飛ばすと Google ログインが `ApiException: 10`（DEVELOPER_ERROR）で必ず失敗する。**

デバッグ用の署名鍵 `~/.android/debug.keystore` は**マシンごとに自動生成される**ので、
新しい端末でビルドした APK は Firebase から見ると別アプリになる。

自分の SHA-1 を調べる。

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Windows の keytool は Android Studio に同梱されている。

```bash
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

出てきた `SHA1:` の値を Firebase コンソールに**追加**する（既存の値は消さない。
消すと他のメンバーの環境が壊れる）。

1. https://console.firebase.google.com/project/nova-hack2026-366bf/settings/general
2. Android アプリ `com.example.snsnovahack` → 「フィンガープリントを追加」
3. 更新された `google-services.json` をダウンロードして
   `android/app/google-services.json` に上書き
4. 変更をコミットして共有する

> **恒久策**：メンバーが増えるたびにこれをやるのが面倒なら、共有の
> debug keystore をリポジトリに置いて `signingConfigs.debug` で指す方法もある。
> デバッグ鍵は秘密情報ではないのでコミットして構わない。

## 4. Cloudflare

バックエンドは **すでにデプロイ済み**。アプリの既定の接続先もそこを向いているので、
アプリを動かすだけなら Cloudflare を触る必要はない。

| | |
|---|---|
| アカウント | `user@example.com` / `YOUR_CLOUDFLARE_ACCOUNT_ID` |
| Worker | `https://bloom-api.example.workers.dev` |
| D1 | `bloom` / `8287e3eb-a958-4693-9bed-abf6cf04c6e1` |
| KV（メディア） | `MEDIA` / `728fd7b51a3846458c038fd43f32a654` |

これらの ID は `workers/wrangler.jsonc` に書いてあるので、リポジトリを clone すれば
そのまま使える。

### デプロイしたいとき

```bash
cd workers && npx wrangler login
```

ブラウザが開くので `user@example.com` で承認する。以降は

```bash
npx wrangler deploy
```

スキーマを変えたときは先にマイグレーションを流す。

```bash
npx wrangler d1 migrations apply bloom --remote
```

### メディアを R2 ではなく KV に置いている理由

R2 は無料枠でもクレジットカードの登録を求められるため、カード不要で
1値あたり 25MB まで置ける KV を使っている。
KV 無料枠は**ストレージ 1GB（namespace 全体）**・**書き込み 1,000回/日**・
**読み取り 100,000回/日**、そして結果整合性（投稿直後の数秒はまれに
メディアが 404 になり得る）。先に当たるのはストレージなので、35mm は投稿前に
長辺 1600px・JPEG quality 85 へ縮小している。404 はアプリ側が読み直して吸収し、
書き込み上限は `503 media_store_unavailable` として返る。

R2 に移す場合は `workers/src/index.ts` の
`put` / `getWithMetadata` と `wrangler.jsonc` のバインディングだけ差し替えればよい。

詳細は [workers/README.md](../workers/README.md)。

## 5. 動かす

### 本番の Worker につなぐ（普通はこれ）

```bash
flutter run
```

### ローカルの Worker につなぐ

Cloudflare のログインは要らない。まず Worker を起動する。

```bash
cd workers && npx wrangler d1 migrations apply bloom --local
```

```bash
npx wrangler dev --ip 0.0.0.0 --port 8787
```

別の窓でアプリを実行する。接続先はエミュレータとUSB実機で変わる。

```bash
flutter run --dart-define=BLOOM_API_BASE_URL=http://10.0.2.2:8787
```

USB 接続の実機からは PC の LAN アドレスを使う。

```bash
flutter run --dart-define=BLOOM_API_BASE_URL=http://192.168.0.25:8787
```

平文 HTTP はデバッグビルドでのみ許可している
（`android/app/src/debug/AndroidManifest.xml` の `usesCleartextTraffic`）。
リリースビルドでは使えない。

### ログインするには Google アカウントが要る

端末（エミュレータ含む）に Google アカウントが1つも無いと、アカウント選択画面が
空のまま止まる。エミュレータの場合は設定から追加しておく。

## 6. APK を作る

```bash
flutter build apk --release
```

`android/app/build.gradle.kts` の release はデバッグ鍵で署名する設定のままなので、
**Firebase に登録済みの SHA-1 と一致し、release APK でも Google ログインが通る**。
本番配布する段階になったら専用の署名鍵を用意して、その SHA-1 も Firebase に登録すること。

## 7. 既知の落とし穴

### プロジェクトのパスに日本語が入っていると release ビルドが落ちる

AOT スナップショッタが `app.dill` を読めずに失敗する。

```text
Error: Unable to read file: ...\.dart_tool\flutter_build\...\app.dill
Dart snapshot generator failed with exit code 255
```

同じ理由で `aapt` も APK を開けず、`flutter run` 時に
`Illegal byte sequence` の警告が出る（ビルド自体は通る）。

**対処**：プロジェクトを `C:\dev\sns-novahack` のような ASCII のみのパスに置く。
どうしても動かせない場合は、`git archive HEAD` で ASCII パスに展開してそこで
release をビルドする。debug ビルドは AOT を通らないので日本語パスでも通る。

Gradle 側のパスチェックは `android/gradle.properties` の
`android.overridePathCheck=true` で無効化済み。これが無いとそもそもビルドが始まらない。

### エミュレータが突然何も描画しなくなる

アプリが起動しているのに画面が真っ黒になることがある。Flutter ではなく
エミュレータの GPU 状態が壊れている。`home` を単色の `ColoredBox` にしても
黒いままなら確実にこれ。

**対処**：コールドブートし直す。

```bash
adb emu kill
```

```bash
emulator -avd Medium_Phone -no-snapshot-load
```

`-gpu swiftshader_indirect`（ソフトウェア描画）はエミュレータ自体が
セグフォで落ちたので使わないこと。

### AVD 名が「Phone」でも電話機とは限らない

`Test13_08_A16_Phone` は 1024x600 @160dpi のタブレット相当。
起動前に解像度を確認したほうが早い。

```bash
grep -E "hw.lcd" ~/.android/avd/<AVD名>.avd/config.ini
```

電話機サイズなのは `Medium_Phone`（1080x2400 @420dpi）や `Pixel_9a`（1080x2424 @420dpi）。

### BLE はエミュレータで検証できない

近距離検知は実機2台でしか確認できない。エミュレータでは権限ダイアログと
「Bluetoothの利用許可が必要です」の表示までしか確認できていない。

BLE 抜きで各状態の画面を確認したい場合は `lib/proximity/proximity_service.dart` の
`FakeProximityService` に差し替える（仕様書 15 のダミー経路）。
`lib/screens/main_shell.dart` の `_proximity` の初期化を
`BleProximityService()` から `FakeProximityService()` に変えるだけ。
