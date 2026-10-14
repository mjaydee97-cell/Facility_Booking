// Applies db/schema.sql; with --seed also inserts demo users and facilities.
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { pool } = require('../src/db');

async function migrate() {
  await pool.query(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
}

async function seed() {
  const hash = await bcrypt.hash('password123', 10);
  await pool.query(
    `INSERT INTO users (name, email, password_hash, role) VALUES
       ('Facility Admin', 'admin@example.com', $1, 'admin'),
       ('Juan Dela Cruz', 'user@example.com',  $1, 'user')
     ON CONFLICT (email) DO NOTHING`,
    [hash],
  );
  const { rowCount } = await pool.query('SELECT 1 FROM facilities LIMIT 1');
  if (rowCount === 0) {
    await pool.query(
      `INSERT INTO facilities (name, description, location, capacity, open_time, close_time, requires_approval) VALUES
         ('Audio-Visual Room', 'Projector, sound system, 60 seats', 'Main Bldg, 2F', 60, '07:00', '20:00', true),
         ('Conference Room A', 'Round table, TV screen, whiteboard', 'Admin Bldg, 3F', 12, '08:00', '17:00', false),
         ('Gymnasium', 'Full basketball court with bleachers', 'Sports Complex', 300, '06:00', '21:00', true),
         ('Computer Laboratory 1', '40 workstations with internet', 'IT Bldg, 1F', 40, '07:00', '19:00', false),
         ('Study Room 3', 'Quiet room for small groups', 'Library, 2F', 6, '08:00', '20:00', false)`,
    );
  }
}

if (require.main === module) {
  (async () => {
    await migrate();
    console.log('Schema applied.');
    if (process.argv.includes('--seed')) {
      await seed();
      console.log('Seed data inserted (admin@example.com / user@example.com, password: password123).');
    }
    await pool.end();
  })().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { migrate, seed };
