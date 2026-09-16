# sns-novahack Flutter Android Docker Environment

Flutter で Android アプリをビルドするための Docker 環境です。

## Build the Docker image

```bash
docker compose build
```

## Create a Flutter app in this folder

```bash
docker compose run --rm flutter-android flutter create .
```

## Install dependencies

```bash
docker compose run --rm flutter-android flutter pub get
```

## Build Android APK

```bash
docker compose run --rm flutter-android flutter build apk
```

The APK is normally created here:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Run on a device or emulator

Start adb on the host first:

```bash
adb start-server
docker compose run --rm flutter-android adb devices
docker compose run --rm flutter-android flutter run
```

Docker Desktop uses `host.docker.internal` so adb in the container can talk to the host adb server.
