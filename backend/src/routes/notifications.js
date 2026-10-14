const express = require('express');
const db = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.get('/', async (req, res) => {
  const { rows } = await db.query(
    `SELECT id, title, body, booking_id, read_at, created_at FROM notifications
      WHERE user_id = $1 ORDER BY created_at DESC LIMIT 100`,
    [req.user.id],
  );
  res.json(rows);
});

router.post('/read-all', async (req, res) => {
  await db.query('UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL', [req.user.id]);
  res.status(204).end();
});

module.exports = router;
