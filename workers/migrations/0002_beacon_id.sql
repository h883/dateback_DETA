-- 仕様書 3.15 近距離識別情報。
--
-- BLE のアドバタイズ電文は 31 バイトしかなく、Firebase の uid（28文字）は
-- サービス UUID と併せると載らない。また 3.15 は「永続的なユーザーID や
-- 認証情報そのものを交換することは確定しない」としている。
--
-- そこでサーバーが 4 バイト（16進8文字）の beacon_id を発行し、
-- 電波に載せるのはこれだけにする。uid への解決はサーバーが行う。
ALTER TABLE users ADD COLUMN beacon_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_beacon_id_unique
  ON users (beacon_id);
