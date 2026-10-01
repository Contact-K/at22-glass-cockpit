// components/acid/Suminagashi.jsx
try { (() => {
/* Stam "Stable Fluids" (semi-Lagrangian advection + Jacobi projection) + vorticity confinement, tuned as watercolour ink in a still tank: soft diffusing clouds (spread), heavy ink settles (sink) while the accent floats, density maps onto a 3-stop ramp (paper → ink → deep ink) so dense areas go navy. Fixed 30Hz step scaled by `speed`; pauses offscreen. Drag = stir + ink, shift = accent, hover (opt-in) = gentle ripple, auto = slow convection + drops. */
function cssColor(el, c) {
  const s = document.createElement("span");
  s.style.color = c;
  el.appendChild(s);
  const v = getComputedStyle(s).color;
  el.removeChild(s);
  const m = v.match(/[\d.]+/g) || [0, 0, 0];
  return [+m[0], +m[1], +m[2]];
}
function Suminagashi({
  width = 640,
  height = 360,
  res = 112,
  ink = "currentColor",
  accent = "var(--accent-pop)",
  bg = "var(--bg)",
  auto = true,
  speed = 0.35,
  dissolve = 0.9993,
  spread = 0.06,
  sink = 0.05,
  viscosity = 0.997,
  strength = 1,
  curlStrength = 0.18,
  grain = true,
  dropEvery = 6,
  brush = 0.045,
  hover = false,
  warmup = 40,
  soft = 0.8,
  style,
  onReady
}) {
  const cv = React.useRef(null),
    api = React.useRef(null);
  React.useEffect(() => {
    const c = cv.current,
      ctx = c.getContext("2d"),
      N = res,
      M = Math.round(res * height / width),
      S = N + 2,
      T = M + 2;
    const off = document.createElement("canvas");
    off.width = N;
    off.height = M;
    const octx = off.getContext("2d");
    const img = octx.createImageData(N, M);
    const F = Float32Array;
    let u = new F(S * T),
      v = new F(S * T),
      u0 = new F(S * T),
      v0 = new F(S * T),
      d1 = new F(S * T),
      d2 = new F(S * T),
      d0 = new F(S * T),
      p = new F(S * T),
      div = new F(S * T),
      curl = new F(S * T);
    const IX = (i, j) => i + S * j;
    const I = cssColor(c, ink),
      A = cssColor(c, accent),
      B = cssColor(c, bg);
    const ID = I.map(x => x * 0.38),
      AD = A.map((x, k) => x * 0.55 + I[k] * 0.25);
    const gr = new F(S * T);
    for (let k = 0; k < gr.length; k++) gr[k] = grain ? (Math.random() - 0.5) * 0.06 : 0;
    function bnd(x) {
      for (let i = 1; i <= N; i++) {
        x[IX(i, 0)] = x[IX(i, 1)];
        x[IX(i, M + 1)] = x[IX(i, M)];
      }
      for (let j = 1; j <= M; j++) {
        x[IX(0, j)] = x[IX(1, j)];
        x[IX(N + 1, j)] = x[IX(N, j)];
      }
    }
    function project() {
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        div[IX(i, j)] = -0.5 * (u[IX(i + 1, j)] - u[IX(i - 1, j)] + v[IX(i, j + 1)] - v[IX(i, j - 1)]) / N;
        p[IX(i, j)] = 0;
      }
      for (let k = 0; k < 14; k++) {
        for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) p[IX(i, j)] = (div[IX(i, j)] + p[IX(i - 1, j)] + p[IX(i + 1, j)] + p[IX(i, j - 1)] + p[IX(i, j + 1)]) / 4;
        bnd(p);
      }
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        u[IX(i, j)] -= 0.5 * N * (p[IX(i + 1, j)] - p[IX(i - 1, j)]);
        v[IX(i, j)] -= 0.5 * N * (p[IX(i, j + 1)] - p[IX(i, j - 1)]);
      }
      bnd(u);
      bnd(v);
    }
    function vorticity(eps) {
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) curl[IX(i, j)] = 0.5 * (v[IX(i + 1, j)] - v[IX(i - 1, j)] - (u[IX(i, j + 1)] - u[IX(i, j - 1)]));
      for (let j = 2; j < M; j++) for (let i = 2; i < N; i++) {
        const gx = 0.5 * (Math.abs(curl[IX(i + 1, j)]) - Math.abs(curl[IX(i - 1, j)])),
          gy = 0.5 * (Math.abs(curl[IX(i, j + 1)]) - Math.abs(curl[IX(i, j - 1)]));
        const len = Math.hypot(gx, gy) + 1e-5;
        const nx = gx / len,
          ny = gy / len,
          c = curl[IX(i, j)];
        u[IX(i, j)] += eps * ny * c;
        v[IX(i, j)] -= eps * nx * c;
      }
    }
    function advect(d, src, dt, decay) {
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        let x = i - dt * N * u[IX(i, j)],
          y = j - dt * N * v[IX(i, j)];
        x = Math.max(0.5, Math.min(N + 0.5, x));
        y = Math.max(0.5, Math.min(M + 0.5, y));
        const i0 = x | 0,
          j0 = y | 0,
          i1 = i0 + 1,
          j1 = j0 + 1,
          s1 = x - i0,
          s0 = 1 - s1,
          t1 = y - j0,
          t0 = 1 - t1;
        d[IX(i, j)] = decay * (s0 * (t0 * src[IX(i0, j0)] + t1 * src[IX(i0, j1)]) + s1 * (t0 * src[IX(i1, j0)] + t1 * src[IX(i1, j1)]));
      }
      bnd(d);
    }
    function diffuse(d, k) {
      if (k <= 0) return;
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        const q = IX(i, j);
        d[q] += k * ((d[q - 1] + d[q + 1] + d[q - S] + d[q + S]) * 0.25 - d[q]);
      }
      bnd(d);
    }
    /* ink is heavier than water and settles; the accent is lighter and floats */
    function buoy(dt) {
      if (!sink) return;
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        const q = IX(i, j);
        const a = d1[q],
          b = d2[q];
        v[q] += sink * dt * (a * a - 0.5 * b * b) * 0.0015;
      }
    }
    let last = null,
      auto_ = auto,
      alive = true,
      visible = true;
    const stir = (x, y, px, py, acc, amt = 0.12) => {
      const gi = Math.max(1, Math.min(N, Math.round(x * N))),
        gj = Math.max(1, Math.min(M, Math.round(y * M)));
      const RB = Math.max(3, Math.round(N * brush)),
        sg = RB * RB * 0.35;
      const cl = q => Math.max(-0.12, Math.min(0.12, q));
      const dx = cl((x - px) * strength * 4),
        dy = cl((y - py) * strength * 4);
      for (let a = -RB; a <= RB; a++) for (let b = -RB; b <= RB; b++) {
        const i = gi + a,
          j = gj + b;
        if (i < 1 || i > N || j < 1 || j > M) continue;
        const w = Math.exp(-(a * a + b * b) / sg);
        u[IX(i, j)] += dx * w;
        v[IX(i, j)] += dy * w;
        if (!amt) continue;
        const k = IX(i, j);
        if (acc) d2[k] = Math.min(1.4, d2[k] + amt * w);else d1[k] = Math.min(1.4, d1[k] + amt * w);
      }
    };
    /* a drop: soft gaussian cloud with a faint outward push */
    const drop = (x, y, r, acc, amt = 1) => {
      const gi = Math.round(x * N),
        gj = Math.round(y * M),
        R = Math.max(2, Math.round(r * Math.min(N, M)));
      const E = Math.ceil(R * 1.4);
      for (let a = -E; a <= E; a++) for (let b = -E; b <= E; b++) {
        const i = gi + a,
          j = gj + b;
        if (i < 1 || i > N || j < 1 || j > M) continue;
        const dist = Math.hypot(a, b),
          q = dist / R;
        const k = IX(i, j);
        if (q < 1.4) {
          const w = amt * Math.exp(-q * q * 2.2);
          if (acc) d2[k] = Math.min(1.4, d2[k] + w);else d1[k] = Math.min(1.4, d1[k] + w);
        }
        if (q < 1.6 && dist > 0.5) {
          const imp = 0.012 * strength * Math.exp(-(q - 0.9) * (q - 0.9) * 3);
          u[k] += imp * a / dist;
          v[k] += imp * b / dist;
        }
      }
    };
    const wash = () => {
      d1.fill(0);
      d2.fill(0);
      u.fill(0);
      v.fill(0);
    };
    api.current = {
      drop,
      wash,
      stir,
      setAuto: a => {
        auto_ = a;
      }
    };
    onReady && onReady(api.current);
    /* seed: accent floating high, ink settling low */
    for (let k = 0; k < 3; k++) drop(0.15 + 0.75 * Math.random(), 0.15 + 0.25 * Math.random(), 0.18 + 0.08 * Math.random(), true, 0.7);
    for (let k = 0; k < 4; k++) drop(0.1 + 0.8 * Math.random(), 0.6 + 0.3 * Math.random(), 0.2 + 0.1 * Math.random(), false, 0.9);
    const pos = e => {
      const r = c.getBoundingClientRect();
      return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height];
    };
    const down = e => {
      c.setPointerCapture(e.pointerId);
      last = pos(e);
      const [x, y] = last;
      drop(x, y, 0.1, e.shiftKey, 0.8);
    };
    let hv = null;
    const move = e => {
      const [x, y] = pos(e);
      if (last) {
        stir(x, y, last[0], last[1], e.shiftKey, 0.14);
        last = [x, y];
        return;
      }
      if (hover) {
        if (hv) stir(x, y, hv[0], hv[1], false, 0);
        hv = [x, y];
      }
    };
    const up = () => {
      last = null;
    };
    const out = () => {
      last = null;
      hv = null;
    };
    c.addEventListener("pointerdown", down);
    c.addEventListener("pointermove", move);
    c.addEventListener("pointerup", up);
    c.addEventListener("pointerleave", out);
    const io = "IntersectionObserver" in window ? new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
    }) : null;
    io && io.observe(c);
    let ax = 0.5,
      ay = 0.5,
      ph = 0,
      acc = 0,
      lastT = performance.now(),
      dropT = 0;
    const TICK = 1000 / 30;
    function step() {
      const dt = 0.5 * speed;
      if (auto_ && !last) {
        ph += 0.0015;
        const nx = 0.5 + 0.34 * Math.sin(ph * 1.3) + 0.08 * Math.sin(ph * 4.1),
          ny = 0.5 + 0.3 * Math.cos(ph * 0.9) + 0.08 * Math.cos(ph * 3.3);
        stir(nx, ny, ax, ay, false, 0);
        ax = nx;
        ay = ny;
        dropT += TICK / 1000;
        if (dropEvery > 0 && dropT > dropEvery) {
          dropT = 0;
          const acc_ = Math.random() < 0.4;
          drop(0.1 + 0.8 * Math.random(), acc_ ? 0.1 + 0.3 * Math.random() : 0.5 + 0.4 * Math.random(), 0.12 + 0.1 * Math.random(), acc_, 0.6);
        }
      }
      vorticity(curlStrength);
      buoy(dt);
      diffuse(u, 0.2);
      diffuse(v, 0.2);
      u0.set(u);
      v0.set(v);
      advect(u, u0, dt, viscosity);
      advect(v, v0, dt, viscosity);
      project();
      d0.set(d1);
      advect(d1, d0, dt, dissolve);
      diffuse(d1, spread);
      d0.set(d2);
      advect(d2, d0, dt, dissolve);
      diffuse(d2, spread);
    }
    /* density → colour: paper → ink → deep ink (3 stops); accent ramp paper → accent → dusky accent; blend by ink share */
    const mix = (o, c0, c1, t) => {
      px[o] = c0[0] + (c1[0] - c0[0]) * t;
      px[o + 1] = c0[1] + (c1[1] - c0[1]) * t;
      px[o + 2] = c0[2] + (c1[2] - c0[2]) * t;
    };
    let px;
    function paint() {
      px = img.data;
      const tmpI = [0, 0, 0],
        tmpA = [0, 0, 0];
      for (let j = 1; j <= M; j++) for (let i = 1; i <= N; i++) {
        const q = IX(i, j),
          a = Math.max(0, d1[q]),
          b = Math.max(0, d2[q]),
          g = 1 + gr[q];
        const tot = (a + b) * g;
        const t = 1 - Math.exp(-1.5 * tot);
        const tt = t < 0.2 ? 0 : (t - 0.2) / 0.8;
        const fi = tot > 0 ? a / (a + b) : 0;
        const o = ((j - 1) * N + (i - 1)) * 4;
        if (tt < 0.55) {
          const s = tt / 0.55;
          for (let k = 0; k < 3; k++) {
            tmpI[k] = B[k] + (I[k] - B[k]) * s;
            tmpA[k] = B[k] + (A[k] - B[k]) * Math.min(1, s * 0.85);
          }
        } else {
          const s = (tt - 0.55) / 0.45;
          for (let k = 0; k < 3; k++) {
            tmpI[k] = I[k] + (ID[k] - I[k]) * s;
            tmpA[k] = A[k] + (AD[k] - A[k]) * s;
          }
        }
        mix(o, tmpA, tmpI, fi);
        px[o + 3] = 255;
      }
      octx.putImageData(img, 0, 0);
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";
      if (soft > 0) ctx.filter = `blur(${(soft * c.width / N).toFixed(1)}px)`;
      ctx.drawImage(off, -2, -2, c.width + 4, c.height + 4);
      ctx.filter = "none";
    }
    for (let k = 0; k < warmup; k++) step();
    paint();
    function frame(now) {
      if (!alive) return;
      requestAnimationFrame(frame);
      const el = now - lastT;
      lastT = now;
      if (!visible) return;
      acc = Math.min(acc + el, TICK * 1.5);
      let did = false;
      if (acc >= TICK) {
        step();
        acc -= TICK;
        did = true;
      }
      if (did) paint();
    }
    requestAnimationFrame(frame);
    return () => {
      alive = false;
      io && io.disconnect();
      c.removeEventListener("pointerdown", down);
      c.removeEventListener("pointermove", move);
      c.removeEventListener("pointerup", up);
      c.removeEventListener("pointerleave", out);
    };
  }, [res, ink, accent, bg, speed, dissolve, spread, sink, viscosity, strength, curlStrength, grain, dropEvery, brush, hover, warmup, soft, width, height]);
  return /*#__PURE__*/React.createElement("canvas", {
    ref: cv,
    width: width,
    height: height,
    style: {
      display: "block",
      width,
      height,
      objectFit: "cover",
      cursor: "crosshair",
      touchAction: "none",
      ...style
    },
    "aria-label": "\u58A8\u6D41\u3057 \u2014 \u306A\u305E\u3063\u3066\u58A8\u3092\u6D41\u3059"
  });
}
Object.assign(__ds_scope, { Suminagashi });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/Suminagashi.jsx", error: String((e && e.message) || e) }); }

