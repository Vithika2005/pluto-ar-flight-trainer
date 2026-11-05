'use strict';
process.env.DB_PATH = ':memory:';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../server');

let server;
let base;

before(async () => {
  server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.closeAllConnections();
  server.close();
});

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json() };
}

test('health check', async () => {
  const r = await call('GET', '/api/health');
  assert.equal(r.status, 200);
  assert.equal(r.json.ok, true);
});

test('register, duplicate, login, bad password', async () => {
  let r = await call('POST', '/api/auth/register', { username: 'pilot1', password: 'secret1' });
  assert.equal(r.status, 201);
  assert.ok(r.json.token);
  r = await call('POST', '/api/auth/register', { username: 'PILOT1', password: 'secret1' });
  assert.equal(r.status, 409);
  r = await call('POST', '/api/auth/login', { username: 'pilot1', password: 'secret1' });
  assert.equal(r.status, 200);
  r = await call('POST', '/api/auth/login', { username: 'pilot1', password: 'wrong' });
  assert.equal(r.status, 401);
  r = await call('POST', '/api/auth/register', { username: 'x', password: 'secret1' });
  assert.equal(r.status, 400);
});

test('protected routes need a token', async () => {
  const r = await call('GET', '/api/me/summary');
  assert.equal(r.status, 401);
});

test('progress, attempts, summary and leaderboard', async () => {
  const reg = await call('POST', '/api/auth/register', { username: 'ace', password: 'secret1' });
  const t = reg.json.token;

  for (const stage of [1, 2, 2, 3]) {
    assert.equal((await call('POST', '/api/tutorial/stage', { stage }, t)).status, 201);
  }
  assert.equal((await call('POST', '/api/tutorial/stage', { stage: 9 }, t)).status, 400);

  const good = { mode: 'mission1', score: 88, durationSec: 52.5, collisions: 0, stability: 71, success: true };
  assert.equal((await call('POST', '/api/attempts', good, t)).status, 201);
  assert.equal((await call('POST', '/api/attempts', { ...good, score: 60, success: false }, t)).status, 201);
  assert.equal((await call('POST', '/api/attempts', { ...good, mode: 'bogus' }, t)).status, 400);
  assert.equal((await call('POST', '/api/attempts', { ...good, score: 500 }, t)).status, 400);

  const s = await call('GET', '/api/me/summary', null, t);
  assert.deepEqual(s.json.stagesCompleted, [1, 2, 3]);
  assert.equal(s.json.best.mission1, 88);
  assert.equal(s.json.attemptCount, 2);

  const a = await call('GET', '/api/attempts?limit=5', null, t);
  assert.equal(a.json.length, 2);
  assert.equal(a.json[0].success, false);

  const lb = await call('GET', '/api/leaderboard?mode=mission1', null, t);
  assert.equal(lb.json[0].username, 'ace');
  assert.equal(lb.json[0].bestScore, 88);
});
