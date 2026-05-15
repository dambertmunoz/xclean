-- xclean initial schema.
--
-- All tables are prefixed `xclean_` so this Supabase project can be
-- safely shared across multiple products without name collisions.
-- Idempotent via IF NOT EXISTS; run via `supabase db query --linked --file`.

CREATE TABLE IF NOT EXISTS xclean_submissions (
  id          BIGSERIAL PRIMARY KEY,
  email       TEXT NOT NULL,
  name        TEXT,
  proof_path  TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'approved', 'rejected')),
  license_key TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_xclean_submissions_status     ON xclean_submissions(status);
CREATE INDEX IF NOT EXISTS idx_xclean_submissions_created_at ON xclean_submissions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_xclean_submissions_email      ON xclean_submissions(email);

CREATE TABLE IF NOT EXISTS xclean_licenses (
  key         TEXT PRIMARY KEY,
  email       TEXT NOT NULL,
  plan        TEXT NOT NULL DEFAULT 'annual',
  status      TEXT NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'revoked', 'expired')),
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_xclean_licenses_email  ON xclean_licenses(email);
CREATE INDEX IF NOT EXISTS idx_xclean_licenses_status ON xclean_licenses(status);

CREATE TABLE IF NOT EXISTS xclean_activations (
  id              BIGSERIAL PRIMARY KEY,
  license_key     TEXT NOT NULL REFERENCES xclean_licenses(key) ON DELETE CASCADE,
  machine_id      TEXT NOT NULL,
  machine_label   TEXT,
  activated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deactivated_at  TIMESTAMPTZ
);

-- DB-enforced "one active activation per license". Partial index races
-- to insert a second active row will reject at the database level.
CREATE UNIQUE INDEX IF NOT EXISTS xclean_activations_one_active
  ON xclean_activations (license_key)
  WHERE deactivated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_xclean_activations_machine ON xclean_activations(machine_id);
