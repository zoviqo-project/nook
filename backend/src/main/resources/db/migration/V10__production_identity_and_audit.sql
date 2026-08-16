CREATE TYPE auth_provider AS ENUM ('APPLE','GOOGLE','FACEBOOK','PHONE','EMAIL');
CREATE TYPE user_status AS ENUM ('ACTIVE','SUSPENDED','DELETED');

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(32);
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(80);
ALTER TABLE users ADD COLUMN IF NOT EXISTS status user_status NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE users ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_users_phone ON users(phone) WHERE phone IS NOT NULL;

CREATE TABLE auth_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider auth_provider NOT NULL,
  provider_subject VARCHAR(255) NOT NULL,
  email VARCHAR(255), phone VARCHAR(32),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_subject)
);
CREATE INDEX idx_auth_identity_user ON auth_identities(user_id);

CREATE TABLE phone_otp_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), phone VARCHAR(32) NOT NULL,
  code_hash VARCHAR(64) NOT NULL, attempts SMALLINT NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL, consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_phone_otp_active ON phone_otp_challenges(phone, expires_at DESC);

CREATE TABLE user_settings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  coffee_sounds_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  locale VARCHAR(12) NOT NULL DEFAULT 'es',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE user_locations (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL, longitude DOUBLE PRECISION NOT NULL,
  accuracy_meters DOUBLE PRECISION, captured_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK(latitude BETWEEN -90 AND 90), CHECK(longitude BETWEEN -180 AND 180)
);

CREATE TABLE passes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK(sender_id <> receiver_id), UNIQUE(sender_id, receiver_id)
);
CREATE INDEX idx_passes_sender ON passes(sender_id, created_at DESC);

CREATE TABLE favorite_cafes (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cafe_id UUID NOT NULL REFERENCES coffee_shops(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(user_id, cafe_id)
);
CREATE TABLE cafe_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), cafe_id UUID NOT NULL REFERENCES coffee_shops(id) ON DELETE CASCADE,
  provider_reference TEXT NOT NULL, position SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(cafe_id, position)
);

CREATE TABLE conversation_participants (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_read_at TIMESTAMPTZ,
  PRIMARY KEY(conversation_id, user_id)
);
INSERT INTO conversation_participants(conversation_id,user_id)
SELECT c.id,m.user_one_id FROM conversations c JOIN matches m ON m.id=c.match_id ON CONFLICT DO NOTHING;
INSERT INTO conversation_participants(conversation_id,user_id)
SELECT c.id,m.user_two_id FROM conversations c JOIN matches m ON m.id=c.match_id ON CONFLICT DO NOTHING;

CREATE TABLE coffee_proposal_participants (
  proposal_id UUID NOT NULL REFERENCES coffee_date_proposals(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL CHECK(role IN ('PROPOSER','RECIPIENT')),
  PRIMARY KEY(proposal_id,user_id)
);
INSERT INTO coffee_proposal_participants(proposal_id,user_id,role)
SELECT id,sender_id,'PROPOSER' FROM coffee_date_proposals ON CONFLICT DO NOTHING;
INSERT INTO coffee_proposal_participants(proposal_id,user_id,role)
SELECT id,receiver_id,'RECIPIENT' FROM coffee_date_proposals ON CONFLICT DO NOTHING;

CREATE TABLE audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  event_type VARCHAR(64) NOT NULL, resource_type VARCHAR(64), resource_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_actor_time ON audit_events(actor_user_id, created_at DESC);
CREATE INDEX idx_audit_event_time ON audit_events(event_type, created_at DESC);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS client_message_id UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uk_message_client_id ON messages(conversation_id,client_message_id)
  WHERE client_message_id IS NOT NULL;
ALTER TABLE coffee_date_proposals ADD COLUMN IF NOT EXISTS idempotency_key UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uk_proposal_idempotency ON coffee_date_proposals(sender_id,idempotency_key)
  WHERE idempotency_key IS NOT NULL;

