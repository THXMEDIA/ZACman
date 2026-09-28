// Headless logic simulation for web/index.html's game script.
// Stubs the DOM/Three.js/Audio surface with lightweight fakes so the REAL
// shipped game-logic code (maze, collision, enemy AI, pickups, scoring,
// level flow) runs unmodified inside a Node vm context, driven by a bot.
//
// This extracts the script directly from web/index.html, so the simulation
// always tests exactly what ships — there is no separately maintained copy.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const htmlPath = path.join(__dirname, '..', 'web', 'index.html');
const html = fs.readFileSync(htmlPath, 'utf8');
const match = html.match(/<script>\n\(function \(\) \{[\s\S]*?\n\}\)\(\);\n<\/script>/);
if (!match) throw new Error('could not find the inline game script in web/index.html');
let code = match[0].slice('<script>\n'.length, -'\n</script>'.length);

const marker = '\n})();';
const idx = code.lastIndexOf(marker);
if (idx === -1) throw new Error('could not find IIFE close to inject test exports');
code =
  code.slice(0, idx) +
  `
  globalThis.__sim = {
    state, tick, startLevel, beginGame, togglePause, LEVELS, CELL,
    getPelletCells: () => pelletCells,
    getPowerMeshes: () => powerMeshes,
    neighborsOf,
  };
` +
  code.slice(idx);

/* ---------------- fake Object3D-ish base ---------------- */
function Obj3D() {
  this.position = {
    x: 0,
    y: 0,
    z: 0,
    set(x, y, z) {
      this.x = x;
      this.y = y;
      this.z = z;
      return this;
    },
  };
  this.rotation = { x: 0, y: 0, z: 0, order: 'XYZ' };
  this.scale = {
    x: 1,
    y: 1,
    z: 1,
    setScalar(s) {
      this.x = this.y = this.z = s;
    },
  };
  this.visible = true;
  this.userData = {};
  this.children = [];
  this.matrix = {};
}
Obj3D.prototype.add = function (...c) {
  this.children.push(...c);
  return this;
};
Obj3D.prototype.remove = function (c) {
  const i = this.children.indexOf(c);
  if (i >= 0) this.children.splice(i, 1);
  return this;
};
Obj3D.prototype.updateMatrix = function () {};

function colorStub() {
  return {
    hex: 0,
    setHex(h) {
      this.hex = h;
    },
    set(h) {
      this.hex = h;
    },
  };
}

function MeshStandardMaterial(opts) {
  this.color = colorStub();
  this.emissive = colorStub();
  Object.assign(this, opts || {});
  if (!this.color || typeof this.color.setHex !== 'function') this.color = colorStub();
  if (!this.emissive || typeof this.emissive.setHex !== 'function') this.emissive = colorStub();
}
function MeshBasicMaterial(opts) {
  this.color = colorStub();
  Object.assign(this, opts || {});
}
function LineBasicMaterial(opts) {
  Object.assign(this, opts || {});
}

function InstancedMesh(geo, mat, count) {
  Obj3D.call(this);
  this.count = count;
  this.instanceMatrix = { needsUpdate: false };
}
InstancedMesh.prototype = Object.create(Obj3D.prototype);
InstancedMesh.prototype.setMatrixAt = function () {};

function Group() {
  Obj3D.call(this);
}
Group.prototype = Object.create(Obj3D.prototype);
function Mesh() {
  Obj3D.call(this);
}
Mesh.prototype = Object.create(Obj3D.prototype);
function LightLike() {
  Obj3D.call(this);
}
LightLike.prototype = Object.create(Obj3D.prototype);

function NoopGeo() {}

function PerspectiveCamera(fov, aspect) {
  Obj3D.call(this);
  this.fov = fov;
  this.aspect = aspect;
}
PerspectiveCamera.prototype = Object.create(Obj3D.prototype);
PerspectiveCamera.prototype.updateProjectionMatrix = function () {};

function Scene() {
  Obj3D.call(this);
  this.background = null;
  this.fog = null;
}
Scene.prototype = Object.create(Obj3D.prototype);

function WebGLRenderer(opts) {
  this.domElement = (opts && opts.canvas) || {};
}
WebGLRenderer.prototype.setPixelRatio = function () {};
WebGLRenderer.prototype.setSize = function () {};
WebGLRenderer.prototype.render = function () {};

