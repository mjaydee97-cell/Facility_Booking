// Periodic background jobs that keep booking statuses truthful for utilization reports.
const db = require('../db');
const config = require('../config');
const { notify } = require('../services/notifications');

// Approved bookings not checked in by the end of the grace period become no-shows,
// which also releases the slot (no_show is outside the no_double_booking constraint).
async function markNoShows() {
  const { rows } = await db.query(
    `UPDATE bookings b SET status = 'no_show', updated_at = now()
       FROM facilities f
      WHERE f.id = b.facility_id AND b.status = 'approved'
        AND now() > b.starts_at + make_interval(mins => $1)
      RETURNING b.id, b.user_id, f.name AS facility_name`,
    [config.checkinGraceMinutes],
  );
  for (const r of rows) {
    await notify(r.user_id, 'Marked as no-show', `You did not check in to ${r.facility_name}, so the slot was released.`, r.id);
  }
  return rows.length;
}

// Checked-in bookings past their end time are completed; usage ends at the scheduled end.
async function autoComplete() {
  const { rowCount } = await db.query(
    `UPDATE bookings SET status = 'completed', checked_out_at = ends_at, updated_at = now()
      WHERE status = 'checked_in' AND now() >= ends_at`,
  );
  return rowCount;
}

// Pending requests nobody acted on before the start time are auto-rejected.
async function expirePending() {
  const { rows } = await db.query(
    `UPDATE bookings b SET status = 'rejected', admin_remarks = 'Not reviewed before the start time', updated_at = now()
       FROM facilities f
      WHERE f.id = b.facility_id AND b.status = 'pending' AND now() >= b.starts_at
      RETURNING b.id, b.user_id, f.name AS facility_name`,
  );
  for (const r of rows) {
    await notify(r.user_id, 'Booking request expired', `Your request for ${r.facility_name} was not reviewed in time.`, r.id);
  }
  return rows.length;
}

async function sendReminders() {
  const { rows } = await db.query(
    `UPDATE bookings b SET reminder_sent_at = now()
       FROM facilities f
      WHERE f.id = b.facility_id AND b.status = 'approved' AND b.reminder_sent_at IS NULL
        AND b.starts_at > now() AND b.starts_at <= now() + make_interval(mins => $1)
      RETURNING b.id, b.user_id, f.name AS facility_name`,
    [config.reminderMinutesBefore],
  );
  for (const r of rows) {
    await notify(r.user_id, 'Upcoming booking', `Your ${r.facility_name} booking starts soon. Scan the QR code at the entrance to check in.`, r.id);
  }
  return rows.length;
}

async function runOnce() {
  return {
    noShows: await markNoShows(),
    completed: await autoComplete(),
    expired: await expirePending(),
    reminders: await sendReminders(),
  };
}

function start() {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      await runOnce();
    } catch (err) {
      console.error('[scheduler]', err);
    } finally {
      running = false;
    }
  };
  tick();
  return setInterval(tick, config.schedulerIntervalMs);
}

module.exports = { start, runOnce };
