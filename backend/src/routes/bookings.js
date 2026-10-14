const express = require('express');
const { z } = require('zod');
const db = require('../db');
const config = require('../config');
const { validate } = require('../middleware/validate');
const { requireAuth, requireAdmin } = require('../middleware/auth');
const { notify, notifyAdmins } = require('../services/notifications');
const { badRequest, notFound, forbidden, conflict } = require('../errors');

const router = express.Router();
router.use(requireAuth);

const idParam = z.object({ id: z.coerce.number().int().positive() });

const SELECT_BOOKING = `
  SELECT b.id, b.facility_id, f.name AS facility_name, f.location AS facility_location,
         b.user_id, u.name AS user_name, u.email AS user_email,
         b.starts_at, b.ends_at, b.purpose, b.attendees, b.status, b.admin_remarks,
         b.checked_in_at, b.checked_out_at, b.created_at, b.updated_at
    FROM bookings b
    JOIN facilities f ON f.id = b.facility_id
    JOIN users u ON u.id = b.user_id`;

const fmt = (d) =>
  new Date(d).toLocaleString('en-US', {
    timeZone: config.timezone, month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });

async function loadBooking(id, client = db) {
  const { rows } = await client.query(`${SELECT_BOOKING} WHERE b.id = $1`, [id]);
  if (!rows[0]) throw notFound('Booking not found');
  return rows[0];
}

function assertOwnerOrAdmin(booking, user) {
  if (booking.user_id !== user.id && user.role !== 'admin') throw forbidden();
}

// Atomically moves a booking from one of `from` statuses to `to`; returns null if the
// booking was not in an allowed status (prevents races such as approve + cancel at once).
async function transition(id, from, to, extraSet = '', extraParams = []) {
  const { rows } = await db.query(
    `UPDATE bookings SET status = $2, updated_at = now() ${extraSet}
      WHERE id = $1 AND status = ANY($3::booking_status[]) RETURNING id`,
    [id, to, from, ...extraParams],
  );
  return rows[0] ? loadBooking(id) : null;
}

// ---------- Create ----------

const createSchema = z.object({
  facility_id: z.number().int().positive(),
  starts_at: z.string().datetime({ offset: true }),
  ends_at: z.string().datetime({ offset: true }),
  purpose: z.string().trim().min(3).max(500),
  attendees: z.number().int().positive().default(1),
});

