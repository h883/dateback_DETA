# 画像・動画共有SNS（NovaHack 2026）

友人同士が**実際に近距離で会ったことをきっかけに**、それまでの投稿の閲覧権限が
解放される SNS。フレンドになっただけでは相手の投稿は見えない。

## いちばん大事な仕様

「viewer から見た author の投稿は、閲覧可能時刻より前のものだけ見える」。

近距離イベントが成立すると双方の閲覧可能時刻が「今」に更新され、それ以降に
投稿されたものは次に会うまで見えない。

**閲覧可否の判定はすべてバックエンドで行う**（仕様書 4.4）。API はその時点で
閲覧可能な投稿だけを返すので、アプリ側で投稿時刻と閲覧可能時刻を突き合わせる
処理は書かないこと。

## 構成

| | |
|---|---|
| アプリ | Flutter / Dart（Android） |
| 認証 | Firebase Authentication（Google ログイン） |
| API | Cloudflare Workers（TypeScript） |
| DB | Cloudflare D1 |
| 画像・動画 | Cloudflare KV |
| 近距離検知 | BLE（アドバタイズ + スキャン） |

```text
lib/
  api/          Worker を叩くクライアント
  models/       API レスポンスのモデル
  proximity/    近距離検知（BLE 実装とダミー）
  screens/      画面
  theme/        デザイントークン
  widgets/      共通ウィジェット
workers/        Cloudflare Workers のバックエンド
```

画面は左から **投稿 ｜ ホーム ｜ プロフィール ｜ フレンド追加** の横並びで、
起動時はホーム（仕様書 8）。

## はじめに読むもの

**[docs/SETUP.md](docs/SETUP.md)** — 別の端末で動かすときはここから。
clone しただけでは動かない箇所（Firebase の SHA-1 登録など）と、
はまりやすい落とし穴をまとめてある。

[workers/README.md](workers/README.md) — バックエンドのエンドポイント一覧と
閲覧制御の仕組み。

## 動かす

```bash
flutter pub get
```

```bash
flutter run
```

既定で本番の Worker（`https://bloom-api.example.workers.dev`）につながる。
ローカルの Worker を使う方法は [docs/SETUP.md](docs/SETUP.md#5-動かす) を参照。

## 未実装

- 閲覧権限の再伝播（仕様書 F-14／追加機能）
- iOS の設定一式（`GoogleService-Info.plist`、カメラの使用目的文言）
- 新しい画面と Worker のテスト

BLE は実装済みだが、**実機2台での通信は未検証**。
エミュレータでは権限まわりまでしか確認できていない。

## Docker

Docker でビルドする場合は [docs/DOCKER.md](docs/DOCKER.md) を参照。
