-- ユーザー名は Google アカウントの表示名をそのまま使えるようにする。
-- 日本語の名前も通すため、一意制約と英数字の縛りをやめた。
-- フレンドは BLE で見つける（仕様書 7.1）ので、検索用の一意なハンドルは要らない。
DROP INDEX IF EXISTS users_username_unique;

-- アプリ内の通知。
-- kind:
--   friend_request  … フレンド申請が届いた
--   friend_accepted … フレンドが成立した
--   proximity       … 近距離イベントで閲覧権限を交換した（仕様書 F-12）
--   like            … 自分の投稿にいいねが付いた
CREATE TABLE IF NOT EXISTS notifications (
  id         TEXT PRIMARY KEY,
  -- 受け取る人。
  uid        TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (
               kind IN ('friend_request', 'friend_accepted', 'proximity', 'like')
             ),
  -- きっかけになった相手。退会しても通知が消えないよう参照制約は付けない。
  actor_uid  TEXT,
  post_id    TEXT,
  read_at    INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS notifications_uid_created
  ON notifications (uid, created_at DESC);

-- 未読件数を数えるため。
CREATE INDEX IF NOT EXISTS notifications_uid_unread
  ON notifications (uid, read_at);
