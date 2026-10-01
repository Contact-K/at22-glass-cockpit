// components/acid/DotDecide.jsx
try { (() => {
/* DotDecide — 決定のドット。from(押したボタン)がドット格子に崩れ、5コマで to(新しい行)へ渡り、着地後に育って面になる。
   飛行中だけピンク、着地で左から青へ。24fpsコマ送り。fire を増やすたびに1回再生。 */
function DotDecide({
  fire,
  from,
  to,
  pitch = 8,
  ink = "#1212EE",
  accent = "#FF3DCC",
  duration = 1150
}) {
  const cv = React.useRef(null),
    [on, setOn] = React.useState(0);
  React.useEffect(() => {
    if (fire) setOn(fire);
  }, [fire]);
  React.useEffect(() => {
    if (!on) return;
    const c = cv.current;
    if (!c) return;
    const W = window.innerWidth,
      H = window.innerHeight,
      dpr = Math.min(2, window.devicePixelRatio || 1);
    c.width = W * dpr;
    c.height = H * dpr;
    const g = c.getContext("2d");
    const A = from || {
        left: 28,
        top: H - 124,
        width: 96,
        height: 96
      },
      B = to || {
        left: W / 2 - 200,
        top: H / 2 - 40,
        width: 400,
        height: 80
      };
    const pt = pitch,
      cols = Math.max(4, Math.round(B.width / pt)),
      rows = Math.max(2, Math.round(B.height / pt)),
      cw = B.width / cols,
      ch = B.height / rows;
    let seed = 7;
    const rnd = () => {
      seed = seed * 16807 % 2147483647;
      return seed / 2147483647;
    };
    const D = [];
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
      const u = (i + .5) / cols,
        v = (j + .5) / rows;
      D.push({
        sx: A.left + u * A.width,
        sy: A.top + v * A.height,
        tx: B.left + (i + .5) * cw,
        ty: B.top + (j + .5) * ch,
        d: Math.hypot(u - .5, v - .5) * 1.4,
        u,
        j: rnd() * 60
      });
    }
    const k1 = duration * 0.19,
      k2 = duration * 0.45,
      fadeAt = duration * 0.83,
      t0 = performance.now();
    let raf, tm;
    const draw = now => {
      clearTimeout(tm);
      const t = Math.floor((now - t0) / (1000 / 24)) * (1000 / 24);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      g.globalAlpha = t > fadeAt ? Math.max(0, 1 - (t - fadeAt) / 200) : 1;
      for (const o of D) {
        const lt = t - o.d * 160 - o.j;
        if (lt < 0) continue;
        let x,
          y,
          r,
          col = accent;
        if (lt < k1) {
          x = o.sx;
          y = o.sy;
          r = pt * 0.5 * Math.min(1, lt / (k1 * 0.8));
        } else if (lt < k2) {
          const k = Math.ceil((lt - k1) / (k2 - k1) * 5) / 5;
          x = o.sx + (o.tx - o.sx) * k;
          y = o.sy + (o.ty - o.sy) * k;
          r = pt * 0.5;
        } else {
          x = o.tx;
          y = o.ty;
          r = pt * (0.5 + 0.5 * Math.min(1, (lt - k2) / 200));
          if (lt > k2 + 40 + o.u * 140) col = ink;
        }
        g.fillStyle = col;
        const s = Math.max(1, Math.min(cw, r));
        g.fillRect(Math.round(x - s / 2), Math.round(y - s / 2), Math.ceil(s), Math.ceil(s));
      }
      if (now - t0 < duration + 200) {
        raf = requestAnimationFrame(draw);
        tm = setTimeout(() => {
          cancelAnimationFrame(raf);
          draw(performance.now());
        }, 50);
      } else setOn(0);
    };
    draw(t0);
    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(tm);
    };
  }, [on]);
  return on ? /*#__PURE__*/React.createElement("canvas", {
    key: on,
    ref: cv,
    "aria-hidden": "true",
    style: {
      position: "fixed",
      inset: 0,
      width: "100%",
      height: "100%",
      zIndex: 220,
      pointerEvents: "none"
    }
  }) : null;
}
Object.assign(__ds_scope, { DotDecide });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/DotDecide.jsx", error: String((e && e.message) || e) }); }

