-- seed.sql
--
-- Generates realistic-ish demo data purely in SQL (no external scripting
-- language needed) so it can be run the same way migrations are run:
--   psql -f sql/seed/seed.sql
--
-- Safe to re-run: it truncates the two tables first, so you always end up
-- with a known, consistent data set.

BEGIN;

TRUNCATE TABLE booking_events, hotel_bookings RESTART IDENTITY CASCADE;

WITH
  orgs (org_id) AS (
    VALUES
      ('11111111-1111-1111-1111-111111111111'::uuid),
      ('22222222-2222-2222-2222-222222222222'::uuid),
      ('33333333-3333-3333-3333-333333333333'::uuid),
      ('44444444-4444-4444-4444-444444444444'::uuid)
  ),
  cities (city) AS (
    VALUES ('delhi'), ('mumbai'), ('bengaluru'), ('pune'), ('hyderabad')
  ),
  statuses (status) AS (
    VALUES ('confirmed'), ('cancelled'), ('pending'), ('completed')
  ),
  numbered_orgs AS (
    SELECT org_id, row_number() OVER () - 1 AS idx FROM orgs
  ),
  numbered_cities AS (
    SELECT city, row_number() OVER () - 1 AS idx FROM cities
  ),
  numbered_statuses AS (
    SELECT status, row_number() OVER () - 1 AS idx FROM statuses
  ),
  generated AS (
    SELECT
      gs AS n,
      (SELECT org_id FROM numbered_orgs WHERE idx = gs % 4) AS org_id,
      (SELECT city FROM numbered_cities WHERE idx = gs % 5) AS city,
      -- offset by +2 so city and status don't move in lockstep
      (SELECT status FROM numbered_statuses WHERE idx = (gs + 2) % 4) AS status,
      (CURRENT_DATE - ((gs % 90) || ' days')::interval)::date AS checkin_date,
      (CURRENT_DATE - ((gs % 90) || ' days')::interval
        + (1 + (gs % 5)) * interval '1 day')::date AS checkout_date,
      (2000 + (gs * 37) % 15000)::numeric(12, 2) AS amount,
      -- spread created_at over the last ~60 days so a "last 30 days"
      -- filter (used by the report query) returns a meaningful subset
      now() - ((gs % 60) || ' days')::interval - ((gs % 24) || ' hours')::interval AS created_at
    FROM generate_series(1, 150) AS gs
  )
INSERT INTO hotel_bookings (org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
  org_id,
  'HTL-' || lpad((100 + n)::text, 4, '0'),
  city,
  checkin_date,
  checkout_date,
  amount,
  status,
  created_at
FROM generated;

-- Attach 1 event to roughly 60% of the bookings just created, so
-- booking_events has realistic partial coverage rather than every booking
-- having identical event history.
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
  b.id,
  (ARRAY['created', 'payment_confirmed', 'cancelled', 'checked_in', 'checked_out'])[1 + (floor(random() * 5))::int],
  jsonb_build_object('source', 'seed-script', 'note', 'auto-generated event'),
  b.created_at + interval '1 hour'
FROM hotel_bookings b
WHERE random() < 0.6;

COMMIT;

-- Quick sanity counts (visible when running via `psql -f`)
SELECT 'hotel_bookings' AS table_name, COUNT(*) AS row_count FROM hotel_bookings
UNION ALL
SELECT 'booking_events', COUNT(*) FROM booking_events
UNION ALL
SELECT 'delhi bookings (any time)', COUNT(*) FROM hotel_bookings WHERE city = 'delhi'
UNION ALL
SELECT 'delhi bookings (last 30 days)', COUNT(*) FROM hotel_bookings
  WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days';
