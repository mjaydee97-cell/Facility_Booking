-- Facility Booking and Utilization Monitoring — PostgreSQL schema
-- Safe to run repeatedly (idempotent).

CREATE EXTENSION IF NOT EXISTS btree_gist;   -- lets the EXCLUDE constraint mix "=" and "&&"
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid()

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('user', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE booking_status AS ENUM (
    'pending',     -- waiting for admin approval
    'approved',    -- confirmed, not yet used
    'rejected',    -- declined by admin
    'cancelled',   -- cancelled by the user (or admin)
    'checked_in',  -- user scanned the facility QR; facility in use
    'completed',   -- usage finished (checked out or auto-completed)
    'no_show'      -- not checked in within the grace period; slot released
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  name          TEXT        NOT NULL,
  email         TEXT        NOT NULL UNIQUE,
  password_hash TEXT        NOT NULL,
  role          user_role   NOT NULL DEFAULT 'user',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS facilities (
  id                SERIAL PRIMARY KEY,
  name              TEXT        NOT NULL,
  description       TEXT        NOT NULL DEFAULT '',
  location          TEXT        NOT NULL DEFAULT '',
  capacity          INTEGER     NOT NULL CHECK (capacity > 0),
  open_time         TIME        NOT NULL DEFAULT '07:00',
  close_time        TIME        NOT NULL DEFAULT '21:00',
  requires_approval BOOLEAN     NOT NULL DEFAULT false,
  is_active         BOOLEAN     NOT NULL DEFAULT true,
  -- Secret encoded in the QR code posted at the facility entrance.
  checkin_token     UUID        NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (close_time > open_time)
);

CREATE TABLE IF NOT EXISTS bookings (
  id                SERIAL PRIMARY KEY,
  facility_id       INTEGER        NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
  user_id           INTEGER        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  starts_at         TIMESTAMPTZ    NOT NULL,
  ends_at           TIMESTAMPTZ    NOT NULL,
  purpose           TEXT           NOT NULL,
  attendees         INTEGER        NOT NULL DEFAULT 1 CHECK (attendees > 0),
  status            booking_status NOT NULL,
  admin_remarks     TEXT,
  checked_in_at     TIMESTAMPTZ,
  checked_out_at    TIMESTAMPTZ,
  reminder_sent_at  TIMESTAMPTZ,
  created_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  -- The core guarantee: two "live" bookings for the same facility can never
  -- overlap in time, even if two requests arrive at the same instant.
  CONSTRAINT no_double_booking EXCLUDE USING gist (
    facility_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (status IN ('pending', 'approved', 'checked_in'))
);

CREATE INDEX IF NOT EXISTS bookings_user_idx     ON bookings (user_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS bookings_facility_idx ON bookings (facility_id, starts_at);
CREATE INDEX IF NOT EXISTS bookings_status_idx   ON bookings (status, starts_at);

CREATE TABLE IF NOT EXISTS device_tokens (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL UNIQUE,
  platform   TEXT        NOT NULL DEFAULT 'unknown',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notifications (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      TEXT        NOT NULL,
  body       TEXT        NOT NULL,
  booking_id INTEGER     REFERENCES bookings(id) ON DELETE SET NULL,
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx ON notifications (user_id, created_at DESC);
