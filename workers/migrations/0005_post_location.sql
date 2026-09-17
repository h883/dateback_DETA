-- B2: 投稿への撮影地(粗いエリア名)追加。
--
-- 緯度経度そのものは保存しない。クライアントが reverse geocoding から
-- 組み立てた「市区町村」程度の粗い文字列だけを保存する(例: "大阪市 中央区")。
-- 既存投稿は NULL のまま(=撮影地なし)で問題なく読み込める。
ALTER TABLE posts ADD COLUMN location_label TEXT;
