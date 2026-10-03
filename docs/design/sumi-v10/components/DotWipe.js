// components/acid/DotWipe.jsx
try { (() => {
/* DotWipe — 遷移のドット。origin から波紋順にドットが育って画面を覆い(cover/hold)、離れた順に縮んで次を見せる(reveal)。
   波紋の先頭からピンク→白→青の三色。phase: idle → cover → hold → reveal → idle。 */
function DotWipe({
  phase = "idle",
  origin,
  label,
  pitch = 18,
  colors = ["#FF3DCC", "#FFFFFF", "#1212EE"],
  coverMs = 250,
  revealMs = 300
}) {
  const cv = React.useRef(null),
    P = React.useRef(0);
  React.useEffect(() => {
    const c = cv.current;
    if (!c) return;
    const W = window.innerWidth,
      H = window.innerHeight,
      dpr = Math.min(1.5, window.devicePixelRatio || 1);
    if (c.width !== Math.round(W * dpr)) {
      c.width = Math.round(W * dpr);
      c.height = Math.round(H * dpr);
    }
    const g = c.getContext("2d");
    const ox = origin?.x ?? W * 0.5,
      oy = origin?.y ?? H * 0.5,
      pc = pitch,
      cols = Math.ceil(W / pc),
      rows = Math.ceil(H / pc),
      maxD = Math.max(Math.hypot(ox, oy), Math.hypot(W - ox, oy), Math.hypot(ox, H - oy), Math.hypot(W - ox, H - oy));
    const from = P.current,
      to = phase === "cover" || phase === "hold" ? 1 : 0,
      dur = phase === "cover" ? coverMs : phase === "reveal" ? revealMs : 0,
      t0 = performance.now();
    let raf, tm;
    const draw = now => {
      clearTimeout(tm);
      const q = dur ? Math.min(1, Math.floor((now - t0) / (1000 / 24)) * (1000 / 24) / dur) : 1,
        p = from + (to - from) * q;
      P.current = p;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      g.fillStyle = colors[2];
      if (p >= 1) g.fillRect(0, 0, W, H);else if (p > 0) {
        const cover = to === 1,
          P2 = p * 1.35;
        for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
          const d = Math.hypot((i + .5) * pc - ox, (j + .5) * pc - oy) / maxD,
            dd = cover ? d : 1 - d,
            f = P2 - dd,
            s = Math.max(0, Math.min(1, f / 0.35));
          if (s <= 0) continue;
          const sz = Math.ceil(s * pc);
          g.fillStyle = f < 0.1 ? colors[0] : f < 0.2 ? colors[1] : colors[2];
          g.fillRect(i * pc + (pc - sz >> 1), j * pc + (pc - sz >> 1), sz, sz);
        }
      }
      if (q < 1) {
        raf = requestAnimationFrame(draw);
        tm = setTimeout(() => {
          cancelAnimationFrame(raf);
          draw(performance.now());
        }, 50);
      }
    };
    draw(t0);
    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(tm);
    };
  }, [phase]);
  return /*#__PURE__*/React.createElement("div", {
    "aria-hidden": "true",
    style: {
      position: "fixed",
      inset: 0,
      zIndex: 200,
      pointerEvents: phase !== "idle" ? "auto" : "none"
    }
  }, /*#__PURE__*/React.createElement("canvas", {
    ref: cv,
    style: {
      position: "absolute",
      inset: 0,
      width: "100%",
      height: "100%"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      opacity: phase === "hold" ? 1 : 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: "400 11px/1 var(--font-mono)",
      letterSpacing: ".14em",
      textTransform: "uppercase",
      color: "#fff"
    }
  }, label)));
}
Object.assign(__ds_scope, { DotWipe });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/DotWipe.jsx", error: String((e && e.message) || e) }); }

