ALTER TABLE coffee_shops ADD COLUMN review_count INTEGER;
ALTER TABLE coffee_shops ADD COLUMN open_now BOOLEAN;
ALTER TABLE coffee_shops ADD COLUMN price_level VARCHAR(40);
ALTER TABLE coffee_shops ADD COLUMN website VARCHAR(500);
ALTER TABLE coffee_shops ADD COLUMN phone VARCHAR(80);
ALTER TABLE coffee_shops ADD COLUMN maps_url VARCHAR(700);
ALTER TABLE coffee_shops ADD COLUMN types TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_coffee_shops_provider_identity ON coffee_shops(provider, provider_id);
