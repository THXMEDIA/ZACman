// Core maze logic for "Kugelschlucker" — tested standalone before embedding in the artifact.
// Grid convention: rows x cols, both ODD. Cells at (r,c) with r odd AND c odd are "rooms".
// Cells with r even or c even are potential walls between rooms (or fixed walls on the border).
// 0 = open, 1 = wall.

function makeRng(seed) {
  let s = seed >>> 0;
  return function () {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function generateMaze(rows, cols, seed) {
  if (rows % 2 === 0 || cols % 2 === 0) throw new Error('rows/cols must be odd');
  const rng = makeRng(seed);
  const grid = Array.from({ length: rows }, () => Array(cols).fill(1));

  const mid = (cols - 1) / 2; // center column index (wall parity, shared axis)

  // central house footprint, chosen on WALL parity (even r, even c) so its border
  // aligns with the natural wall grid instead of overwriting real room nodes.
  const evenNear = (n) => (n % 2 === 0 ? n : n - 1);
  const midRowEven = evenNear(Math.floor(rows / 2));
  const hw = Math.max(2, evenNear(Math.floor(cols * 0.14))); // half-width, even
  const hh = 2; // half-height, even (rows/cols step by 2)
  const house = { r0: midRowEven - hh, r1: midRowEven + hh, c0: mid - hw, c1: mid + hw, mid };

  const insideHouse = (r, c) => r > house.r0 && r < house.r1 && c > house.c0 && c < house.c1;

  const roomRows = [];
  for (let r = 1; r < rows; r += 2) roomRows.push(r);
  const roomColsLeft = [];
  for (let c = 1; c <= mid; c += 2) roomColsLeft.push(c);

  // open all room cells within left half, excluding anything inside the house footprint
  for (const r of roomRows) for (const c of roomColsLeft) if (!insideHouse(r, c)) grid[r][c] = 0;

  // randomized DFS spanning tree over left-half rooms (house cells excluded entirely)
  const key = (r, c) => r + ',' + c;
  const visited = new Set();
  const startRoom = roomRows.find((r) => roomColsLeft.some((c) => !insideHouse(r, c)));
  const startCol = roomColsLeft.find((c) => !insideHouse(startRoom, c));
  const stack = [[startRoom, startCol]];
  visited.add(key(startRoom, startCol));
  while (stack.length) {
    const [r, c] = stack[stack.length - 1];
    const neighbors = [
      [r - 2, c, r - 1, c],
      [r + 2, c, r + 1, c],
      [r, c - 2, r, c - 1],
      [r, c + 2, r, c + 1],
    ].filter(
      ([nr, nc]) =>
        roomRows.includes(nr) && roomColsLeft.includes(nc) && !insideHouse(nr, nc) && !visited.has(key(nr, nc))
    );
    if (neighbors.length === 0) {
      stack.pop();
      continue;
    }
    const [nr, nc, wr, wc] = neighbors[Math.floor(rng() * neighbors.length)];
    grid[wr][wc] = 0;
    visited.add(key(nr, nc));
    stack.push([nr, nc]);
  }

  // add loops: knock extra walls between adjacent left-half rooms (never touching the house)
  for (const r of roomRows) {
    for (const c of roomColsLeft) {
      if (insideHouse(r, c)) continue;
      if (c + 2 <= mid && !insideHouse(r, c + 2) && rng() < 0.16) grid[r][c + 1] = 0;
      const r2 = r + 2;
      if (roomRows.includes(r2) && !insideHouse(r2, c) && rng() < 0.16) grid[r + 1][c] = 0;
    }
  }

  // mirror left half (cols 0..mid) onto right half (mid..cols-1)
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c <= mid; c++) {
      grid[r][cols - 1 - c] = grid[r][c];
    }
  }

  // carve a horizontal tunnel: pick a room row roughly in the middle, open the full row at both edges
  const tunnelRow = roomRows[Math.floor(roomRows.length / 2)];
  grid[tunnelRow][0] = 0;
  grid[tunnelRow][1] = 0;
  grid[tunnelRow][cols - 1] = 0;
  grid[tunnelRow][cols - 2] = 0;

  // open the house interior and punch a single door on its top border, wired
  // into the room cell directly above it, which is already part of the tree.
  for (let r = house.r0 + 1; r < house.r1; r++) {
    for (let c = house.c0 + 1; c < house.c1; c++) grid[r][c] = 0;
  }
  // the door must land on a ROOM column (odd parity) so it actually connects
  // to a real room cell above it; the wall-parity center column dead-ends.
  const doorCol = mid % 2 === 0 ? mid - 1 : mid;
  grid[house.r0][doorCol] = 0;

  return { grid, rows, cols, tunnelRow, house, doorCol };
}

function isOpen(maze, r, c) {
  if (r < 0 || r >= maze.rows) return false;
  if (c < 0) c = maze.cols - 1;
  if (c >= maze.cols) c = 0;
  return maze.grid[r][c] === 0;
}

function cellsInRoom(maze, includeHouse) {
  const list = [];
  for (let r = 1; r < maze.rows; r += 2) {
    for (let c = 1; c < maze.cols; c += 2) {
      if (maze.grid[r][c] !== 0) continue;
      const inHouse = r > maze.house.r0 && r < maze.house.r1 && c > maze.house.c0 && c < maze.house.c1;
      if (inHouse && !includeHouse) continue;
      list.push([r, c]);
    }
  }
  return list;
}

// BFS over the OPEN-cell grid graph (every open cell is a node, 4-neighborhood, with tunnel wraparound)
function bfs(maze, startR, startC) {
  const dist = Array.from({ length: maze.rows }, () => Array(maze.cols).fill(-1));
  if (!isOpen(maze, startR, startC)) return dist;
  dist[startR][startC] = 0;
  const q = [[startR, startC]];
  let qi = 0;
  while (qi < q.length) {
    const [r, c] = q[qi++];
    const neighbors = [
      [r - 1, c],
      [r + 1, c],
      [r, c === 0 ? maze.cols - 1 : c - 1],
      [r, c === maze.cols - 1 ? 0 : c + 1],
    ];
    for (const [nr, nc] of neighbors) {
      if (!isOpen(maze, nr, nc)) continue;
      if (dist[nr][nc] !== -1) continue;
      dist[nr][nc] = dist[r][c] + 1;
      q.push([nr, nc]);
    }
  }
  return dist;
}

function connectivityCheck(maze) {
  const rooms = cellsInRoom(maze, true);
  const [sr, sc] = rooms[0];
  const dist = bfs(maze, sr, sc);
  const unreachable = rooms.filter(([r, c]) => dist[r][c] === -1);
  return { total: rooms.length, unreachable: unreachable.length, ok: unreachable.length === 0 };
}

module.exports = { generateMaze, isOpen, cellsInRoom, bfs, connectivityCheck, makeRng };
