ALTER TABLE user_preferences
  ADD COLUMN IF NOT EXISTS desired_genders TEXT,
  ADD COLUMN IF NOT EXISTS intentions TEXT,
  ADD COLUMN IF NOT EXISTS coffee_types TEXT,
  ADD COLUMN IF NOT EXISTS preferred_vibes TEXT,
  ADD COLUMN IF NOT EXISTS preferred_moments TEXT,
  ADD COLUMN IF NOT EXISTS meeting_styles TEXT;
