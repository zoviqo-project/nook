ALTER TABLE auth_identities
  ALTER COLUMN provider TYPE VARCHAR(24) USING provider::text;
DROP TYPE auth_provider;
