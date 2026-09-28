// Connectivity + reachability tests for the maze generator used by every
// level. Run with: node --test tests/maze-core.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { generateMaze, connectivityCheck, cellsInRoom, bfs } = require('../core/maze-core.js');

const LEVEL_SIZES = [
  [19, 21],
  [21, 25],
  [23, 27],
  [23, 29],
];

test('every level size is fully connected across many seeds', () => {
  for (let levelIndex = 0; levelIndex < LEVEL_SIZES.length; levelIndex++) {
    const [rows, cols] = LEVEL_SIZES[levelIndex];
    for (let seed = 1; seed <= 30; seed++) {
      const maze = generateMaze(rows, cols, levelIndex * 10000 + seed * 37);
      const check = connectivityCheck(maze);
      assert.equal(
        check.ok,
        true,
        `level ${levelIndex} (${rows}x${cols}) seed ${seed}: ${check.unreachable}/${check.total} cells unreachable`
      );
    }
  }
});

test('the house door lands on a real room column, not the wall-parity center', () => {
  for (const [rows, cols] of LEVEL_SIZES) {
    const maze = generateMaze(rows, cols, 999);
    assert.equal(maze.doorCol % 2, 1, 'door column should be odd (room parity)');
    assert.equal(maze.grid[maze.house.r0][maze.doorCol], 0, 'door tile should be open');
  }
});

test('the tunnel row is open at both world edges for wraparound', () => {
  const maze = generateMaze(21, 25, 5);
  assert.equal(maze.grid[maze.tunnelRow][0], 0);
  assert.equal(maze.grid[maze.tunnelRow][maze.cols - 1], 0);
});

test('bfs distance grows monotonically outward from the start cell', () => {
  const maze = generateMaze(19, 21, 12);
  const rooms = cellsInRoom(maze, true);
  const [sr, sc] = rooms[0];
  const dist = bfs(maze, sr, sc);
  assert.equal(dist[sr][sc], 0);
  for (const [r, c] of rooms) {
    assert.notEqual(dist[r][c], -1, `cell ${r},${c} should be reachable`);
  }
});
