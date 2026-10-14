const jwt = require('jsonwebtoken');
const config = require('../config');
const { unauthorized, forbidden } = require('../errors');

function signToken(user) {
  return jwt.sign({ sub: user.id, role: user.role, name: user.name }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
  });
}

function requireAuth(req, _res, next) {
  const header = req.get('authorization') || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) return next(unauthorized());
  try {
    const payload = jwt.verify(token, config.jwtSecret);
    req.user = { id: payload.sub, role: payload.role, name: payload.name };
    next();
  } catch {
    next(unauthorized('Invalid or expired token'));
  }
}

function requireAdmin(req, _res, next) {
  if (req.user?.role !== 'admin') return next(forbidden('Admin access required'));
  next();
}

module.exports = { signToken, requireAuth, requireAdmin };
