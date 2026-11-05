'use strict';
// Pluto AR Flight Trainer - REST API (zero dependencies, Node >= 22.13)
const http = require('node:http');
const os = require('node:os');
const db = require('./db');
const auth = require('./auth');

const MODES = ['tutorial', 'mission1', 'mission2', 'mission3'];

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > 100_000) {
        reject(new HttpError(413, 'Request body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new HttpError(400, 'Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}

function send(res, status, body) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  };
  if (status === 204) {
    res.writeHead(204, headers);
    return res.end();
  }
  const data = JSON.stringify(body);
  res.writeHead(status, {
    ...headers,
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(data),
  });
  res.end(data);
}

function requireUser(req) {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  const payload = m && auth.verifyToken(m[1]);
  if (!payload) throw new HttpError(401, 'Not authenticated');
  const user = db.prepare('SELECT id, username FROM users WHERE id = ?').get(payload.uid);
  if (!user) throw new HttpError(401, 'Unknown user');
  return user;
}

function number(value, name, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) {
    throw new HttpError(400, `${name} must be a number between ${min} and ${max}`);
  }
  return n;
}

const routes = {
  'GET /api/health': async () => ({ body: { ok: true, time: new Date().toISOString() } }),

  'POST /api/auth/register': async (req) => {
    const { username, password } = await readJson(req);
    if (!/^[A-Za-z0-9_]{3,24}$/.test(username || '')) {
      throw new HttpError(400, 'Username must be 3-24 letters, digits or underscores');
    }
    if (typeof password !== 'string' || password.length < 6 || password.length > 100) {
      throw new HttpError(400, 'Password must be 6-100 characters');
    }
    if (db.prepare('SELECT 1 FROM users WHERE username = ?').get(username)) {
      throw new HttpError(409, 'Username already taken');
    }
    const info = db
      .prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)')
      .run(username, auth.hashPassword(password));
    const id = Number(info.lastInsertRowid);
    return { status: 201, body: { token: auth.signToken(id), user: { id, username } } };
  },

  'POST /api/auth/login': async (req) => {
    const { username, password } = await readJson(req);
    const row =
      typeof username === 'string' && typeof password === 'string'
        ? db.prepare('SELECT id, username, password_hash FROM users WHERE username = ?').get(username)
        : null;
    if (!row || !auth.verifyPassword(password, row.password_hash)) {
      throw new HttpError(401, 'Invalid username or password');
    }
    return { body: { token: auth.signToken(row.id), user: { id: row.id, username: row.username } } };
  },

  'GET /api/me/summary': async (req) => {
    const user = requireUser(req);
    const stages = db
      .prepare('SELECT stage FROM tutorial_progress WHERE user_id = ? ORDER BY stage')
      .all(user.id)
      .map((r) => r.stage);
    const best = {};
    for (const r of db
      .prepare('SELECT mode, MAX(score) AS best FROM attempts WHERE user_id = ? AND success = 1 GROUP BY mode')
      .all(user.id)) {
      best[r.mode] = r.best;
    }
    const { n } = db.prepare('SELECT COUNT(*) AS n FROM attempts WHERE user_id = ?').get(user.id);
    return { body: { username: user.username, stagesCompleted: stages, best, attemptCount: n } };
  },

  'POST /api/tutorial/stage': async (req) => {
    const user = requireUser(req);
    const { stage } = await readJson(req);
    const s = number(stage, 'stage', 1, 7);
    if (!Number.isInteger(s)) throw new HttpError(400, 'stage must be an integer');
    db.prepare('INSERT OR IGNORE INTO tutorial_progress (user_id, stage) VALUES (?, ?)').run(user.id, s);
    return { status: 201, body: { ok: true } };
  },

  'POST /api/attempts': async (req) => {
    const user = requireUser(req);
    const b = await readJson(req);
    if (!MODES.includes(b.mode)) throw new HttpError(400, `mode must be one of ${MODES.join(', ')}`);
    const score = Math.round(number(b.score, 'score', 0, 100));
    const duration = number(b.durationSec, 'durationSec', 0, 36000);
    const collisions = Math.round(number(b.collisions ?? 0, 'collisions', 0, 1000));
    const stability = number(b.stability ?? 0, 'stability', 0, 100);
    const info = db
      .prepare(
        `INSERT INTO attempts (user_id, mode, score, duration_sec, collisions, stability, success)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .run(user.id, b.mode, score, duration, collisions, stability, b.success ? 1 : 0);
    return { status: 201, body: { id: Number(info.lastInsertRowid) } };
  },

  'GET /api/attempts': async (req, url) => {
    const user = requireUser(req);
    const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '30', 10) || 30));
    const rows = db
      .prepare(
        `SELECT id, mode, score, duration_sec, collisions, stability, success, created_at
         FROM attempts WHERE user_id = ? ORDER BY id DESC LIMIT ?`
      )
      .all(user.id, limit);
    return {
      body: rows.map((r) => ({
        id: r.id,
        mode: r.mode,
        score: r.score,
        durationSec: r.duration_sec,
        collisions: r.collisions,
        stability: r.stability,
        success: !!r.success,
        createdAt: r.created_at,
      })),
    };
  },

  'GET /api/leaderboard': async (req, url) => {
    requireUser(req);
    const mode = url.searchParams.get('mode') || 'mission1';
    if (!MODES.includes(mode)) throw new HttpError(400, 'Unknown mode');
    const rows = db
      .prepare(
        `SELECT u.username AS username, MAX(a.score) AS best_score,
                MIN(a.duration_sec) AS best_time, COUNT(*) AS attempts
         FROM attempts a JOIN users u ON u.id = a.user_id
         WHERE a.mode = ? AND a.success = 1
         GROUP BY u.id, u.username
         ORDER BY best_score DESC, best_time ASC
         LIMIT 10`
      )
      .all(mode);
    return {
      body: rows.map((r) => ({
        username: r.username,
        bestScore: r.best_score,
        bestTime: r.best_time,
        attempts: r.attempts,
      })),
    };
  },
};

function createServer() {
  return http.createServer(async (req, res) => {
    try {
      if (req.method === 'OPTIONS') return send(res, 204);
      const url = new URL(req.url, 'http://localhost');
      const handler = routes[`${req.method} ${url.pathname}`];
      if (!handler) throw new HttpError(404, 'Not found');
      const out = await handler(req, url);
      send(res, out.status || 200, out.body);
    } catch (e) {
      if (e instanceof HttpError) return send(res, e.status, { error: e.message });
      console.error(e);
      send(res, 500, { error: 'Internal server error' });
    }
  });
}

module.exports = { createServer };

if (require.main === module) {
  const port = Number(process.env.PORT) || 3000;
  createServer().listen(port, '0.0.0.0', () => {
    console.log(`Pluto AR backend listening on port ${port}`);
    console.log('Use one of these URLs in the app (phone and laptop on the same Wi-Fi):');
    for (const addrs of Object.values(os.networkInterfaces())) {
      for (const a of addrs || []) {
        if (a.family === 'IPv4' && !a.internal) console.log(`  http://${a.address}:${port}`);
      }
    }
  });
}