router.post('/', validate(createSchema), async (req, res) => {
  const { facility_id, purpose, attendees } = req.body;
  const starts = new Date(req.body.starts_at);
  const ends = new Date(req.body.ends_at);
  const now = Date.now();

  if (ends <= starts) throw badRequest('End time must be after start time');
  if (starts.getTime() < now) throw badRequest('Start time must be in the future');
  if ((ends - starts) / 3_600_000 > config.maxBookingHours) {
    throw badRequest(`A booking may not exceed ${config.maxBookingHours} hours`);
  }
  if ((starts - now) / 86_400_000 > config.maxAdvanceDays) {
    throw badRequest(`Bookings can be made at most ${config.maxAdvanceDays} days in advance`);
  }

  const { rows: [check] } = await db.query(
    `SELECT f.name, f.capacity, f.is_active, f.requires_approval,
            (($2::timestamptz AT TIME ZONE $4)::date = ($3::timestamptz AT TIME ZONE $4)::date
              AND ($2::timestamptz AT TIME ZONE $4)::time >= f.open_time
              AND ($3::timestamptz AT TIME ZONE $4)::time <= f.close_time) AS within_hours,
            to_char(f.open_time, 'HH24:MI') AS open_time, to_char(f.close_time, 'HH24:MI') AS close_time
       FROM facilities f WHERE f.id = $1`,
    [facility_id, starts, ends, config.timezone],
  );
  if (!check || !check.is_active) throw notFound('Facility not found or not available for booking');
  if (attendees > check.capacity) throw badRequest(`${check.name} holds at most ${check.capacity} people`);
  if (!check.within_hours) {
    throw badRequest(`${check.name} can only be booked between ${check.open_time} and ${check.close_time} on a single day`);
  }

  const status = check.requires_approval ? 'pending' : 'approved';
  let id;
  try {
    const { rows } = await db.query(
      `INSERT INTO bookings (facility_id, user_id, starts_at, ends_at, purpose, attendees, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [facility_id, req.user.id, starts, ends, purpose, attendees, status],
    );
    id = rows[0].id;
  } catch (err) {
    // 23P01 = exclusion_violation from the no_double_booking constraint.
    if (err.code === '23P01') throw conflict('This time slot overlaps an existing booking. Please choose another time.');
    throw err;
  }

  const booking = await loadBooking(id);
  if (status === 'pending') {
    await notifyAdmins('New booking request', `${booking.user_name} requested ${booking.facility_name} on ${fmt(starts)}.`, id);
  } else {
    await notify(req.user.id, 'Booking confirmed', `${booking.facility_name} on ${fmt(starts)} is confirmed.`, id);
  }
  res.status(201).json(booking);
});

// ---------- Read ----------

router.get('/mine', async (req, res) => {
  const past = req.query.scope === 'past';
  const { rows } = await db.query(
    `${SELECT_BOOKING}
      WHERE b.user_id = $1 AND ${past ? 'b.ends_at < now()' : 'b.ends_at >= now()'}
      ORDER BY b.starts_at ${past ? 'DESC' : 'ASC'} LIMIT 200`,
    [req.user.id],
  );
  res.json(rows);
});

const listSchema = z.object({
  status: z.enum(['pending', 'approved', 'rejected', 'cancelled', 'checked_in', 'completed', 'no_show']).optional(),
  facility_id: z.coerce.number().int().positive().optional(),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional(),
});

router.get('/', requireAdmin, validate(listSchema, 'query'), async (req, res) => {
  const q = req.validQuery;
  const where = [];
  const params = [];
  const add = (sql, v) => { params.push(v); where.push(sql.replace('?', `$${params.length}`)); };
  if (q.status) add('b.status = ?', q.status);
  if (q.facility_id) add('b.facility_id = ?', q.facility_id);
  if (q.from) add('b.ends_at > ?', q.from);
  if (q.to) add('b.starts_at < ?', q.to);
  const { rows } = await db.query(
    `${SELECT_BOOKING} ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY b.starts_at LIMIT 500`,
    params,
  );
  res.json(rows);
});

router.get('/:id', validate(idParam, 'params'), async (req, res) => {
  const booking = await loadBooking(req.params.id);
  assertOwnerOrAdmin(booking, req.user);
  res.json(booking);
});

// ---------- Lifecycle ----------

router.post('/:id/cancel', validate(idParam, 'params'), async (req, res) => {
  const booking = await loadBooking(req.params.id);
  assertOwnerOrAdmin(booking, req.user);
  if (req.user.role !== 'admin' && new Date(booking.starts_at) <= new Date()) {
    throw badRequest('Bookings can no longer be cancelled after they start');
  }
  const updated = await transition(booking.id, ['pending', 'approved'], 'cancelled');
  if (!updated) throw conflict(`A ${booking.status} booking cannot be cancelled`);
  if (req.user.id !== booking.user_id) {
    await notify(booking.user_id, 'Booking cancelled', `Your ${booking.facility_name} booking on ${fmt(booking.starts_at)} was cancelled by an administrator.`, booking.id);
  }
  res.json(updated);
});

const remarksSchema = z.object({ remarks: z.string().trim().max(500).optional() });

router.post('/:id/approve', requireAdmin, validate(idParam, 'params'), validate(remarksSchema), async (req, res) => {
  const booking = await loadBooking(req.params.id);
  if (new Date(booking.ends_at) <= new Date()) throw badRequest('This booking has already ended');
  const updated = await transition(booking.id, ['pending'], 'approved', ', admin_remarks = $4', [req.body.remarks ?? null]);
  if (!updated) throw conflict(`Only pending bookings can be approved (this one is ${booking.status})`);
  await notify(booking.user_id, 'Booking approved', `${booking.facility_name} on ${fmt(booking.starts_at)} has been approved.`, booking.id);
  res.json(updated);
});

router.post('/:id/reject', requireAdmin, validate(idParam, 'params'), validate(remarksSchema), async (req, res) => {
  const booking = await loadBooking(req.params.id);
  const updated = await transition(booking.id, ['pending'], 'rejected', ', admin_remarks = $4', [req.body.remarks ?? null]);
  if (!updated) throw conflict(`Only pending bookings can be rejected (this one is ${booking.status})`);
  const reason = req.body.remarks ? ` Reason: ${req.body.remarks}` : '';
  await notify(booking.user_id, 'Booking rejected', `${booking.facility_name} on ${fmt(booking.starts_at)} was not approved.${reason}`, booking.id);
  res.json(updated);
});

// User scans the QR code posted at the facility. The server finds that user's
// approved booking for this facility whose check-in window is open right now.
router.post('/check-in', validate(z.object({ qr_payload: z.string().min(1) })), async (req, res) => {
  const match = /^FBUM:([0-9a-f-]{36})$/i.exec(req.body.qr_payload.trim());
  if (!match) throw badRequest('This is not a valid facility QR code');
  const { rows: [facility] } = await db.query('SELECT id, name FROM facilities WHERE checkin_token = $1', [match[1]]);
  if (!facility) throw notFound('Unknown or expired facility QR code');

  const { rows } = await db.query(
    `UPDATE bookings SET status = 'checked_in', checked_in_at = now(), updated_at = now()
      WHERE id = (
        SELECT id FROM bookings
         WHERE user_id = $1 AND facility_id = $2 AND status = 'approved'
           AND now() BETWEEN starts_at - make_interval(mins => $3) AND starts_at + make_interval(mins => $4)
           AND now() < ends_at
         ORDER BY starts_at LIMIT 1)
      RETURNING id`,
    [req.user.id, facility.id, config.checkinEarlyMinutes, config.checkinGraceMinutes],
  );
  if (!rows[0]) {
    throw badRequest(
      `You have no approved booking for ${facility.name} right now. Check-in opens ${config.checkinEarlyMinutes} minutes before your start time and closes ${config.checkinGraceMinutes} minutes after.`,
    );
  }
  res.json(await loadBooking(rows[0].id));
});

// Admin fallback when a user cannot scan (e.g. no camera).
router.post('/:id/check-in', requireAdmin, validate(idParam, 'params'), async (req, res) => {
  const updated = await transition(req.params.id, ['approved'], 'checked_in', ', checked_in_at = now()');
  if (!updated) throw conflict('Only approved bookings can be checked in');
  res.json(updated);
});

router.post('/:id/check-out', validate(idParam, 'params'), async (req, res) => {
  const booking = await loadBooking(req.params.id);
  assertOwnerOrAdmin(booking, req.user);
  const updated = await transition(booking.id, ['checked_in'], 'completed', ', checked_out_at = now()');
  if (!updated) throw conflict('Only checked-in bookings can be checked out');
  res.json(updated);
});

module.exports = router;
