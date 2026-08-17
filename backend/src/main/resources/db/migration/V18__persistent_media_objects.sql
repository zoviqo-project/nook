CREATE TABLE media_objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  filename VARCHAR(100) NOT NULL UNIQUE,
  content_type VARCHAR(80) NOT NULL,
  content BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
