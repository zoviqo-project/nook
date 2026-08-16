ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS is_primary BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE user_photos p SET is_primary = TRUE
WHERE position = (SELECT min(p2.position) FROM user_photos p2 WHERE p2.user_id=p.user_id);
CREATE UNIQUE INDEX uk_user_primary_photo ON user_photos(user_id) WHERE is_primary;
