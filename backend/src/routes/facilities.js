const express = require('express');
const { z } = require('zod');
const db = require('../db');
const config = require('../config');
const { validate } = require('../middleware/validate');
const { requireAuth, requireAdmin } = require('../middleware/auth');
const { notFound, badRequest } = require('../errors');

const router = express.Router();
router.use(requireAuth);

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:MM (24-hour)');
const idParam = z.object({ id: z.coerce.number().int().positive() });

const facilitySchema = z.object({
  name: z.string().trim().min(2).max(120),
  description: z.string().trim().max(1000).default(''),
  location: z.string().trim().max(200).default(''),
  capacity: z.number().int().positive(),
  open_time: time.default('07:00'),
  close_time: time.default('21:00'),
  requires_approval: z.boolean().default(false),
  is_active: z.boolean().default(true),
}).refine((f) => f.close_time > f.open_time, { message: 'close_time must be after open_time', path: ['close_time'] });

// checkin_token is only exposed to admins (it is what the posted QR code encodes).
const PUBLIC_COLUMNS = `id, name, description, location, capacity,
  to_char(open_time, 'HH24:MI') AS open_time, to_char(close_time, 'HH24:MI') AS close_time,
  requires_approval, is_active`;

router.get('/', async (req, res) => {
  const showAll = req.user.role === 'admin' && req.query.all === 'true';
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS} FROM facilities ${showAll ? '' : 'WHERE is_active'} ORDER BY name`,
  );
  res.json(rows);
});

router.get('/:id', validate(idParam, 'params'), async (req, res) => {
  const { rows } = await db.query(`SELECT ${PUBLIC_COLUMNS} FROM facilities WHERE id = $1`, [req.params.id]);
  if (!rows[0]) throw notFound('Facility not found');
  res.json(rows[0]);
});

// Busy time ranges for one local calendar day, so the app can draw a timeline.
router.get('/:id/availability', validate(idParam, 'params'), async (req, res) => {
  const date = String(req.query.date || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw badRequest('Query parameter "date" (YYYY-MM-DD) is required');
  const fac = await db.query(`SELECT ${PUBLIC_COLUMNS} FROM facilities WHERE id = $1`, [req.params.id]);
  if (!fac.rows[0]) throw notFound('Facility not found');
  const { rows } = await db.query(
    `SELECT id, starts_at, ends_at, status, (user_id = $4) AS is_mine
       FROM bookings
      WHERE facility_id = $1
        AND status IN ('pending', 'approved', 'checked_in')
        AND tstzrange(starts_at, ends_at) && tstzrange(($2::date)::timestamp AT TIME ZONE $3,
                                                       ($2::date + 1)::timestamp AT TIME ZONE $3)
      ORDER BY starts_at`,
    [req.params.id, date, config.timezone, req.user.id],
  );
  res.json({ facility: fac.rows[0], date, timezone: config.timezone, busy: rows });
});

// ---- Admin ----

router.get('/:id/checkin-qr', requireAdmin, validate(idParam, 'params'), async (req, res) => {
  const { rows } = await db.query('SELECT id, name, checkin_token FROM facilities WHERE id = $1', [req.params.id]);
  if (!rows[0]) throw notFound('Facility not found');
  // The mobile app renders this payload as a QR code to print and post at the door.
  res.json({ ...rows[0], qr_payload: `FBUM:${rows[0].checkin_token}` });
});

router.post('/:id/checkin-qr/rotate', requireAdmin, validate(idParam, 'params'), async (req, res) => {
  const { rows } = await db.query(
    'UPDATE facilities SET checkin_token = gen_random_uuid() WHERE id = $1 RETURNING id, name, checkin_token',
    [req.params.id],
  );
  if (!rows[0]) throw notFound('Facility not found');
  res.json({ ...rows[0], qr_payload: `FBUM:${rows[0].checkin_token}` });
});

router.post('/', requireAdmin, validate(facilitySchema), async (req, res) => {
  const f = req.body;
  const { rows } = await db.query(
    `INSERT INTO facilities (name, description, location, capacity, open_time, close_time, requires_approval, is_active)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING ${PUBLIC_COLUMNS}`,
    [f.name, f.description, f.location, f.capacity, f.open_time, f.close_time, f.requires_approval, f.is_active],
  );
  res.status(201).json(rows[0]);
});

router.put('/:id', requireAdmin, validate(idParam, 'params'), validate(facilitySchema), async (req, res) => {
  const f = req.body;
  const { rows } = await db.query(
    `UPDATE facilities SET name = $2, description = $3, location = $4, capacity = $5,
            open_time = $6, close_time = $7, requires_approval = $8, is_active = $9
      WHERE id = $1 RETURNING ${PUBLIC_COLUMNS}`,
    [req.params.id, f.name, f.description, f.location, f.capacity, f.open_time, f.close_time, f.requires_approval, f.is_active],
  );
  if (!rows[0]) throw notFound('Facility not found');
  res.json(rows[0]);
});

// Soft delete: keeps booking history intact for utilization reports.
router.delete('/:id', requireAdmin, validate(idParam, 'params'), async (req, res) => {
  const { rowCount } = await db.query('UPDATE facilities SET is_active = false WHERE id = $1', [req.params.id]);
  if (!rowCount) throw notFound('Facility not found');
  res.status(204).end();
});

module.exports = router;
