// Integration tests against a real PostgreSQL database.
// Uses TEST_DATABASE_URL (default: local facility_booking_test) and wipes it first.
process.env.DATABASE_URL =
  process.env.TEST_DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/facility_booking_test';
process.env.GOOGLE_APPLICATION_CREDENTIALS = '';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const app = require('../src/app');
const { pool } = require('../src/db');
const { migrate, seed } = require('../db/migrate');
const scheduler = require('../src/jobs/scheduler');

const api = request(app);
let adminToken, userToken, otherToken, conferenceId, avRoomId;

const auth = (t) => ({ Authorization: `Bearer ${t}` });

// A future time at the given local (Asia/Manila, UTC+8) hour, `days` days from today.
function manila(days, hour, minute = 0) {
  const nowManila = new Date(Date.now() + 8 * 3600_000);
  const d = new Date(Date.UTC(nowManila.getUTCFullYear(), nowManila.getUTCMonth(), nowManila.getUTCDate() + days, hour - 8, minute));
  return d.toISOString();
}

before(async () => {
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  await seed();
  const login = async (email) =>
    (await api.post('/api/auth/login').send({ email, password: 'password123' }).expect(200)).body.token;
  adminToken = await login('admin@example.com');
  userToken = await login('user@example.com');
  otherToken = (await api.post('/api/auth/register')
    .send({ name: 'Maria Santos', email: 'maria@example.com', password: 'password123' }).expect(201)).body.token;
  const { body } = await api.get('/api/facilities').set(auth(userToken)).expect(200);
  conferenceId = body.find((f) => f.name === 'Conference Room A').id;
  avRoomId = body.find((f) => f.name === 'Audio-Visual Room').id;
});

after(() => pool.end());

test('rejects unauthenticated and bad logins', async () => {
  await api.get('/api/facilities').expect(401);
  await api.post('/api/auth/login').send({ email: 'user@example.com', password: 'wrong' }).expect(401);
  await api.post('/api/auth/register').send({ name: 'X', email: 'nope', password: '1' }).expect(400);
});

test('non-admins cannot hit admin endpoints', async () => {
  await api.get('/api/analytics/summary').set(auth(userToken)).expect(403);
  await api.post('/api/facilities').set(auth(userToken)).send({ name: 'Hack', capacity: 1 }).expect(403);
  await api.get(`/api/facilities/${conferenceId}/checkin-qr`).set(auth(userToken)).expect(403);
});

test('auto-approves when facility needs no approval, and blocks double booking', async () => {
  const res = await api.post('/api/bookings').set(auth(userToken)).send({
    facility_id: conferenceId, starts_at: manila(2, 9), ends_at: manila(2, 11), purpose: 'Team meeting', attendees: 5,
  }).expect(201);
  assert.equal(res.body.status, 'approved');

  const clash = await api.post('/api/bookings').set(auth(otherToken)).send({
    facility_id: conferenceId, starts_at: manila(2, 10), ends_at: manila(2, 12), purpose: 'Overlapping meeting',
  }).expect(409);
  assert.match(clash.body.error, /overlaps/);

  // Back-to-back is fine: [9,11) and [11,12) do not overlap.
  await api.post('/api/bookings').set(auth(otherToken)).send({
    facility_id: conferenceId, starts_at: manila(2, 11), ends_at: manila(2, 12), purpose: 'Next meeting',
  }).expect(201);
});

test('concurrent requests for the same slot: exactly one wins', async () => {
  const body = { facility_id: conferenceId, starts_at: manila(3, 13), ends_at: manila(3, 14), purpose: 'Race test' };
  const results = await Promise.all(
    Array.from({ length: 8 }, (_, i) => api.post('/api/bookings').set(auth(i % 2 ? userToken : otherToken)).send(body)),
  );
  assert.equal(results.filter((r) => r.status === 201).length, 1);
  assert.equal(results.filter((r) => r.status === 409).length, 7);
});

test('enforces opening hours, capacity and past times', async () => {
  const base = { facility_id: conferenceId, purpose: 'Rule check' };
  // Conference Room A is open 08:00–17:00.
  await api.post('/api/bookings').set(auth(userToken)).send({ ...base, starts_at: manila(4, 7), ends_at: manila(4, 9) }).expect(400);
  await api.post('/api/bookings').set(auth(userToken)).send({ ...base, starts_at: manila(4, 16), ends_at: manila(4, 18) }).expect(400);
  await api.post('/api/bookings').set(auth(userToken)).send({ ...base, starts_at: manila(4, 9), ends_at: manila(4, 10), attendees: 50 }).expect(400);
  await api.post('/api/bookings').set(auth(userToken)).send({ ...base, starts_at: manila(-1, 9), ends_at: manila(-1, 10) }).expect(400);
});

