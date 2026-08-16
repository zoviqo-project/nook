ALTER TABLE messages ALTER COLUMN sender_id DROP NOT NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS metadata JSONB;

ALTER TABLE coffee_date_proposals
  ADD COLUMN IF NOT EXISTS coffee_shop_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uk_active_coffee_date_per_match
  ON coffee_date_proposals(match_id)
  WHERE status IN ('PENDING'::date_status, 'COUNTER_PROPOSED'::date_status);

CREATE INDEX IF NOT EXISTS idx_dates_history
  ON coffee_date_proposals(sender_id, receiver_id, status, proposed_at DESC);
