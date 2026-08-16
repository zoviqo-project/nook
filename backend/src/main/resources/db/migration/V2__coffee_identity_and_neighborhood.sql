ALTER TABLE user_profiles
    ADD COLUMN preferred_vibe VARCHAR(30),
    ADD COLUMN coffees_per_day SMALLINT,
    ADD COLUMN favorite_coffee_moment VARCHAR(30),
    ADD CONSTRAINT coffees_per_day_range CHECK (coffees_per_day BETWEEN 0 AND 4);

ALTER TABLE coffee_shops ADD COLUMN neighborhood VARCHAR(100);

CREATE INDEX idx_profiles_coffee_affinity
    ON user_profiles(preferred_vibe, favorite_coffee_moment);
