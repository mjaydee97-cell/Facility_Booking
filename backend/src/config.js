require('dotenv').config();

const env = process.env;

module.exports = {
  port: Number(env.PORT || 3000),
  databaseUrl: env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/facility_booking',
  jwtSecret: env.JWT_SECRET || 'change-me-in-production',
  jwtExpiresIn: env.JWT_EXPIRES_IN || '7d',
  // Facility opening hours are stored as local wall-clock times in this zone.
  timezone: env.APP_TIMEZONE || 'Asia/Manila',
  // Check-in window: from CHECKIN_EARLY_MIN before start until CHECKIN_GRACE_MIN after start.
  checkinEarlyMinutes: Number(env.CHECKIN_EARLY_MIN || 15),
  checkinGraceMinutes: Number(env.CHECKIN_GRACE_MIN || 15),
  reminderMinutesBefore: Number(env.REMINDER_MINUTES_BEFORE || 30),
  maxBookingHours: Number(env.MAX_BOOKING_HOURS || 8),
  maxAdvanceDays: Number(env.MAX_ADVANCE_DAYS || 60),
  // Path to the Firebase service-account JSON. If unset, push is skipped (in-app inbox still works).
  firebaseCredentials: env.GOOGLE_APPLICATION_CREDENTIALS || '',
  schedulerIntervalMs: Number(env.SCHEDULER_INTERVAL_MS || 60_000),
};
