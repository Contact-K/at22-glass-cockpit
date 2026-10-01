// components/acid/InkLoader.jsx
try { (() => {
/* Sumi status loaders — coarse binary block grid, hard frames, seamless loops. Every loop starts and ends as the same solid 4×4 ink square, morphs (SDF blend) into the status motif, animates, and folds back.
   think 思考 (split & orbit) / search 検索 (magnifier) / write 書込 (pencil) / reply 返信 (bubble dots) / transfer 転送 (packet between keys) / download 取得 (arrow into tray) / delete 削除 (into bin) / connect 接続 (line grows between nodes, signal runs) / error エラー (the square cracks, shakes, mends).
   upload 送信 (arrow out of tray, pairs with download) / wait 承認待ち (a hand rises at top-right and waves from its base: left, up, right — tip pink while waving) / handoff 引き継ぎ (splits; the left half's pink contents flow into the empty right half; the left is left as an outline, then both bleed back to the square) / reread 読み返し (a file with a folded corner; the pink reading line runs to the bottom and jumps back to the top) / duplicate 複製 (copies stack behind the square one outline at a time, newest flashes pink) / idle 待機・うたた寝 (shoulders drop and spread, ink drips and a drop falls, then it jolts awake one cell and sucks the drop back up into the square) / done 完了 (square bleeds into a pink check, the check turns ink, bleeds back to the square — plays ONCE) / build ビルド (bricks stack into the square, gauge runs) / overload 文脈超過 (bleeds, drips, crumbles, then holds together). */
function rgb(el, c) {
  const s = document.createElement("span");
  s.style.color = c;
  el.appendChild(s);
  const v = getComputedStyle(s).color;
  el.removeChild(s);
  const m = v.match(/[\d.]+/g) || [0, 0, 0];
  return `rgba(${m[0]},${m[1]},${m[2]},1)`;
}
const TAU = Math.PI * 2,
  fr = v => v - Math.floor(v),
  cl = t => Math.max(0, Math.min(1, t)),
  ss = t => t * t * (3 - 2 * t);
const ALIAS = {
    compile: "build",
    test: "build",
    get: "download",
    doze: "idle"
  },
  NOMORPH = {
    idle: true
  },
  ONCE = {
    done: true
  },
  hsh = (x, y, n) => fr(Math.sin(x * 12.9898 + y * 78.233 + n * 37.719) * 43758.5453);
const PERIOD = {
  think: 2.6,
  search: 2.8,
  write: 2.8,
  reply: 2.8,
  transfer: 3.2,
  download: 2.6,
  upload: 2.6,
  delete: 2.6,
  connect: 2.8,
  error: 2.4,
  wait: 3.6,
  idle: 6.4,
  handoff: 3.6,
  reread: 3.6,
  duplicate: 3.6,
  done: 2.2,
  build: 3.0,
  overload: 2.6
};
/* 10×10 motif masks: 0 empty, 1 ink, 2 pink. q = 0..1 through the loop. */
const G = 10,
  near = (x, y, px, py, r) => (x - px) ** 2 + (y - py) ** 2 < r * r,
  seg = (x, y, ax, ay, bx, by, r) => {
    const vx = bx - ax,
      vy = by - ay,
      t = cl(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy));
    return near(x, y, ax + vx * t, ay + vy * t, r);
  };
const MOTIF = {
  search: q => {
    const a = q * TAU,
      cx = 3.6 + 1.1 * Math.sin(a),
      cy = 3.6 + 0.8 * Math.sin(2 * a),
      M = new Uint8Array(G * G);
    for (let y = 0; y < G; y++) for (let x = 0; x < G; x++) {
      const d = Math.hypot(x - cx, y - cy);
      if (Math.abs(d - 2.05) < 0.62 || seg(x, y, cx + 1.9, cy + 1.9, cx + 4.6, cy + 4.6, 0.8)) M[y * G + x] = 1;
    }
    const gx = Math.round(cx - 0.8),
      gy = Math.round(cy - 0.8);
    if (gx >= 0 && gy >= 0) M[gy * G + gx] = 2;
    return M;
  },
  write: q => {
    const M = new Uint8Array(G * G),
      wq = cl((q - 0.06) / 0.72),
      tx = 1 + 7 * wq,
      wy = x => 7 - (Math.round(x) % 3 === 1 ? 1 : 0),
      ty = wy(tx);
    for (let x = 1; x <= Math.floor(tx); x++) M[wy(x) * G + x] = 1;
    for (let y = 0; y < G; y++) for (let x = 0; x < G; x++) {
      if (seg(x, y, tx + 1.1, ty - 1.1, tx + 4.4, ty - 4.4, 1.05)) M[y * G + x] = 1;
    }
    const px = Math.round(tx),
      py = Math.round(ty);
    M[py * G + px] = 2;
    if (px + 1 < G && py - 1 >= 0) M[(py - 1) * G + px + 1] = 2;
    return M;
  },
  reply: q => {
    const M = new Uint8Array(G * G);
    for (let x = 0; x <= 8; x++) {
      M[1 * G + x] = 1;
      M[6 * G + x] = 1;
    }
    for (let y = 1; y <= 6; y++) {
      M[y * G] = 1;
      M[y * G + 8] = 1;
    }
    M[7 * G + 1] = 1;
    M[7 * G + 2] = 1;
    M[8 * G + 1] = 1;
    const f = fr(cl((q - 0.06) / 0.8) * 2) * 4,
      n = Math.floor(f);
    for (let i = 0; i < Math.min(3, n + (q > 0.06 && q < 0.86 ? 1 : 0)); i++) {
      const x = 2 + i * 2;
      M[3 * G + x] = M[4 * G + x] = i === n ? 2 : 1;
    }
    return M;
  },
  transfer: q => {
    const M = new Uint8Array(G * G),
      tq = cl((q - 0.04) / 0.8),
      f = tq * 4,
      n = Math.min(4, Math.floor(f)),
      t = f - n,
      run = tq < 1,
      sd = run && t < 0.2,
      dd = run && t > 0.8;
    const key = (x0, down) => {
      const y0 = down ? 8 : 7;
      for (let y = y0; y < y0 + 2; y++) for (let x = x0; x < x0 + 3; x++) M[y * G + x] = 1;
    };
    key(0, sd);
    key(7, dd);
    const done = n + (dd ? 1 : 0);
    for (let i = 0; i < Math.min(4, done); i++) {
      M[1 * G + 1 + i * 2] = M[1 * G + 2 + i * 2] = 1;
    }
    if (run && t >= 0.2 && t <= 0.8) {
      const u = (t - 0.2) / 0.6,
        px = Math.round(1 + 7 * u),
        py = Math.round(5.5 - 4 * u * (1 - u) * 3.2);
      M[py * G + px] = 2;
      if (py + 1 < G) M[(py + 1) * G + px] = 2;
    }
    return M;
  },
  download: q => {
    const M = new Uint8Array(G * G),
      f = cl((q - 0.04) / 0.84) * 2,
      t = fr(f),
      tip = Math.min(7, Math.floor(2 + t * 6.5)),
      land = tip >= 7 && q < 0.9;
    for (let x = 1; x <= 8; x++) M[9 * G + x] = land ? 2 : 1;
    for (let y = 7; y <= 9; y++) {
      M[y * G + 1] = M[y * G + 8] = 1;
    }
    const R = (y, x0, x1) => {
      if (y < 0 || y >= G) return;
      for (let x = x0; x <= x1; x++) M[y * G + x] = 1;
    };
    R(tip, 4, 5);
    R(tip - 1, 3, 6);
    R(tip - 2, 2, 7);
    R(tip - 3, 4, 5);
    R(tip - 4, 4, 5);
    return M;
  },
  delete: q => {
    const M = new Uint8Array(G * G),
      f = cl((q - 0.04) / 0.84),
      open = f > 0.1 && f < 0.75,
      by = Math.round(-2 + f * 9);
    const ly = open ? 1 : 2,
      lx = open ? 1 : 0;
    for (let x = 1; x <= 8; x++) M[ly * G + x + lx - (open ? 0 : 0)] = 1;
    M[(ly - 1) * G + 4 + lx] = M[(ly - 1) * G + 5 + lx] = 1;
    for (let y = 3; y <= 9; y++) {
      M[y * G + 2] = M[y * G + 7] = 1;
    }
    for (let x = 2; x <= 7; x++) M[9 * G + x] = 1;
    for (let y = 5; y <= 7; y++) {
      M[y * G + 4] = M[y * G + 5] = 1;
    }
    if (f < 0.85) for (let y = by; y < by + 2; y++) if (y >= 0 && y < 9 && (open || y < ly)) for (let x = 4; x <= 5; x++) M[y * G + x] = 2;
    return M;
  },
  upload: q => {
    const M = new Uint8Array(G * G),
      f = cl((q - 0.04) / 0.84) * 2,
      t = fr(f),
      tip = Math.round(5 - t * 8),
      launch = t < 0.15 && q < 0.9;
    for (let x = 1; x <= 8; x++) M[9 * G + x] = launch ? 2 : 1;
    for (let y = 7; y <= 9; y++) {
      M[y * G + 1] = M[y * G + 8] = 1;
    }
    const R = (y, x0, x1) => {
      if (y < 0 || y >= 7) return;
      for (let x = x0; x <= x1; x++) M[y * G + x] = 1;
    };
    R(tip, 4, 5);
    R(tip + 1, 3, 6);
    R(tip + 2, 2, 7);
    R(tip + 3, 4, 5);
    R(tip + 4, 4, 5);
    return M;
  },
  connect: q => {
    const M = new Uint8Array(G * G);
    for (let y = 3; y <= 5; y++) for (const x of [0, 1, 2, 7, 8, 9]) M[y * G + x] = 1;
    const e = cl(q / 0.45),
      n = Math.floor(e * 4.99);
    for (let x = 3; x < 3 + n; x++) M[4 * G + x] = 1;
    if (e < 1) M[4 * G + Math.min(6, 3 + n)] = 2;else {
      const u = fr((q - 0.45) / 0.25),
        px = Math.round(3 + u * 3.99);
      M[4 * G + px] = 2;
      if (q > 0.7 && Math.floor(q * 16) % 2 === 0) for (const [x, y] of [[1, 4], [8, 4]]) M[y * G + x] = 2;
    }
    return M;
  },
  wait: q => {
    const M = new Uint8Array(G * G),
      S = (x, y, v = 1) => {
        if (x >= 0 && y >= 0 && x < G && y < G) M[y * G + x] = v;
      };
    for (let y = 3; y <= 6; y++) for (let x = 3; x <= 6; x++) S(x, y);
    S(6, 2);
    const wv = q > 0.1 && q < 0.44 || q > 0.54 && q < 0.86,
      pose = wv ? [0, 1, 2, 1][Math.floor(q * 28) % 4] : 1,
      A = [[[5, 1], [4, 0]], [[6, 1], [6, 0]], [[7, 1], [8, 0]]][pose];
    S(...A[0]);
    S(...A[1], wv ? 2 : 1);
    return M;
  },
  handoff: q => {
    const M = new Uint8Array(G * G),
      S = (x, y, v = 1) => {
        x = Math.round(x);
        if (x >= 0 && y >= 0 && x < G && y < G) M[y * G + x] = v;
      },
      RC = (x0, y0, x1, y1, v = 1) => {
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) S(x, y, v);
      },
      RG = (x0, y0, x1, y1) => {
        for (let x = x0; x <= x1; x++) {
          S(x, y0);
          S(x, y1);
        }
        for (let y = y0; y <= y1; y++) {
          S(x0, y);
          S(x1, y);
        }
      };
    if (q < 0.08) {
      RC(3, 3, 6, 6);
      return M;
    }
    if (q < 0.18) {
      RC(2, 3, 3, 6);
      RC(6, 3, 7, 6);
      return M;
    }
    if (q >= 0.66) {
      RG(0, 3, 2, 6);
      RC(7, 3, 9, 6);
      return M;
    }
    const k = q < 0.3 ? 0 : q < 0.62 ? Math.ceil((q - 0.3) / 0.32 * 5) : 5;
    RC(0, 3, 2, 6);
    RG(7, 3, 9, 6);
    if (k > 0) {
      S(1, 4, 0);
      S(1, 5, 0);
      if (k < 5) {
        const x = 2 + k * 1.2;
        S(x, 4, 2);
        S(x, 5, 2);
      } else {
        S(8, 4, 2);
        S(8, 5, 2);
      }
    }
    return M;
  },
  reread: q => {
    const M = new Uint8Array(G * G);
    for (let y = 1; y <= 8; y++) for (let x = 2; x <= 7; x++) M[y * G + x] = 1;
    M[1 * G + 7] = M[1 * G + 6] = M[2 * G + 7] = 0;
    M[2 * G + 6] = 2;
    const u = fr(q * 2),
      y = 2 + Math.min(5, Math.floor(u * 6));
    for (let x = 3; x <= 6; x++) M[y * G + x] = u < 0.9 ? 2 : 1;
    return M;
  },
  duplicate: q => {
    const M = new Uint8Array(G * G),
      n = Math.min(3, Math.floor(q * 3.6)),
      RG = (x0, y0, x1, y1, v) => {
        for (let x = x0; x <= x1; x++) for (const y of [y0, y1]) if (x >= 0 && y >= 0 && x < G && y < G) M[y * G + x] = v;
        for (let y = y0; y <= y1; y++) for (const x of [x0, x1]) if (x >= 0 && y >= 0 && x < G && y < G) M[y * G + x] = v;
      };
    for (let k = n; k >= 1; k--) RG(3 + k, 3 - k, 6 + k, 6 - k, k === n && fr(q * 3.6) < 0.35 ? 2 : 1);
    for (let y = 3; y <= 6; y++) for (let x = 3; x <= 6; x++) M[y * G + x] = 1;
    return M;
  },
  idle: q => {
    const M = new Uint8Array(G * G),
      S = (x, y, v = 1) => {
        if (x >= 0 && y >= 0 && x < G && y < G) M[y * G + x] = v;
      },
      RC = (x0, y0, x1, y1) => {
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) S(x, y);
      },
      SAG = () => {
        RC(3, 4, 6, 6);
        S(2, 6);
        S(7, 6);
      };
    if (q < 0.12 || q >= 0.66) {
      RC(3, 3, 6, 6);
      return M;
    }
    if (q < 0.16) {
      RC(3, 3, 6, 6);
      S(2, 6);
      S(7, 6);
      return M;
    }
    if (q < 0.5) {
      SAG();
      if (q > 0.22 && q < 0.34) S(5, 7);
      if (q > 0.3 && q < 0.4) {
        S(5, 7);
        S(5, 8);
      }
      if (q >= 0.4) S(5, 9);
      return M;
    }
    RC(3, 2, 6, 5);
    if (q < 0.54) S(5, 9);else if (q < 0.58) S(5, 8, 2);else if (q < 0.62) {
      S(5, 7, 2);
      S(5, 6, 2);
    } else {
      M.fill(0);
      RC(3, 3, 6, 6);
    }
    return M;
  },
  done: q => {
    const M = new Uint8Array(G * G),
      C = [[1, 5], [2, 6], [3, 7], [4, 6], [5, 5], [6, 4], [7, 3], [8, 2]],
      n = Math.min(C.length, Math.ceil(cl(q / 0.5) * C.length)),
      v = q > 0.65 ? 1 : 2;
    if (!n) {
      for (let y = 3; y <= 6; y++) for (let x = 3; x <= 6; x++) M[y * G + x] = 1;
      return M;
    }
    for (let k = 0; k < n; k++) {
      const [x, y] = C[k];
      M[y * G + x] = v;
      M[(y + 1) * G + x] = v;
    }
    return M;
  },
  build: q => {
    const M = new Uint8Array(G * G),
      u = cl((q - 0.04) / 0.8),
      f = u * 4,
      n = Math.min(4, Math.floor(f)),
      t = f - n;
    for (let i = 0; i < n; i++) for (let x = 3; x <= 6; x++) M[(6 - i) * G + x] = 1;
    if (n < 4) {
      const ty = 6 - n,
        k = Math.min(1, Math.ceil(t * 6) / 6 / 0.85),
        y = Math.round(ty * k);
      for (let x = 3; x <= 6; x++) M[y * G + x] = k < 1 ? 2 : 1;
    }
    const gx = Math.round(1 + u * 7);
    for (let x = 1; x <= 8; x++) M[9 * G + x] = x < gx ? 1 : x === gx ? 2 : 0;
    return M;
  },
  overload: q => {
    const M = new Uint8Array(G * G),
      a = Math.sin(Math.PI * cl(q / 0.92)),
      fn = Math.floor(q * 31);
    for (let y = 0; y < G; y++) for (let x = 0; x < G; x++) {
      const e = Math.max(Math.abs(x - 4.5), Math.abs(y - 4.5)) - 1.5,
        r = hsh(x, y, fn);
      if (e <= 0) {
        if (!(a > 0.55 && r < (a - 0.55) * 0.7)) M[y * G + x] = 1;
      } else if (e <= 1) {
        if (r < a * 0.85) M[y * G + x] = r < a * 0.3 ? 2 : 1;
      } else if (e <= 2) {
        if (r < a * 0.35) M[y * G + x] = 1;
      } else if (r < a * 0.1) M[y * G + x] = 2;
    }
    for (let x = 3; x <= 6; x++) {
      const len = Math.floor(a * 4.2 * fr(Math.sin(x * 91.37) * 4375.5));
      for (let y = 7; y < 7 + len && y < G; y++) M[y * G + x] = 1;
    }
    return M;
  },
  error: q => {
    const M = new Uint8Array(G * G),
      o = q < 0.15 ? 0 : q < 0.3 ? 1 : q < 0.6 ? 2 : q < 0.75 ? 1 : 0,
      sh = q > 0.3 && q < 0.6 ? [0, 1, 0, -1][Math.floor(q * 40) % 4] : 0,
      J = [0, 1, 0, 1];
    for (let r = 0; r < 4; r++) {
      const y = 3 + r,
        cut = 4 + J[r];
      for (let x = 3; x <= 6; x++) {
        const XX = (x <= cut ? x - Math.ceil(o / 2) : x + Math.floor(o / 2) + (o ? 1 : 0)) + sh;
        if (XX >= 0 && XX < G) M[y * G + XX] = 1;
      }
      if (o > 0) for (let g = 0; g < o; g++) {
        const gx = cut + 1 - Math.ceil(o / 2) + g + sh;
        if (gx >= 0 && gx < G && !M[y * G + gx]) M[y * G + gx] = 2;
      }
    }
    return M;
  }
};
function InkLoader({
  status = "think",
  size: _size,
  pitch = 5,
  gap = 0,
  speed = 1,
  fps = 24,
  color = "var(--fg)",
  accent = "var(--accent-pop)",
  label,
  onLoop,
  style
}) {
  const st = ALIAS[status] || status;
  const size = 10;
  pitch = Math.max(1, pitch);
  const cv = React.useRef(null),
    LP = React.useRef(onLoop);
  LP.current = onLoop;
  React.useEffect(() => {
    const c = cv.current;
    if (!c) return;
    const ctx = c.getContext("2d"),
      dpr = Math.min(3, window.devicePixelRatio || 1),
      S = size * pitch;
    const P = Math.max(1, Math.round(pitch * dpr)),
      SD = size * P;
    c.width = SD;
    c.height = SD;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.imageSmoothingEnabled = false;
    const on = rgb(c, color),
      ac = rgb(c, accent),
      m = (size - 1) / 2,
      T = PERIOD[st] || 2.6,
      k = size / 10,
      H = 2 * k,
      R0 = 2.3 * k;
    const gd = Math.round(gap * dpr),
      cell = (x, y, col) => {
        if (x < 0 || y < 0 || x >= size || y >= size) return;
        ctx.fillStyle = col;
        ctx.fillRect(x * P + (gd >> 1), y * P + (gd >> 1), P - gd, P - gd);
      };
    const sq = (x, y) => (Math.max(Math.abs(x - m), Math.abs(y - m)) - H) / (H + 0.5);
    const draw = (B, w) => {
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const dx = x - m,
          dy = y - m;
        let f = 0,
          best = 0,
          bi = -1;
        for (let i = 0; i < B.length; i++) {
          const [bx, by, r] = B[i],
            v = r * r / ((dx - bx) ** 2 + (dy - by) ** 2 + 0.01);
          f += v;
          if (v > best) {
            best = v;
            bi = i;
          }
        }
        const v = (1 - w) * sq(x, y) + w * (1 - Math.sqrt(f));
        if (v < 0) cell(x, y, w > 0.5 && B[bi][3] ? ac : on);
      }
    };
    const drawMask = (M, w) => {
      const at = (x, y) => M[Math.min(G - 1, Math.floor(y * G / size)) * G + Math.min(G - 1, Math.floor(x * G / size))],
        lit = [],
        un = [];
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) (at(x, y) ? lit : un).push([x, y]);
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const a = at(x, y);
        let v;
        if (w >= 1) v = a ? -1 : 1;else {
          let d = 1e9;
          for (const [X, Y] of a ? un : lit) {
            const e = (X - x) ** 2 + (Y - y) ** 2;
            if (e < d) d = e;
          }
          d = Math.sqrt(d) - 0.5;
          v = (1 - w) * sq(x, y) + w * (a ? -d : d) / (H + 0.5);
        }
        if (v < 0) cell(x, y, w > 0.5 && a === 2 ? ac : on);
      }
    };
    let raf,
      to,
      t0 = performance.now(),
      lastCy = -1;
    const tick = now => {
      clearTimeout(to);
      ctx.clearRect(0, 0, SD, SD);
      const tq = Math.floor((now - t0) / (1000 / fps)) / fps * speed;
      const cy = Math.floor(tq / T);
      if (cy !== lastCy) {
        if (lastCy >= 0 && LP.current) LP.current(cy);
        lastCy = cy;
      }
      const p = ONCE[st] ? cl(tq / T) : fr(Math.floor((now - t0) / (1000 / fps)) / fps * speed / T);
      if (ONCE[st] && p >= 1) {
        ctx.clearRect(0, 0, SD, SD);
        drawMask(MOTIF[st](0), 0);
        if (LP.current) LP.current(0);
        return;
      }
      {
        const w = NOMORPH[st] ? 1 : p < 0.1 ? 0 : p < 0.22 ? ss((p - 0.1) / 0.12) : p < 0.8 ? 1 : p < 0.92 ? 1 - ss((p - 0.8) / 0.12) : 0,
          q = NOMORPH[st] ? p : cl((p - 0.1) / 0.82);
        if (MOTIF[st]) drawMask(MOTIF[st](q), w);else {
          const sp = Math.sin(Math.PI * q),
            a = Math.PI * q * 2 + Math.PI / 4,
            D = 2.1 * k * sp,
            r = R0 / Math.SQRT2 * (1 - 0.12 * sp);
          draw([[D * Math.cos(a), D * Math.sin(a), r, 0], [-D * Math.cos(a), -D * Math.sin(a), r, 1]], w);
        }
      }
      raf = requestAnimationFrame(tick);
      to = setTimeout(() => {
        cancelAnimationFrame(raf);
        tick(performance.now());
      }, 80);
    };
    tick(t0);
    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(to);
    };
  }, [st, size, pitch, gap, speed, fps, color, accent]);
  return /*#__PURE__*/React.createElement("span", {
    role: "status",
    "aria-label": label || "Loading",
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 12,
      ...style
    }
  }, /*#__PURE__*/React.createElement("canvas", {
    ref: cv,
    style: {
      display: "block",
      width: size * pitch,
      height: size * pitch
    }
  }), label ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: "400 11px/1 var(--font-mono)",
      letterSpacing: ".14em",
      textTransform: "uppercase",
      color: "var(--fg-2)"
    }
  }, label) : null);
}
Object.assign(__ds_scope, { InkLoader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/InkLoader.jsx", error: String((e && e.message) || e) }); }

