const express = require('express');
const bcrypt = require('bcryptjs');
const { z } = require('zod');
const db = require('../db');
const { validate } = require('../middleware/validate');
const { signToken, requireAuth } = require('../middleware/auth');
const { unauthorized, conflict, notFound } = require('../errors');

const router = express.Router();

const publicUser = (u) => ({ id: u.id, name: u.name, email: u.email, role: u.role });

const registerSchema = z.object({
  name: z.string().trim().min(2).max(100),
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(8).max(100),
});

router.post('/register', validate(registerSchema), async (req, res) => {
  const { name, email, password } = req.body;
  const hash = await bcrypt.hash(password, 10);
  try {
    const { rows } = await db.query(
      `INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3)
       RETURNING id, name, email, role`,
      [name, email, hash],
    );
    res.status(201).json({ token: signToken(rows[0]), user: publicUser(rows[0]) });
  } catch (err) {
    if (err.code === '23505') throw conflict('An account with this email already exists');
    throw err;
  }
});

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1),
});

router.post('/login', validate(loginSchema), async (req, res) => {
  const { email, password } = req.body;
  const { rows } = await db.query('SELECT * FROM users WHERE email = $1', [email]);
  const user = rows[0];
  if (!user || !(await bcrypt.compare(password, user.password_hash))) {
    throw unauthorized('Incorrect email or password');
  }
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.get('/me', requireAuth, async (req, res) => {
  const { rows } = await db.query('SELECT id, name, email, role FROM users WHERE id = $1', [req.user.id]);
  if (!rows[0]) throw notFound('User not found');
  res.json(rows[0]);
});

// Registers this device's FCM token so the server can push to it.
router.post(
  '/device-token',
  requireAuth,
  validate(z.object({ token: z.string().min(10), platform: z.enum(['android', 'ios', 'web', 'unknown']).default('unknown') })),
  async (req, res) => {
    await db.query(
      `INSERT INTO device_tokens (user_id, token, platform) VALUES ($1, $2, $3)
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform`,
      [req.user.id, req.body.token, req.body.platform],
    );
    res.status(204).end();
  },
);

router.delete('/device-token', requireAuth, validate(z.object({ token: z.string() })), async (req, res) => {
  await db.query('DELETE FROM device_tokens WHERE token = $1 AND user_id = $2', [req.body.token, req.user.id]);
  res.status(204).end();
});

module.exports = router;
