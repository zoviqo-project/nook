ALTER TABLE user_photos
  ADD COLUMN source VARCHAR(16) NOT NULL DEFAULT 'USER',
  ADD COLUMN provider VARCHAR(24);

CREATE UNIQUE INDEX uk_social_photo_per_provider
  ON user_photos(user_id, provider)
  WHERE source = 'SOCIAL';

ALTER TABLE coffee_date_proposals
  ADD COLUMN time_zone_id VARCHAR(80) NOT NULL DEFAULT 'UTC';

ALTER TABLE coffee_shops
  ADD COLUMN utc_offset_minutes INTEGER;

ALTER TABLE user_profiles ALTER COLUMN birth_date DROP NOT NULL;
ALTER TABLE user_profiles ALTER COLUMN gender DROP NOT NULL;
ALTER TABLE user_profiles ALTER COLUMN looking_for DROP NOT NULL;

CREATE OR REPLACE FUNCTION prefer_first_user_photo() RETURNS trigger AS $$
BEGIN
  IF NEW.source = 'USER' AND NOT EXISTS (
    SELECT 1 FROM user_photos WHERE user_id = NEW.user_id AND source = 'USER'
  ) THEN
    UPDATE user_photos SET is_primary = FALSE WHERE user_id = NEW.user_id;
    NEW.is_primary = TRUE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prefer_first_user_photo
BEFORE INSERT ON user_photos
FOR EACH ROW EXECUTE FUNCTION prefer_first_user_photo();