test('approval workflow, cancellation and notifications', async () => {
  const created = await api.post('/api/bookings').set(auth(userToken)).send({
    facility_id: avRoomId, starts_at: manila(5, 13), ends_at: manila(5, 15), purpose: 'Seminar', attendees: 40,
  }).expect(201);
  assert.equal(created.body.status, 'pending');

  // Pending still holds the slot.
  await api.post('/api/bookings').set(auth(otherToken)).send({
    facility_id: avRoomId, starts_at: manila(5, 14), ends_at: manila(5, 16), purpose: 'Clash',
  }).expect(409);

  const adminInbox = await api.get('/api/notifications').set(auth(adminToken)).expect(200);
  assert.ok(adminInbox.body.some((n) => n.title === 'New booking request'));

  const pending = await api.get('/api/bookings?status=pending').set(auth(adminToken)).expect(200);
  assert.ok(pending.body.some((b) => b.id === created.body.id));

  const approved = await api.post(`/api/bookings/${created.body.id}/approve`).set(auth(adminToken)).send({}).expect(200);
  assert.equal(approved.body.status, 'approved');
  await api.post(`/api/bookings/${created.body.id}/approve`).set(auth(adminToken)).send({}).expect(409);

  // Another user can neither view nor cancel it.
  await api.get(`/api/bookings/${created.body.id}`).set(auth(otherToken)).expect(403);
  await api.post(`/api/bookings/${created.body.id}/cancel`).set(auth(otherToken)).expect(403);

  const cancelled = await api.post(`/api/bookings/${created.body.id}/cancel`).set(auth(userToken)).expect(200);
  assert.equal(cancelled.body.status, 'cancelled');

  // Cancelling frees the slot.
  await api.post('/api/bookings').set(auth(otherToken)).send({
    facility_id: avRoomId, starts_at: manila(5, 14), ends_at: manila(5, 16), purpose: 'Now free',
  }).expect(201);

  const inbox = await api.get('/api/notifications').set(auth(userToken)).expect(200);
  assert.ok(inbox.body.some((n) => n.title === 'Booking approved'));
});

test('QR check-in, check-out, no-show and analytics', async () => {
  const { rows: [b] } = await pool.query(
    `INSERT INTO bookings (facility_id, user_id, starts_at, ends_at, purpose, status)
     SELECT $1, id, now() - interval '5 minutes', now() + interval '55 minutes', 'Live session', 'approved'
       FROM users WHERE email = 'user@example.com' RETURNING id`,
    [conferenceId],
  );
  const qr = (await api.get(`/api/facilities/${conferenceId}/checkin-qr`).set(auth(adminToken)).expect(200)).body.qr_payload;

  await api.post('/api/bookings/check-in').set(auth(userToken)).send({ qr_payload: 'garbage' }).expect(400);
  await api.post('/api/bookings/check-in').set(auth(otherToken)).send({ qr_payload: qr }).expect(400); // no booking
  const checkedIn = await api.post('/api/bookings/check-in').set(auth(userToken)).send({ qr_payload: qr }).expect(200);
  assert.equal(checkedIn.body.id, b.id);
  assert.equal(checkedIn.body.status, 'checked_in');
  // Simulate 30 minutes of actual use before checking out.
  await pool.query("UPDATE bookings SET checked_in_at = now() - interval '30 minutes' WHERE id = $1", [b.id]);

  const out = await api.post(`/api/bookings/${b.id}/check-out`).set(auth(userToken)).expect(200);
  assert.equal(out.body.status, 'completed');

  // A missed booking becomes no_show once the grace period is over.
  const { rows: [missed] } = await pool.query(
    `INSERT INTO bookings (facility_id, user_id, starts_at, ends_at, purpose, status)
     SELECT $1, id, now() - interval '40 minutes', now() + interval '20 minutes', 'Forgot', 'approved'
       FROM users WHERE email = 'maria@example.com' RETURNING id`,
    [avRoomId],
  );
  const ran = await scheduler.runOnce();
  assert.ok(ran.noShows >= 1);
  const { rows: [m] } = await pool.query('SELECT status FROM bookings WHERE id = $1', [missed.id]);
  assert.equal(m.status, 'no_show');

  const a = await api.get('/api/analytics/summary').set(auth(adminToken)).expect(200);
  assert.ok(a.body.totals.total_bookings >= 2);
  assert.ok(a.body.totals.by_status.no_show >= 1);
  assert.ok(a.body.totals.utilization_rate > 0);
  assert.equal(a.body.daily.length, 30);
  assert.equal(a.body.peak_hours.length, 24);
  const conf = a.body.facilities.find((f) => f.id === conferenceId);
  assert.equal(conf.used_hours, 0.5);

  const avail = await api.get(`/api/facilities/${conferenceId}/availability?date=${manila(2, 12).slice(0, 10)}`)
    .set(auth(userToken)).expect(200);
  assert.equal(avail.body.busy.length, 2);
});
