# Docker で Flutter をビルドする

Flutter を直接インストールせずに Android アプリをビルドするための環境。
Firebase CLI と flutterfire_cli も入っている。

ホストに Flutter を入れているなら、こちらは使わなくてよい。

## イメージのビルド

```bash
docker compose build
```

## 依存の取得

```bash
docker compose run --rm flutter-android flutter pub get
```

## APK のビルド

```bash
docker compose run --rm flutter-android flutter build apk
```

APK はここに出る。

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 実機・エミュレータで動かす

先にホスト側で adb を起動する。

```bash
adb start-server
```

```bash
docker compose run --rm flutter-android adb devices
```

```bash
docker compose run --rm flutter-android flutter run
```

## 永続化しているもの

`docker-compose.yml` で名前付きボリュームにしてあるので、コンテナを作り直しても消えない。

| ボリューム | 中身 |
|---|---|
| `flutter-pub-cache` | pub のキャッシュ |
| `gradle-cache` | Gradle のキャッシュ |
| `android-sdk` | Android SDK |
| `firebase-config` | Firebase CLI の認証情報 |
| `android-debug-keystore` | デバッグ用の署名鍵 |

**デバッグ鍵を永続化しているのは重要**。作り直すたびに鍵が変わると SHA-1 も変わり、
Google ログインが `ApiException: 10` で失敗するようになる
（[docs/SETUP.md](SETUP.md#3-firebase--自分の-sha-1-を登録する) 参照）。

なお、この永続化が効くのはコンテナ内でビルドした場合だけ。**ホストで直接ビルドすると
ホスト側の `~/.android/debug.keystore` が使われる**ので、そちらの SHA-1 も
Firebase に登録が必要になる。
