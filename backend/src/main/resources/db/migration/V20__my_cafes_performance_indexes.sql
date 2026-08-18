CREATE INDEX IF NOT EXISTS idx_dates_sender_proposed
  ON coffee_date_proposals(sender_id, proposed_at DESC);

CREATE INDEX IF NOT EXISTS idx_dates_receiver_proposed
  ON coffee_date_proposals(receiver_id, proposed_at DESC);

CREATE INDEX IF NOT EXISTS idx_dates_status_proposed
  ON coffee_date_proposals(status, proposed_at);

CREATE INDEX IF NOT EXISTS idx_conversations_updated
  ON conversations(updated_at DESC);
