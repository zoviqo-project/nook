ALTER TABLE user_profiles ALTER COLUMN gender TYPE VARCHAR(24) USING gender::text;
ALTER TABLE user_profiles ALTER COLUMN looking_for TYPE VARCHAR(32) USING looking_for::text;
DROP INDEX IF EXISTS uk_active_coffee_date_per_match;
ALTER TABLE coffee_date_proposals ALTER COLUMN status DROP DEFAULT;
ALTER TABLE coffee_date_proposals ALTER COLUMN status TYPE VARCHAR(32) USING status::text;
ALTER TABLE coffee_date_proposals ALTER COLUMN payment_preference TYPE VARCHAR(32) USING payment_preference::text;
ALTER TABLE coffee_date_proposals ALTER COLUMN status SET DEFAULT 'PENDING';
CREATE UNIQUE INDEX uk_active_coffee_date_per_match
  ON coffee_date_proposals(match_id)
  WHERE status IN ('PENDING', 'COUNTER_PROPOSED');
DROP TYPE gender;
DROP TYPE looking_for;
DROP TYPE date_status;
DROP TYPE payment_preference;
