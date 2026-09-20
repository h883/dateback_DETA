# bloom-api （Cloudflare Workers）

本SNS のバックエンド。投稿・フレンド・閲覧権限を D1 で、画像と動画を **R2** で管理する。
以前は R2 のカード登録を避けて KV に置いていたが、KV の制約（ストレージ 1GB・
書き込み 1,000回/日・結果整合性）がメディアに合わないため R2 へ移した。
経緯は [仕様書 6.1](../仕様書.md) を参照。

仕様書 4.4 のとおり、**投稿を見てよいかどうかの判定はすべてここで行う**。
API はその時点で閲覧可能な投稿だけを返すので、アプリ側で投稿時刻と閲覧可能時刻を
突き合わせる処理は書かないこと。

## 構成

| ファイル | 内容 |
|---|---|
| `src/index.ts` | ルーティングと全エンドポイント |
| `src/auth.ts` | Firebase ID トークンの検証（JWKS + WebCrypto） |
| `migrations/0001_init.sql` | D1 のスキーマ |
| `wrangler.jsonc` | Worker / D1 / R2 / 旧 KV の設定 |

## セットアップ

Cloudflare のアカウントは `user@example.com`（account_id は `wrangler.jsonc` に記載済み）。

```bash
cd workers
npm install
npx wrangler login
```

D1 と R2 バケットを作る。`d1 create` が出力する id は `wrangler.jsonc` の
`d1_databases[].database_id` に貼り替える（既存の本番環境に繋ぐだけなら
記載済みなので作り直さない）。

```bash
npx wrangler d1 create bloom
```

```bash
npx wrangler r2 bucket create bloom-media
```

**R2 の有効化には Cloudflare アカウントへの支払い方法の登録が必要になる場合が
ある。** 無料枠（ストレージ 10GB / Class A 100万・Class B 1,000万 ops 月・
エグレス無料）に収まっていれば請求は発生しないが、バケット作成が弾かれたら
その登録を先に済ませること。

スキーマを流す。

```bash
npx wrangler d1 migrations apply bloom --remote
```

デプロイ。

```bash
npx wrangler deploy
```

## アプリ側の接続先

デプロイすると `https://bloom-api.<subdomain>.workers.dev` が出るので、
それを Flutter に渡す。

```bash
flutter run --dart-define=BLOOM_API_BASE_URL=https://bloom-api.example.workers.dev
```

`lib/api/bloom_api.dart` の `defaultBaseUrl` を書き換えてもよい。

## ローカルで動かす

```bash
npx wrangler d1 migrations apply bloom --local
```

```bash
npx wrangler dev
```

## エンドポイント

すべて `Authorization: Bearer <Firebase ID トークン>` が必要。

| メソッド | パス | 用途 |
|---|---|---|
| GET | `/api/me` | 自分のプロフィール。未設定なら 404 `profile_not_set` |
| PUT | `/api/me` | ユーザー名・自己紹介の保存 |
| PUT | `/api/me/avatar` | アイコン画像（本文は生バイト） |
| GET | `/api/users/nearby` | フレンド追加モードの候補 |
| GET | `/api/users/:uid` | 他ユーザーのプロフィール |
| GET | `/api/users/:uid/posts` | その人の**閲覧可能な**投稿 |
| POST | `/api/posts` | 投稿。本文は生メディア、`X-Post-Kind: 35mm\|8mm` |
| GET | `/api/posts/mine` | 自分の投稿（常に全件） |
| GET | `/api/feed` | 閲覧可能な他人の投稿を投稿者ごとに |
| POST/DELETE | `/api/posts/:id/like` | いいね |
| GET | `/api/friends` | フレンド一覧（閲覧可能時刻つき） |
| GET | `/api/friends/requests` | 受信中／送信中の申請 |
| POST | `/api/friends/requests` | 申請する |
| POST | `/api/friends/requests/:uid/accept` | 承認 |
| DELETE | `/api/friends/requests/:uid` | 取り消し／却下 |
| POST | `/api/proximity` | 近距離イベントの記録と閲覧権限交換 |
| GET | `/api/media/:key` | R2 のメディア配信（Range 対応。R2 に無ければ旧 KV を見る） |

## 閲覧制御のしくみ

`view_permissions (viewer_uid, author_uid, visible_until)` が「viewer から見た
author の投稿は visible_until 以前まで見られる」を表す。

`POST /api/proximity` が呼ばれると、フレンドであることを確かめたうえで
双方向にこの行を「今」へ更新する（仕様書 4.3）。同じ相手とは
`PROXIMITY_COOLDOWN_MS`（60秒）の間は新しいイベントとして扱わない（仕様書 6.3）。

投稿の取得は `VISIBLE_POSTS_SQL` を通す。自分の投稿は常に見え、他人の投稿は
上の行があり、かつ `posts.created_at <= visible_until` のものだけが返る。

## メディア（R2）の運用と、旧 KV からの移行

### いまの動き

- **書き込みは R2 だけ**。`putMedia()` が `env.MEDIA`（R2 バケット
  `bloom-media`）へ `httpMetadata.contentType` 付きで置く。
- **読み取りは R2 を見て、無ければ旧 KV を見る**（`legacyKvMedia()`）。
  R2 へ移す前に投稿されたものは KV にしか無いため、この二段構えが無いと
  切り替えた瞬間に過去の投稿の画像が全部消える。
- `GET /api/media/:key` は `Range` と `If-None-Match` をそのまま R2 へ渡すので、
  部分取得（206）と 304 が効く。KV では原理的にできなかった。

### 移行の状態

| | 置き場 |
|---|---|
| R2 切り替え**後**に投稿されたもの | R2 のみ |
| R2 切り替え**前**に投稿されたもの | 旧 KV のみ（読み取りフォールバックで配信） |

**旧 KV へ新しい書き込みは一切行かない**ので、KV の容量がこれ以上増えることは
ない。放置しても壊れないため、移行は「急がなくてよい残作業」の扱いでよい。

### 旧 KV を空にする（任意）

KV を畳みたくなったら、`wrangler kv key list` で拾って R2 へ入れ直し、
最後に `wrangler.jsonc` の `kv_namespaces` と `src/index.ts` の
`legacyKvMedia()` / `Env.MEDIA_LEGACY_KV` をまとめて削除する。

> この一括コピーは本番データを触るため、**動作確認できていないスクリプトは
> 置いていない**。実行する場合は、まず1件だけ手で移して
> `GET /api/media/:key` が 200 を返すことを確かめてから全体へ広げること。

### 保存に失敗したとき

`putMedia()` が例外を捕まえて `503 media_store_unavailable` に変換し、
`console.error` へ残す（素の 500 にしない）。`npx wrangler tail bloom-api` で
その場で見える。

### 古い実体の掃除

アイコンを差し替えたときは `putAvatar` が旧キーを R2 と旧 KV の両方から
消しに行く。DB が新しいキーを指してから消す順序なので、掃除に失敗しても
アイコン変更そのものは成功する。

## 未実装

- BLE そのもの。`POST /api/proximity` は「相手の uid が分かっている」前提で、
  近くにいることの確認はクライアント側の責務になっている。
  仕様書 16 の近距離識別情報が決まったら、ここに検証を足す必要がある。
- `/api/users/nearby` は BLE が入るまでの仮実装で、
  実際には「自分ともフレンドでもない既存ユーザー」を新しい順に返しているだけ。
- 閲覧権限の再伝播（仕様書 F-14）。
