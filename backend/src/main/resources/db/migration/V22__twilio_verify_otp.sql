ALTER TABLE phone_otp_challenges ALTER COLUMN code_hash DROP NOT NULL;
ALTER TABLE phone_otp_challenges ADD COLUMN provider_reference VARCHAR(64);
