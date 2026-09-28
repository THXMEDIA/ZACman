// End-to-end game-logic simulation, driven by a bot, against the exact
// script shipped in web/index.html. Run with: node --test tests/game-logic.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { sim, advance, runTimeouts } = require('./sim-harness.js');

function isFiniteNum(n) {
  return typeof n === 'number' && Number.isFinite(n);
}

// Pins an enemy at an exact grid cell so the per-frame interpolation code
// (fromR/fromC -> targetR/targetC by `t`) can't drag it away before a
// same-tick collision check runs.
function pinEnemyAt(en, r, c) {
  en.r = en.fromR = en.targetR = r;
  en.c = en.fromC = en.targetC = c;
  en.x = c * sim.CELL;
  en.z = r * sim.CELL;
  en.t = 0;
}

test('beginGame starts cleanly', () => {
  sim.beginGame();
  assert.equal(sim.state.running, true);
  assert.notEqual(sim.state.maze, null);
  assert.ok(sim.state.pelletsRemaining > 0);
  assert.equal(sim.state.lives, 3);
  assert.ok(sim.state.enemies.length >= 3);
  assert.ok(sim.state.enemies.every((e) => e.mode === 'house'));
});

test('bot random-walk survives 3000 frames with no exceptions and no NaN', () => {
  sim.beginGame();
  const dirs = ['KeyW', 'KeyA', 'KeyS', 'KeyD'];
  let changeCounter = 0;
  let current = 'KeyW';
  for (let i = 0; i < 3000; i++) {
    if (changeCounter-- <= 0) {
      Object.keys(sim.state.keys).forEach((k) => (sim.state.keys[k] = false));
      current = dirs[Math.floor(Math.random() * dirs.length)];
      changeCounter = 15 + Math.floor(Math.random() * 30);
    }
    sim.state.keys[current] = true;
    advance(33);
    sim.tick();
    assert.ok(isFiniteNum(sim.state.player.x), `player.x finite at frame ${i}`);
    assert.ok(isFiniteNum(sim.state.player.z), `player.z finite at frame ${i}`);
    for (const en of sim.state.enemies) {
      assert.ok(isFiniteNum(en.x) && isFiniteNum(en.z), `enemy position finite at frame ${i}`);
    }
    if (!sim.state.running) break;
  }
});

test('tunnel wraparound keeps the player within world bounds', () => {
  sim.beginGame();
  const maze = sim.state.maze;
  const worldW = maze.cols * sim.CELL;
  sim.state.player.x = -sim.CELL * 5;
  sim.state.player.z = maze.tunnelRow * sim.CELL;
  sim.state.player.yaw = 0;
  Object.keys(sim.state.keys).forEach((k) => (sim.state.keys[k] = false));
  advance(16);
  sim.tick();
  assert.ok(sim.state.player.x > -sim.CELL);
  assert.ok(sim.state.player.x < worldW);
});

test('enemies release from the house after their timer', () => {
  sim.beginGame();
  assert.ok(sim.state.enemies.every((e) => e.mode === 'house'));
  sim.state.enemies.forEach((en) => (en.releaseAt = 0));
  advance(50);
  for (let i = 0; i < 3; i++) sim.tick();
  assert.ok(sim.state.enemies.every((e) => e.mode !== 'house'));
});

test('a power pellet lets the player eat a frightened enemy for a score combo', () => {
  sim.beginGame();
  const scoreBefore = sim.state.score;
  const pr = Math.round(sim.state.player.z / sim.CELL);
  const pc = Math.round(sim.state.player.x / sim.CELL);
  const target = sim.state.enemies[0];
  target.mode = 'chase';
  pinEnemyAt(target, pr, pc);
  sim.state.frightenedUntil = 1e15;
  sim.state.player.invulnUntil = 0;
  sim.state.comboCount = 0;
  advance(16);
  sim.tick();
  assert.equal(target.mode, 'eaten');
  assert.ok(sim.state.score > scoreBefore);
});

test('a non-frightened collision costs a life', () => {
  sim.beginGame();
  const livesBefore = sim.state.lives;
  const en = sim.state.enemies[0];
  const pr = Math.round(sim.state.player.z / sim.CELL);
  const pc = Math.round(sim.state.player.x / sim.CELL);
  en.mode = 'chase';
  pinEnemyAt(en, pr, pc);
  sim.state.frightenedUntil = 0;
  sim.state.player.invulnUntil = 0;
  advance(16);
  sim.tick();
  assert.equal(sim.state.lives, livesBefore - 1);
});

test('losing the last life ends the game', () => {
  sim.beginGame();
  sim.state.lives = 1;
  const en = sim.state.enemies[0];
  const pr = Math.round(sim.state.player.z / sim.CELL);
  const pc = Math.round(sim.state.player.x / sim.CELL);
  en.mode = 'chase';
  pinEnemyAt(en, pr, pc);
  sim.state.frightenedUntil = 0;
  sim.state.player.invulnUntil = 0;
  advance(16);
  sim.tick();
  assert.equal(sim.state.running, false);
});

test('eating every pellet advances to the next level', () => {
  sim.beginGame();
  const levelBefore = sim.state.levelIndex;
  for (const [r, c] of sim.getPelletCells()) {
    sim.state.player.x = c * sim.CELL;
    sim.state.player.z = r * sim.CELL;
    advance(16);
    sim.tick();
  }
  for (const m of sim.getPowerMeshes()) {
    sim.state.player.x = m.userData.c * sim.CELL;
    sim.state.player.z = m.userData.r * sim.CELL;
    advance(16);
    sim.tick();
  }
  assert.ok(sim.state.pelletsRemaining <= 0);
  assert.equal(sim.state.running, false);
  const fired = runTimeouts();
  assert.ok(fired >= 1);
  assert.equal(sim.state.levelIndex, levelBefore + 1);
  assert.notEqual(sim.state.maze, null);
  assert.ok(sim.state.pelletsRemaining > 0);
});
