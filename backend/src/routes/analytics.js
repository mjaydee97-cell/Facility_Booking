// Utilization monitoring. Definitions (all over the requested date range, local time):
//   available hours = opening hours per day × number of days
//   booked hours    = reserved time of bookings that held the slot (approved, checked_in, completed, no_show)
//   used hours      = actual time between check-in and check-out (or scheduled end)
//   booking rate    = booked / available       utilization rate = used / available
//   no-show rate    = no_show / (no_show + checked_in + completed)
const express = require('express');
const { z } = require('zod');
const db = require('../db');
const config = require('../config');
const { validate } = require('../middleware/validate');
const { requireAuth, requireAdmin } = require('../middleware/auth');
const { badRequest } = require('../errors');

const router = express.Router();
router.use(requireAuth, requireAdmin);

const dateStr = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use YYYY-MM-DD');
const querySchema = z.object({
  from: dateStr.optional(),
  to: dateStr.optional(),
  facility_id: z.coerce.number().int().positive().optional(),
});

const HELD = `('approved','checked_in','completed','no_show')`;
const round = (n, d = 2) => Math.round(Number(n) * 10 ** d) / 10 ** d;
const rate = (num, den) => (Number(den) > 0 ? round(Number(num) / Number(den), 4) : 0);

function localDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86_400_000);
  return d.toLocaleDateString('en-CA', { timeZone: config.timezone }); // YYYY-MM-DD
}

