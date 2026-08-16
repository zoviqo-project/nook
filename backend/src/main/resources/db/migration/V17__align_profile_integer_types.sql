ALTER TABLE user_preferences
  ALTER COLUMN min_age TYPE INTEGER,
  ALTER COLUMN max_age TYPE INTEGER,
  ALTER COLUMN max_distance_km TYPE INTEGER;

ALTER TABLE user_profiles ALTER COLUMN coffees_per_day TYPE INTEGER;
