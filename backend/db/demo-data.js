// Fills the database with ~60 days of realistic booking history plus upcoming
// bookings, so the utilization dashboard has something to show in a demo.
// Usage: npm run db:demo   (run db:seed first)
require('dotenv').config();
const bcrypt = require('bcryptjs');
const { pool } = require('../src/db');
const config = require('../src/config');

// Deterministic pseudo-random numbers so every demo looks the same.
let state = 42;
const rand = () => ((state = (state * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const pick = (arr) => arr[Math.floor(rand() * arr.length)];

const PURPOSES = [
  'Department meeting', 'Thesis defense', 'Org general assembly', 'Review session', 'Seminar',
  'Club practice', 'Training workshop', 'Faculty consultation', 'Group study', 'Committee planning',
];
const STUDENTS = ['Ana Reyes', 'Mark Villanueva', 'Carla Mendoza', 'Paolo Garcia', 'Bea Navarro', 'Rico Bautista'];

async function main() {
  const hash = await bcrypt.hash('password123', 10);
  for (const name of STUDENTS) {
    const email = `${name.split(' ')[0].toLowerCase()}@example.com`;
    await pool.query(
      'INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) ON CONFLICT (email) DO NOTHING',
      [name, email, hash],
    );
  }
  const users = (await pool.query("SELECT id FROM users WHERE role = 'user'")).rows.map((r) => r.id);
  const facilities = (await pool.query(
    `SELECT id, EXTRACT(HOUR FROM open_time)::int AS open_h, EXTRACT(HOUR FROM close_time)::int AS close_h,
            requires_approval FROM facilities WHERE is_active`,
  )).rows;
  // Popularity differs per facility so the dashboard shows contrast.
  const demand = [0.9, 0.6, 0.45, 0.75, 0.3];

  await pool.query("DELETE FROM bookings WHERE purpose LIKE '%[demo]'");
  let count = 0;
  for (let dayOffset = -60; dayOffset <= 14; dayOffset++) {
    for (const [fi, f] of facilities.entries()) {
      const weekday = new Date(Date.now() + dayOffset * 86_400_000).getDay();
      const weekendFactor = weekday === 0 ? 0.2 : weekday === 6 ? 0.5 : 1;
      let hour = f.open_h;
      while (hour < f.close_h - 1) {
        // Morning (9–11) and mid-afternoon (13–16) are busier.
        const peak = (hour >= 9 && hour <= 11) || (hour >= 13 && hour <= 16) ? 1.3 : 0.6;
        if (rand() < demand[fi % demand.length] * weekendFactor * peak * 0.45) {
          const dur = Math.min(pick([1, 1, 2, 2, 3]), f.close_h - hour);
          const start = `((now() AT TIME ZONE '${config.timezone}')::date + ${dayOffset})::timestamp + interval '${hour} hours'`;
          const end = `((now() AT TIME ZONE '${config.timezone}')::date + ${dayOffset})::timestamp + interval '${hour + dur} hours'`;
          const past = dayOffset < 0;
          let status;
          const r = rand();
          if (past) status = r < 0.72 ? 'completed' : r < 0.85 ? 'no_show' : r < 0.95 ? 'cancelled' : 'rejected';
          else if (dayOffset === 0) status = null; // leave today alone so live check-in can be demoed
          else status = f.requires_approval && r < 0.35 ? 'pending' : r < 0.9 ? 'approved' : 'cancelled';
          if (status) {
            const lateMin = Math.floor(rand() * 12);
            const earlyLeaveMin = rand() < 0.4 ? Math.floor(rand() * 40) : 0;
            await pool.query(
              `INSERT INTO bookings (facility_id, user_id, starts_at, ends_at, purpose, attendees, status,
                                     checked_in_at, checked_out_at, created_at)
               VALUES ($1, $2, (${start}) AT TIME ZONE $3, (${end}) AT TIME ZONE $3, $4, $5, $6::booking_status,
                       CASE WHEN $6 = 'completed' THEN (${start}) AT TIME ZONE $3 + make_interval(mins => $7) END,
                       CASE WHEN $6 = 'completed' THEN (${end}) AT TIME ZONE $3 - make_interval(mins => $8) END,
                       (${start}) AT TIME ZONE $3 - interval '3 days')`,
              [f.id, pick(users), config.timezone, `${pick(PURPOSES)} [demo]`, 1 + Math.floor(rand() * 10),
                status, lateMin, earlyLeaveMin],
            );
            count++;
          }
          hour += dur;
        } else {
          hour += 1;
        }
      }
    }
  }
  console.log(`Inserted ${count} demo bookings. Student logins: ana@example.com … rico@example.com / password123`);
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