router.get('/summary', validate(querySchema, 'query'), async (req, res) => {
  const from = req.validQuery.from || localDate(-29);
  const to = req.validQuery.to || localDate(0);
  if (to < from) throw badRequest('"to" must not be before "from"');
  const facilityId = req.validQuery.facility_id || null;
  const tz = config.timezone;

  // $1 from, $2 to (inclusive), $3 tz, $4 facility filter (nullable)
  const ctes = `
    WITH rng AS (
      SELECT ($1::date)::timestamp AT TIME ZONE $3 AS r_start,
             ($2::date + 1)::timestamp AT TIME ZONE $3 AS r_end),
    fac AS (SELECT * FROM facilities WHERE ($4::int IS NULL OR id = $4)),
    bk AS (
      SELECT b.*,
             EXTRACT(EPOCH FROM LEAST(b.ends_at, r.r_end) - GREATEST(b.starts_at, r.r_start)) / 3600 AS held_h,
             CASE WHEN b.checked_in_at IS NOT NULL THEN GREATEST(0, EXTRACT(EPOCH FROM
                    LEAST(COALESCE(b.checked_out_at, LEAST(b.ends_at, now())), r.r_end)
                    - GREATEST(b.checked_in_at, r.r_start)) / 3600) ELSE 0 END AS used_h
        FROM bookings b JOIN fac ON fac.id = b.facility_id, rng r
       WHERE b.starts_at < r.r_end AND b.ends_at > r.r_start)`;
  const params = [from, to, tz, facilityId];

  const [perFacility, daily, hourly, weekday] = await Promise.all([
    db.query(
      `${ctes}
       SELECT fac.id, fac.name, fac.is_active,
              EXTRACT(EPOCH FROM fac.close_time - fac.open_time) / 3600
                * ($2::date - $1::date + 1)                                  AS available_hours,
              COUNT(bk.id)                                                   AS total_bookings,
              COUNT(bk.id) FILTER (WHERE bk.status = 'pending')              AS pending,
              COUNT(bk.id) FILTER (WHERE bk.status = 'approved')             AS approved,
              COUNT(bk.id) FILTER (WHERE bk.status = 'checked_in')           AS checked_in,
              COUNT(bk.id) FILTER (WHERE bk.status = 'completed')            AS completed,
              COUNT(bk.id) FILTER (WHERE bk.status = 'no_show')              AS no_show,
              COUNT(bk.id) FILTER (WHERE bk.status = 'cancelled')            AS cancelled,
              COUNT(bk.id) FILTER (WHERE bk.status = 'rejected')             AS rejected,
              COALESCE(SUM(bk.held_h) FILTER (WHERE bk.status IN ${HELD}), 0) AS booked_hours,
              COALESCE(SUM(bk.used_h), 0)                                    AS used_hours
         FROM fac LEFT JOIN bk ON bk.facility_id = fac.id
        WHERE fac.is_active OR bk.id IS NOT NULL
        GROUP BY fac.id, fac.name, fac.is_active, fac.open_time, fac.close_time
        ORDER BY fac.name`,
      params,
    ),
    db.query(
      `${ctes}
       SELECT to_char(d, 'YYYY-MM-DD') AS date,
              COALESCE(SUM(bk.held_h) FILTER (WHERE bk.status IN ${HELD}), 0) AS booked_hours,
              COALESCE(SUM(bk.used_h), 0) AS used_hours,
              COUNT(bk.id) AS bookings
         FROM generate_series($1::date, $2::date, interval '1 day') d
         LEFT JOIN bk ON (bk.starts_at AT TIME ZONE $3)::date = d::date
        GROUP BY d ORDER BY d`,
      params,
    ),
    // How many held bookings occupy each hour of the day — reveals peak periods.
    db.query(
      `${ctes}
       SELECT h AS hour, COUNT(bk.id) AS bookings
         FROM generate_series(0, 23) h
         LEFT JOIN bk ON bk.status IN ${HELD}
              AND h >= EXTRACT(HOUR FROM bk.starts_at AT TIME ZONE $3)
              AND h <  EXTRACT(HOUR FROM bk.starts_at AT TIME ZONE $3)
                       + CEIL(EXTRACT(EPOCH FROM bk.ends_at - date_trunc('hour', bk.starts_at)) / 3600)
        GROUP BY h ORDER BY h`,
      params,
    ),
    db.query(
      `${ctes}
       SELECT dow, COUNT(bk.id) AS bookings
         FROM generate_series(1, 7) dow
         LEFT JOIN bk ON bk.status IN ${HELD} AND EXTRACT(ISODOW FROM bk.starts_at AT TIME ZONE $3) = dow
        GROUP BY dow ORDER BY dow`,
      params,
    ),
  ]);

  const facilities = perFacility.rows.map((f) => {
    const attended = Number(f.no_show) + Number(f.checked_in) + Number(f.completed);
    const out = { ...f };
    for (const k of ['total_bookings', 'pending', 'approved', 'checked_in', 'completed', 'no_show', 'cancelled', 'rejected']) {
      out[k] = Number(f[k]);
    }
    out.available_hours = round(f.available_hours);
    out.booked_hours = round(f.booked_hours);
    out.used_hours = round(f.used_hours);
    out.booking_rate = rate(f.booked_hours, f.available_hours);
    out.utilization_rate = rate(f.used_hours, f.available_hours);
    out.no_show_rate = rate(f.no_show, attended);
    return out;
  });

  const sum = (k) => facilities.reduce((a, f) => a + Number(f[k]), 0);
  const totals = {
    facilities: facilities.length,
    total_bookings: sum('total_bookings'),
    by_status: Object.fromEntries(
      ['pending', 'approved', 'checked_in', 'completed', 'no_show', 'cancelled', 'rejected'].map((s) => [s, sum(s)]),
    ),
    available_hours: round(sum('available_hours')),
    booked_hours: round(sum('booked_hours')),
    used_hours: round(sum('used_hours')),
  };
  totals.booking_rate = rate(totals.booked_hours, totals.available_hours);
  totals.utilization_rate = rate(totals.used_hours, totals.available_hours);
  totals.no_show_rate = rate(sum('no_show'), sum('no_show') + sum('checked_in') + sum('completed'));

  res.json({
    from,
    to,
    timezone: tz,
    totals,
    facilities,
    daily: daily.rows.map((d) => ({ date: d.date, bookings: Number(d.bookings), booked_hours: round(d.booked_hours), used_hours: round(d.used_hours) })),
    peak_hours: hourly.rows.map((h) => ({ hour: Number(h.hour), bookings: Number(h.bookings) })),
    weekday: weekday.rows.map((w) => ({ dow: Number(w.dow), bookings: Number(w.bookings) })),
  });
});

module.exports = router;
