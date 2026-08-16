CREATE UNIQUE INDEX IF NOT EXISTS uq_google_coffee_shop_place_id
  ON coffee_shops(provider_id)
  WHERE provider = 'GOOGLE' AND provider_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_google_coffee_shop_location
  ON coffee_shops(latitude, longitude)
  WHERE provider = 'GOOGLE' AND active = TRUE;
