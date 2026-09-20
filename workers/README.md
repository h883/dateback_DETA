# bloom-api （Cloudflare Workers）

本SNS のバックエンド。投稿・フレンド・閲覧権限を D1 で、画像と動画を KV で管理する。
KV を選んだ理由と制約は [仕様書 6.1](../仕様書.md) を参照。

仕様書 4.4 のとおり、**投稿を見てよいかどうかの判定はすべてここで行う**。
API はその時点で閲覧可能な投稿だけを返すので、アプリ側で投稿時刻と閲覧可能時刻を
突き合わせる処理は書かないこと。

## 構成

| ファイル | 内容 |
|---|---|
| `src/index.ts` | ルーティングと全エンドポイント |
| `src/auth.ts` | Firebase ID トークンの検証（JWKS + WebCrypto） |
| `migrations/0001_init.sql` | D1 のスキーマ |
| `wrangler.jsonc` | Worker / D1 / KV の設定 |

## セットアップ

Cloudflare のアカウントは `user@example.com`（account_id は `wrangler.jsonc` に記載済み）。

```bash
cd workers
npm install
npx wrangler login
```

D1 と KV を作る。それぞれが出力する id を `wrangler.jsonc` の
`d1_databases[].database_id` と `kv_namespaces[].id` に貼り替える
（既存の本番環境に繋ぐだけなら、どちらも記載済みなので作り直さない）。

```bash
npx wrangler d1 create bloom
```

```bash
npx wrangler kv namespace create MEDIA
```

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
| GET | `/api/media/:key` | KV のメディア配信 |

## 閲覧制御のしくみ

`view_permissions (viewer_uid, author_uid, visible_until)` が「viewer から見た
author の投稿は visible_until 以前まで見られる」を表す。

`POST /api/proximity` が呼ばれると、フレンドであることを確かめたうえで
双方向にこの行を「今」へ更新する（仕様書 4.3）。同じ相手とは
`PROXIMITY_COOLDOWN_MS`（60秒）の間は新しいイベントとして扱わない（仕様書 6.3）。

投稿の取得は `VISIBLE_POSTS_SQL` を通す。自分の投稿は常に見え、他人の投稿は
上の行があり、かつ `posts.created_at <= visible_until` のものだけが返る。

## メディア（KV）の運用上の注意

KV は「消えては困るものを置く永続ストア」だが、読み取り経路がキャッシュの
ように各地へ配られる作りのため、メディア置き場としては次の癖がある。

| 制約（無料枠） | 値 | 効いてくる場所 |
|---|---|---|
| ストレージ | **namespace 全体で 1GB** | いちばん先に当たる。35mm は投稿前に長辺 1600px / JPEG quality 85 へ縮小している（`lib/screens/tabs/post_tab.dart`） |
| 書き込み | 1,000 回／日 | 1 投稿 = 1 write、アイコン変更 = 1 write + 1 delete |
| 読み取り | 100,000 回／日 | 表示のたびに1回 |
| 1 値のサイズ | 25MB | `MAX_MEDIA_BYTES` がこの上限そのもの |

- **結果整合性**：`put` 直後の `get` は伝播が終わるまで `null` を返しうる。
  `handleMedia` はこれを 404 にして返すので、アプリ側（`RemoteImage` /
  `RemoteVideo`）が 404 のときだけ間を置いて読み直す。
- **書き込み失敗**：上限に当たると `put` が例外を投げる。`putMedia()` が
  これを捕まえて `503 media_store_unavailable` に変換し、`wrangler tail` の
  ログへ残す（素の 500 にしない）。
- **古い実体は自動では消えない**：キャッシュと違い KV は勝手に捨てないので、
  アイコンを差し替えたときは `putAvatar` が古いキーを明示的に削除する。

## 未実装

- BLE そのもの。`POST /api/proximity` は「相手の uid が分かっている」前提で、
  近くにいることの確認はクライアント側の責務になっている。
  仕様書 16 の近距離識別情報が決まったら、ここに検証を足す必要がある。
- `/api/users/nearby` は BLE が入るまでの仮実装で、
  実際には「自分ともフレンドでもない既存ユーザー」を新しい順に返しているだけ。
- 閲覧権限の再伝播（仕様書 F-14）。