function Clock() {
  this._last = globalThis.__fakeNowSec();
}
Clock.prototype.getDelta = function () {
  const now = globalThis.__fakeNowSec();
  const d = now - this._last;
  this._last = now;
  return d;
};

const THREE = {
  WebGLRenderer,
  Scene,
  PerspectiveCamera,
  Color: function () {},
  FogExp2: function () {},
  AmbientLight: LightLike,
  HemisphereLight: LightLike,
  PointLight: LightLike,
  MeshStandardMaterial,
  MeshBasicMaterial,
  LineBasicMaterial,
  BoxGeometry: NoopGeo,
  EdgesGeometry: NoopGeo,
  SphereGeometry: NoopGeo,
  PlaneGeometry: NoopGeo,
  IcosahedronGeometry: NoopGeo,
  OctahedronGeometry: NoopGeo,
  Group,
  InstancedMesh,
  Mesh,
  Object3D: Obj3D,
  Clock,
};

/* ---------------- fake DOM ---------------- */
function makeCtx2D() {
  const noop = () => {};
  return new Proxy(
    {},
    {
      get() {
        return noop;
      },
    }
  );
}

function makeElement(id) {
  const listeners = {};
  const el = {
    id,
    style: {},
    dataset: {},
    hidden: false,
    textContent: '',
    className: '',
    width: 140,
    height: 140,
    classList: {
      add() {},
      remove() {},
      contains() {
        return false;
      },
      toggle() {},
    },
    children: [],
    appendChild(c) {
      this.children.push(c);
    },
    addEventListener(evt, cb) {
      (listeners[evt] = listeners[evt] || []).push(cb);
    },
    removeEventListener() {},
    querySelectorAll() {
      return [];
    },
    getContext() {
      return makeCtx2D();
    },
    requestPointerLock: undefined,
    __fire(evt, e) {
      (listeners[evt] || []).forEach((cb) => cb(e));
    },
  };
  return el;
}

const elements = {};
function getElementById(id) {
  if (!elements[id]) elements[id] = makeElement(id);
  return elements[id];
}

const documentStub = {
  body: makeElement('body'),
  documentElement: makeElement('html'),
  getElementById,
  querySelectorAll() {
    return [];
  },
  addEventListener() {},
  removeEventListener() {},
  exitPointerLock() {},
  pointerLockElement: null,
  createElement() {
    return makeElement('dyn');
  },
};

let fakeClockMs = 0;
globalThis.__fakeNowSec = () => fakeClockMs / 1000;

const store = {};
const localStorageStub = {
  getItem(k) {
    return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null;
  },
  setItem(k, v) {
    store[k] = String(v);
  },
};

function AudioContextStub() {
  this.state = 'running';
  this.currentTime = 0;
  this.destination = {};
}
AudioContextStub.prototype.resume = function () {};
AudioContextStub.prototype.createGain = function () {
  return {
    gain: { value: 0, setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {}, setTargetAtTime() {} },
    connect() {},
  };
};
AudioContextStub.prototype.createOscillator = function () {
  return {
    type: 'sine',
    frequency: { setValueAtTime() {}, exponentialRampToValueAtTime() {}, setTargetAtTime() {} },
    connect() {},
    start() {},
    stop() {},
  };
};

const windowStub = {
  innerWidth: 1280,
  innerHeight: 800,
  devicePixelRatio: 1,
  addEventListener() {},
  removeEventListener() {},
  AudioContext: AudioContextStub,
  webkitAudioContext: AudioContextStub,
  claude: undefined,
};

const navigatorStub = { maxTouchPoints: 0 };

const context = {
  console,
  THREE,
  document: documentStub,
  window: windowStub,
  navigator: navigatorStub,
  localStorage: localStorageStub,
  performance: { now: () => fakeClockMs },
  requestAnimationFrame: () => {},
  setTimeout: (fn) => {
    context.__pendingTimeouts.push({ fn });
    return context.__pendingTimeouts.length;
  },
  clearTimeout: () => {},
  __pendingTimeouts: [],
  Math,
  Set,
  Map,
  Array,
  JSON,
  globalThis: undefined,
};
context.globalThis = context;
context.self = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'zacman-game-script.js' });

module.exports = {
  sim: context.__sim,
  advance(ms) {
    fakeClockMs += ms;
  },
  runTimeouts() {
    const pending = context.__pendingTimeouts.splice(0);
    pending.forEach((t) => t.fn());
    return pending.length;
  },
};
