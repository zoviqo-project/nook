CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TYPE gender AS ENUM ('WOMAN','MAN','NON_BINARY','OTHER');
CREATE TYPE looking_for AS ENUM ('MEET_PEOPLE','FRIENDSHIP','SOMETHING_MORE','SEE_WHAT_HAPPENS');
CREATE TYPE date_status AS ENUM ('PENDING','ACCEPTED','DECLINED','CANCELLED','COMPLETED');
CREATE TYPE payment_preference AS ENUM ('I_INVITE','THEY_INVITE','SPLIT','DECIDE_THERE');

CREATE TABLE users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), email VARCHAR(255) NOT NULL, password_hash VARCHAR(255) NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE, hidden BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), CONSTRAINT uk_users_email UNIQUE(email));
CREATE TABLE user_profiles (user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, name VARCHAR(80) NOT NULL, birth_date DATE NOT NULL, gender gender NOT NULL, bio VARCHAR(500) NOT NULL DEFAULT '', city VARCHAR(100), latitude DOUBLE PRECISION, longitude DOUBLE PRECISION, looking_for looking_for NOT NULL, coffee_personality VARCHAR(80), preferred_plan VARCHAR(60), onboarding_complete BOOLEAN NOT NULL DEFAULT FALSE, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), CONSTRAINT adult_birth CHECK (birth_date <= CURRENT_DATE - INTERVAL '18 years'));
CREATE TABLE user_preferences (user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, min_age SMALLINT NOT NULL DEFAULT 18, max_age SMALLINT NOT NULL DEFAULT 45, max_distance_km SMALLINT NOT NULL DEFAULT 30, visible BOOLEAN NOT NULL DEFAULT TRUE, CHECK(min_age>=18 AND max_age>=min_age), CHECK(max_distance_km BETWEEN 1 AND 200));
CREATE TABLE coffee_preferences (user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, preference VARCHAR(30) NOT NULL, PRIMARY KEY(user_id,preference));
CREATE TABLE user_photos (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, url VARCHAR(500) NOT NULL, position SMALLINT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(user_id,position));
CREATE INDEX idx_photos_user ON user_photos(user_id);

CREATE TABLE coffee_likes (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CONSTRAINT no_self_like CHECK(sender_id<>receiver_id), UNIQUE(sender_id,receiver_id));
CREATE INDEX idx_likes_receiver ON coffee_likes(receiver_id,sender_id);
CREATE TABLE matches (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_one_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, user_two_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK(user_one_id<user_two_id), UNIQUE(user_one_id,user_two_id));
CREATE INDEX idx_matches_one ON matches(user_one_id,active); CREATE INDEX idx_matches_two ON matches(user_two_id,active);
CREATE TABLE conversations (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), match_id UUID NOT NULL UNIQUE REFERENCES matches(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE messages (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, body VARCHAR(2000) NOT NULL, message_type VARCHAR(30) NOT NULL DEFAULT 'TEXT', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), read_at TIMESTAMPTZ);
CREATE INDEX idx_messages_conversation ON messages(conversation_id,created_at);

CREATE TABLE coffee_shops (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), provider VARCHAR(30) NOT NULL DEFAULT 'SEED', provider_id VARCHAR(100), name VARCHAR(160) NOT NULL, address VARCHAR(300) NOT NULL, latitude DOUBLE PRECISION NOT NULL, longitude DOUBLE PRECISION NOT NULL, photo_url VARCHAR(500), opening_hours VARCHAR(300), rating NUMERIC(2,1), description VARCHAR(300), active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(provider,provider_id));
CREATE INDEX idx_shops_coordinates ON coffee_shops(latitude,longitude);
CREATE TABLE coffee_shop_vibes (coffee_shop_id UUID NOT NULL REFERENCES coffee_shops(id) ON DELETE CASCADE, vibe VARCHAR(30) NOT NULL, PRIMARY KEY(coffee_shop_id,vibe));
CREATE TABLE coffee_date_proposals (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), sender_id UUID NOT NULL REFERENCES users(id), receiver_id UUID NOT NULL REFERENCES users(id), match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE, coffee_shop_id UUID NOT NULL REFERENCES coffee_shops(id), proposed_at TIMESTAMPTZ NOT NULL, payment_preference payment_preference NOT NULL, status date_status NOT NULL DEFAULT 'PENDING', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK(sender_id<>receiver_id));
CREATE INDEX idx_dates_match ON coffee_date_proposals(match_id,status,proposed_at); CREATE INDEX idx_dates_receiver ON coffee_date_proposals(receiver_id,status);

CREATE TABLE blocks (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK(blocker_id<>blocked_id), UNIQUE(blocker_id,blocked_id));
CREATE INDEX idx_blocks_reverse ON blocks(blocked_id,blocker_id);
CREATE TABLE reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id UUID NOT NULL REFERENCES users(id), reported_id UUID NOT NULL REFERENCES users(id), reason VARCHAR(80) NOT NULL, details VARCHAR(1000), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK(reporter_id<>reported_id));
CREATE TABLE notifications (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, type VARCHAR(40) NOT NULL, title VARCHAR(160) NOT NULL, body VARCHAR(500) NOT NULL, resource_id UUID, read_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_notifications_user ON notifications(user_id,created_at DESC);
CREATE TABLE refresh_tokens (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, token_hash VARCHAR(64) NOT NULL UNIQUE, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_refresh_user ON refresh_tokens(user_id);
CREATE TABLE device_tokens (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, token VARCHAR(300) NOT NULL UNIQUE, platform VARCHAR(20) NOT NULL DEFAULT 'IOS', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
