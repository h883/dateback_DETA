-- beacon_id を固定にしていると、一度電波を盗聴されただけで無期限に
-- なりすまし・接触記録の偽装ができてしまう（セキュリティレビューで指摘）。
-- 定期的にローテーションし、直前世代だけ猶予として残す。
ALTER TABLE users ADD COLUMN beacon_id_prev TEXT;
ALTER TABLE users ADD COLUMN beacon_rotated_at INTEGER;
