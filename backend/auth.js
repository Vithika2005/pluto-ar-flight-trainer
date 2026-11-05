'use strict';
// Password hashing (scrypt) and signed bearer tokens (HMAC-SHA256) using only Node's crypto module.
const crypto = require('node:crypto');

const SECRET = process.env.TOKEN_SECRET || 'change-me-before-deploying';
const TOKEN_TTL_SEC = 60 * 60 * 24 * 7; // 7 days

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

function verifyPassword(password, stored) {
  const [saltHex, hashHex] = String(stored).split(':');
  if (!saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length);
  return crypto.timingSafeEqual(actual, expected);
}

function sign(body) {
  return crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
}

function signToken(uid) {
  const body = Buffer.from(
    JSON.stringify({ uid, exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SEC })
  ).toString('base64url');
  return `${body}.${sign(body)}`;
}

function verifyToken(token) {
  if (typeof token !== 'string') return null;
  const [body, sig] = token.split('.');
  if (!body || !sig) return null;
  const a = Buffer.from(sig);
  const b = Buffer.from(sign(body));
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (typeof payload.exp !== 'number' || payload.exp < Date.now() / 1000) return null;
    return payload;
  } catch {
    return null;
  }
}

module.exports = { hashPassword, verifyPassword, signToken, verifyToken };
