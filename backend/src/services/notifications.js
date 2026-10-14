// Stores every notification in the in-app inbox and, when Firebase is configured,
// sends it as a push message via Firebase Cloud Messaging (FCM HTTP v1 API).
const config = require('../config');
const db = require('../db');

let messaging = null;
let initTried = false;

function getMessaging() {
  if (initTried) return messaging;
  initTried = true;
  if (!config.firebaseCredentials) {
    console.warn('[notifications] GOOGLE_APPLICATION_CREDENTIALS not set — push disabled, inbox only.');
    return null;
  }
  try {
    const admin = require('firebase-admin');
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    messaging = admin.messaging();
  } catch (err) {
    console.error('[notifications] Firebase init failed:', err.message);
  }
  return messaging;
}

async function sendPush(userId, title, body, data) {
  const fcm = getMessaging();
  if (!fcm) return;
  const { rows } = await db.query('SELECT token FROM device_tokens WHERE user_id = $1', [userId]);
  if (rows.length === 0) return;
  const tokens = rows.map((r) => r.token);
  const res = await fcm.sendEachForMulticast({ tokens, notification: { title, body }, data });
  // Remove tokens FCM reports as no longer registered (app uninstalled, etc.).
  const stale = res.responses
    .map((r, i) => (!r.success && r.error?.code === 'messaging/registration-token-not-registered' ? tokens[i] : null))
    .filter(Boolean);
  if (stale.length) await db.query('DELETE FROM device_tokens WHERE token = ANY($1)', [stale]);
}

async function notify(userId, title, body, bookingId = null) {
  await db.query(
    'INSERT INTO notifications (user_id, title, body, booking_id) VALUES ($1, $2, $3, $4)',
    [userId, title, body, bookingId],
  );
  const data = bookingId ? { bookingId: String(bookingId) } : {};
  // Push failures must never break the request that triggered them.
  sendPush(userId, title, body, data).catch((err) => console.error('[notifications] push failed:', err.message));
}

async function notifyAdmins(title, body, bookingId = null) {
  const { rows } = await db.query("SELECT id FROM users WHERE role = 'admin'");
  await Promise.all(rows.map((r) => notify(r.id, title, body, bookingId)));
}

module.exports = { notify, notifyAdmins };
