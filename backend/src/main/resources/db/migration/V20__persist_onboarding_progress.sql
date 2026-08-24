ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS onboarding_step INTEGER NOT NULL DEFAULT 0;

ALTER TABLE user_profiles
  ADD CONSTRAINT chk_user_profiles_onboarding_step
  CHECK (onboarding_step BETWEEN 0 AND 15);

UPDATE user_profiles
SET onboarding_step = 15
WHERE onboarding_complete = TRUE AND onboarding_step < 15;
