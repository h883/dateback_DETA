-- 本SNS のデータを D1 で管理する。
-- uid は Firebase Auth の uid をそのまま主キーに使う。
-- 時刻はすべて UNIX ミリ秒（サーバー時刻）。

CREATE TABLE IF NOT EXISTS users (
  uid         TEXT PRIMARY KEY,
  username    TEXT NOT NULL,
  bio         TEXT NOT NULL DEFAULT '',
  avatar_key  TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

-- ユーザー名は大文字小文字を区別せず一意にする。
CREATE UNIQUE INDEX IF NOT EXISTS users_username_unique
  ON users (username COLLATE NOCASE);

CREATE TABLE IF NOT EXISTS posts (
  id           TEXT PRIMARY KEY,
  uid          TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  -- 35mm は静止画、8mm は2秒の動画。
  kind         TEXT NOT NULL CHECK (kind IN ('35mm', '8mm')),
  media_key    TEXT NOT NULL,
  content_type TEXT NOT NULL,
  -- 仕様書 3.7 投稿時刻。閲覧可否の判定に使う。
  created_at   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS posts_uid_created
  ON posts (uid, created_at DESC);

-- フレンド関係（仕様書 3.3）。片方向のフォローは持たない。
-- 申請の向きを保つため requester / addressee を正規化せずに保存する。
CREATE TABLE IF NOT EXISTS friendships (
  requester  TEXT NOT NULL,
  addressee  TEXT NOT NULL,
  status     TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (requester, addressee)
);

CREATE INDEX IF NOT EXISTS friendships_addressee
  ON friendships (addressee, status);

-- 仕様書 3.12 閲覧可能時刻。
-- 「viewer から見た author の投稿は visible_until 以前のものだけ見られる」。
CREATE TABLE IF NOT EXISTS view_permissions (
  viewer_uid    TEXT NOT NULL,
  author_uid    TEXT NOT NULL,
  visible_until INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  PRIMARY KEY (viewer_uid, author_uid)
);

-- 仕様書 3.10 近距離イベント。
-- 6.3 の「同一近距離状態では交換を繰り返さない」判定にも使う。
CREATE TABLE IF NOT EXISTS proximity_events (
  id          TEXT PRIMARY KEY,
  uid_a       TEXT NOT NULL,
  uid_b       TEXT NOT NULL,
  occurred_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS proximity_events_pair
  ON proximity_events (uid_a, uid_b, occurred_at DESC);

CREATE TABLE IF NOT EXISTS likes (
  post_id    TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  uid        TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, uid)
);
