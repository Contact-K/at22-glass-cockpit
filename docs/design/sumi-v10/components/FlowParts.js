// ui_kits/flow/FlowParts.jsx
try { (() => {
const {
  InkLoader
} = window.SumiDesignSystem_05bb6e;
const flowMono = (s = 11) => ({
  font: `400 ${s}px/1 var(--font-mono)`,
  letterSpacing: ".14em",
  textTransform: "uppercase"
});

/* 墨の四角のマスコット。本体は常にInkLoaderと同じ4×4の墨の四角(8×8格子の中央)。form で生き物の特徴だけ足す。
   削ぎ落とし方針: 付属物は1/4升の細線と小さな点だけ。ピンクは1か所まで。 frog 蛙(採用) / bird 鳥 / chick 雛 / crane 鶴 — 四角は胴。目は抜きだけ(瞳なし)、口・嘴・鼻は視線に追従 */
const MASCOT_FORMS = ["frog", "bird", "chick", "crane"];
function Mascot({
  pitch = 14,
  look = "c",
  color = "var(--fg)",
  form = "plain",
  busy,
  busyLabel,
  walk = false,
  pose,
  style
}) {
  const cv = React.useRef(null),
    L = React.useRef(look),
    SD = React.useRef(1),
    K = React.useRef(busy ? 0 : 1),
    BR = React.useRef(busy),
    W = React.useRef(walk),
    PO = React.useRef(pose);
  L.current = look;
  PO.current = pose;
  BR.current = busy;
  W.current = walk;
  const [mode, setMode] = React.useState(busy ? "loader" : "idle"),
    [ls, setLs] = React.useState(busy || "think");
  React.useEffect(() => {
    if (busy && mode === "idle") {
      setLs(busy);
      setMode(form === "crane" ? "retract" : "loader");
      if (form !== "crane") K.current = 0;
    }
  }, [busy, mode, form]);
  React.useEffect(() => {
    if (busy && (mode === "loader" || mode === "retract") && busy !== ls) setLs(busy);
  }, [busy, mode, ls]);
  React.useEffect(() => {
    if (mode !== "loader" || busy) return;
    const x = setTimeout(() => setMode(form === "crane" ? "extend" : "idle"), 3400);
    return () => clearTimeout(x);
  }, [mode, busy, form]);
  const onLoop = React.useCallback(() => {
    if (!BR.current) setMode(form === "crane" ? "extend" : "idle");
  }, [form]);
  React.useEffect(() => {
    if (mode === "loader") return;
    const c = cv.current;
    if (!c) return;
    const G = 8,
      dpr = Math.min(3, window.devicePixelRatio || 1),
      P = Math.max(2, Math.round(pitch * dpr)),
      S = G * P;
    c.width = S;
    c.height = S;
    const ctx = c.getContext("2d");
    const sp = document.createElement("span");
    sp.style.color = color;
    c.parentNode.appendChild(sp);
    const col = getComputedStyle(sp).color;
    sp.style.color = "var(--accent-pop)";
    const pink = getComputedStyle(sp).color;
    sp.remove();
    let t0 = performance.now(),
      raf,
      to;
    const O = {
        c: [0, 0],
        l: [-1, 0],
        r: [1, 0],
        u: [0, -1],
        d: [0, 1]
      },
      r = Math.round,
      h = P / 2,
      q = P / 4;
    let lastK = performance.now();
    const tick = now => {
      clearTimeout(to);
      const t = (now - t0) / 1000,
        st = Math.floor(t * 3);
      let blink = t % 3.7 < 0.12;
      let hop = t % 5.3 > 5.0 ? 1 : 0;
      if (mode === "retract" || mode === "extend") {
        if (now - lastK > 70) {
          lastK = now;
          K.current = Math.max(0, Math.min(1, K.current + (mode === "retract" ? -0.25 : 0.25)));
        }
        if (mode === "retract" && K.current <= 0) {
          setMode("loader");
          return;
        }
        if (mode === "extend" && K.current >= 1) {
          setMode("idle");
        }
      }
      const A = K.current;
      if (A < 0.5) blink = true;
      const [lx, ly] = O[L.current] || O.c;
      if (lx !== 0) SD.current = lx;
      const side = lx < 0 ? -1 : 1,
        face = SD.current;
      if (form === "frog") hop = t % 3.2 > 2.8 ? 1.25 : 0;
      let act = "idle",
        pd = false;
      if (form === "crane") {
        const T7 = t % 7.5,
          wk = W.current;
        act = PO.current ? PO.current : wk ? "walk" : T7 > 3 && T7 < 4.4 ? "peck" : T7 > 5.2 && T7 < 6.6 ? "preen" : T7 > 1.2 && T7 < 2.6 ? "one" : "idle";
        pd = act === "peck" && Math.floor(((PO.current ? t : T7) - 3) * 4) % 3 !== 2;
        hop = 0.75 * A - (pd ? 0.5 * A : act === "peck" ? 0.25 * A : 0) + (wk && Math.floor(t * 4) % 2 ? 0.25 * A : 0);
      }
      if (form === "chick") hop = [0, 0, 0, 0.25][st % 4];
      if (form === "catbody") hop = 0;
      ctx.clearRect(0, 0, S, S);
      const F = (x, y, w, hh, cc) => {
          ctx.fillStyle = cc || col;
          ctx.fillRect(r(x), r(y), Math.max(1, r(w)), Math.max(1, r(hh)));
        },
        X = (x, y, w, hh) => ctx.clearRect(r(x), r(y), Math.max(1, r(w)), Math.max(1, r(hh)));
      const ox = 2 * P,
        oy = (2 - hop) * P;
      F(ox, oy, 4 * P, 4 * P);
      let eyes = true,
        ex = [1.3, 2.7],
        ey = 1.5;
      const cl = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
      const hole = (cx, cy, e, bx0, by0, bx1, by1, d) => {
        const eh = blink ? Math.max(1, r(q / 2)) : e,
          x = cl(cx - e / 2 + lx * d, bx0, bx1 - e),
          y = cl(cy - eh / 2 + ly * d * 0.6, by0, by1 - eh);
        X(x, y, e, eh);
      };
      if (form === "frog") {
        eyes = false;
        const jump = t % 3.2 > 2.8,
          b1 = ox + q,
          b2 = ox + 3 * P - h,
          bw = P + q,
          e = r(P * 0.55);
        const BH = 1.25 * P,
          e2 = r(P * 0.6);
        for (const bx of [b1, b2]) {
          F(bx, oy - BH, bw, BH);
          X(bx === b1 ? bx : bx + bw - q, oy - BH, q, q);
          hole(bx + bw / 2, oy - BH * 0.5, e2, bx + q / 2, oy - BH + q, bx + bw - q / 2, oy - q / 2, q);
        }
        const puff = t % 4.6 > 4.2,
          mx = ox + P - q + lx * q,
          my = oy + P + ly * q * 0.5;
        F(mx, my, 2 * P + h, q, pink);
        if (puff) F(mx + q, my + q, 2 * P, h, pink);
        if (jump) {
          F(ox + q, oy + 4 * P, q, 1.5 * P);
          F(ox + 4 * P - h, oy + 4 * P, q, 1.5 * P);
          F(ox - q, oy + 4 * P + 1.5 * P - q, h, q);
          F(ox + 4 * P - q, oy + 4 * P + 1.5 * P - q, h, q);
        } else {
          F(ox - h, oy + 2.5 * P, h, 1.5 * P);
          F(ox - P, oy + 4 * P - q, P + h, q);
          F(ox + 4 * P, oy + 2.5 * P, h, 1.5 * P);
          F(ox + 4 * P - h, oy + 4 * P - q, P + h, q);
        }
        F(ox + P - q, oy + 4 * P, h, q);
        F(ox + 3 * P - q, oy + 4 * P, h, q);
      }
      if (form === "bird" || form === "chick" || form === "crane") {
        eyes = false;
        const front = form === "crane" ? face : lx === 0 ? 1 : side,
          fr = front > 0 ? ox + 4 * P : ox,
          bk = front > 0 ? ox : ox + 4 * P,
          e = r(P * 0.6),
          by = oy + P + q + ly * q;
        const fe = form === "crane" && act === "preen" ? -front : front,
          ecx = lx === 0 && form !== "crane" ? [ox + 1.3 * P, ox + 2.7 * P] : fe > 0 ? [ox + 2.4 * P, ox + 3.3 * P] : [ox + 0.7 * P, ox + 1.6 * P];
        if (!pd) for (const cx of ecx) hole(cx, oy + 1.3 * P, e, ox + q, oy + q, ox + 4 * P - q, oy + 2.5 * P, r(P * 0.35));
        if (form === "chick") {
          X(ox, oy, q, q);
          X(ox + 4 * P - q, oy, q, q);
          X(ox, oy + 4 * P - q, q, q);
          X(ox + 4 * P - q, oy + 4 * P - q, q, q);
          const sw = [0, q, 0, -q][Math.floor(t * 2) % 4];
          F(ox + 2 * P - q / 2, oy - h, q, h);
          F(ox + 2 * P - q / 2 + sw, oy - P, q, h);
          if (lx !== 0) F(front > 0 ? fr : fr - h, by, h, h, pink);else F(ox + 2 * P - q, oy + 2 * P, h, h, pink);
          F(ox + P + q, oy + 4 * P, q, h);
          F(ox + 2 * P + h, oy + 4 * P, q, h);
          F(ox + P, oy + 4 * P + h, P, q);
          F(ox + 2 * P + q, oy + 4 * P + h, P, q);
        } else if (form === "crane") {
          const fl = S - q,
            L = (fl - (oy + 4 * P)) * A,
            lg = ox + 2 * P - q / 2 + front * 0.6 * P,
            lg2 = ox + 2 * P - q / 2 - front * 0.6 * P,
            dir = front,
            toe = (x, y) => F(dir > 0 ? x : x - P * A + q, y, P * A, q);
          if (A > 0) {
            const wph = Math.floor(t * 4) % 2,
              leg = (x, off, lift) => {
                const xx = x + off * dir,
                  ll = L - lift;
                F(xx, oy + 4 * P, q, ll);
                toe(xx, oy + 4 * P + ll - q);
              };
            if (act === "walk") {
              leg(lg, wph ? q : -q, wph ? q : 0);
              leg(lg2, wph ? -q : q, wph ? 0 : q);
            } else if (act === "one") {
              leg(lg, 0, 0);
              const ky = oy + 4 * P + L * 0.45;
              F(dir > 0 ? lg2 : lg2 - h + q, oy + 4 * P, q, L * 0.45);
              F(dir > 0 ? lg2 : lg2 - h + q, ky, h + q, q);
            } else {
              leg(lg, 0, 0);
              leg(lg2, 0, 0);
            }
            const bw = P * A,
              bh = h;
            if (act === "peck") {
              if (pd) {
                const e2 = r(P * 0.6),
                  eyh = blink ? Math.max(1, r(q / 2)) : e2,
                  exs = dir > 0 ? [ox + 2.5 * P, ox + 3.3 * P] : [ox + 0.7 * P, ox + 1.5 * P];
                for (const xx of exs) X(xx - e2 / 2, oy + 2.7 * P, e2, eyh);
                const bx = dir > 0 ? ox + 4 * P : ox - h;
                F(bx, oy + 3.25 * P, h, h, pink);
                F(bx + dir * h, oy + 3.25 * P + h, h, h, pink);
                const tipx = bx + dir * h,
                  tipy = oy + 3.25 * P + P;
                const dot = Math.floor(t * 8) % 2;
                F(tipx + dir * q, fl - q, q, q);
                if (dot) F(tipx + dir * (h + q), fl - q, q, q);
              } else F(dir > 0 ? fr : fr - bw, by, bw, bh, pink);
            } else if (act === "preen") {
              const nb = Math.floor(t * 6) % 2 ? q : 0,
                bx = dir > 0 ? ox - bw * 0.6 + nb : ox + 4 * P - nb;
              F(bx, oy + 1.8 * P, bw * 0.6, bh, pink);
              X(dir > 0 ? ox : ox + 4 * P - q, oy + 2.3 * P, q, h);
            } else F(dir > 0 ? fr : fr - bw, by, bw, bh, pink);
            const tx = dir > 0 ? ox - h * A : ox + 4 * P;
            F(tx, oy + 2.5 * P, h * A, P + h);
            F(dir > 0 ? tx - q * A : tx + h * A, oy + 2.5 * P + h, q * A, h);
          }
        } else {
          if (lx !== 0) F(front > 0 ? fr : fr - P, by, P, h, pink);else F(ox + 2 * P - q, oy + 2 * P + q, h, h, pink);
          const flap = t % 3 > 2.6;
          F(bk + (front > 0 ? -h : 0), oy + (flap ? P : 2.5 * P), h, flap ? P + h : P);
          F(ox + P + q, oy + 4 * P, q, P + q);
          F(ox + 2 * P + h, oy + 4 * P, q, P + q);
          F(ox + P, oy + 5 * P + q, P, q);
          F(ox + 2 * P + q, oy + 5 * P + q, P, q);
        }
      }
      if (eyes) {
        const e = r(P * 0.6),
          d = r(P * 0.45),
          eh = blink ? Math.max(1, r(e * 0.25)) : e;
        const top = form === "frog" ? oy - P + q : oy + q,
          dy = ey < 1.2 ? d * 0.35 : d;
        for (const cx of ex) {
          X(ox + cx * P - e / 2 + lx * d, Math.max(top, oy + ey * P - eh / 2 + ly * dy), e, eh);
        }
      }
      raf = requestAnimationFrame(tick);
      to = setTimeout(() => {
        cancelAnimationFrame(raf);
        tick(performance.now());
      }, 100);
    };
    tick(t0);
    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(to);
    };
  }, [pitch, color, mode, form]);
  if (mode === "loader") return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-block",
      position: "relative",
      width: 8 * pitch,
      height: 8 * pitch,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      left: -pitch,
      top: -pitch
    }
  }, /*#__PURE__*/React.createElement(InkLoader, {
    status: ls,
    pitch: pitch,
    color: color,
    onLoop: onLoop
  })), busyLabel ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      bottom: -4,
      textAlign: "center",
      ...flowMono(10),
      color: "var(--fg-2)"
    }
  }, busyLabel) : null);
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-block",
      position: "relative",
      ...style
    }
  }, /*#__PURE__*/React.createElement("canvas", {
    ref: cv,
    style: {
      display: "block",
      width: 8 * pitch,
      height: 8 * pitch
    }
  }));
}

/* ページ遷移 — 唯一の「祝う」モーション。phase: idle → cover → hold → reveal → idle */
function FlowTransition({
  ritual,
  phase,
  origin,
  label
}) {
  if (ritual === "dots") return /*#__PURE__*/React.createElement(FlowDotCover, {
    phase: phase,
    origin: origin,
    label: label
  });
  const on = phase !== "idle",
    hold = phase === "hold";
  const loader = /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      opacity: hold ? 1 : 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 16,
      color: "#fff"
    }
  }, /*#__PURE__*/React.createElement(InkLoader, {
    status: "transfer",
    pitch: 9,
    color: "#fff"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      ...flowMono(11),
      color: "#fff"
    }
  }, label)));
  if (ritual === "scan") {
    const N = 12;
    return /*#__PURE__*/React.createElement("div", {
      "aria-hidden": "true",
      style: {
        position: "fixed",
        inset: 0,
        zIndex: 200,
        pointerEvents: on ? "auto" : "none"
      }
    }, Array.from({
      length: N
    }, (_, i) => {
      const d = phase === "reveal" ? i : i,
        show = phase === "cover" || phase === "hold";
      return /*#__PURE__*/React.createElement("div", {
        key: i,
        style: {
          position: "absolute",
          left: 0,
          right: 0,
          top: `${i * 100 / N}%`,
          height: `${100 / N + 0.2}%`,
          background: i % 4 === 3 ? "var(--accent-pop)" : "#1212EE",
          transformOrigin: phase === "reveal" ? "bottom" : "top",
          transform: `scaleY(${show ? 1 : 0})`,
          transition: phase === "idle" ? "none" : `transform 150ms steps(3) ${d * 24}ms`
        }
      });
    }), loader);
  }
  if (ritual === "sink") {
    const ox = origin?.x ?? window.innerWidth / 2,
      oy = origin?.y ?? window.innerHeight / 2,
      R = Math.hypot(Math.max(ox, window.innerWidth - ox), Math.max(oy, window.innerHeight - oy)) * 2.1,
      show = phase === "cover" || phase === "hold";
    return /*#__PURE__*/React.createElement("div", {
      "aria-hidden": "true",
      style: {
        position: "fixed",
        inset: 0,
        zIndex: 200,
        overflow: "hidden",
        pointerEvents: on ? "auto" : "none"
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        position: "absolute",
        left: ox,
        top: oy,
        width: R,
        height: R,
        marginLeft: -R / 2,
        marginTop: -R / 2,
        background: "#1212EE",
        transform: `scale(${show ? 1 : 0})`,
        transition: phase === "idle" ? "none" : "transform 380ms steps(7)"
      }
    }), /*#__PURE__*/React.createElement("div", {
      style: {
        position: "absolute",
        left: ox,
        top: oy,
        width: R * 0.5,
        height: R * 0.5,
        marginLeft: -R * 0.25,
        marginTop: -R * 0.25,
        border: "2px solid var(--accent-pop)",
        transform: `scale(${show ? 1.2 : 0})`,
        transition: phase === "idle" ? "none" : "transform 380ms steps(5) 40ms"
      }
    }), loader);
  }
  const x = phase === "cover" || phase === "hold" ? "-25vw" : phase === "reveal" ? "130vw" : "-190vw";
  return /*#__PURE__*/React.createElement("div", {
    "aria-hidden": "true",
    style: {
      position: "fixed",
      inset: 0,
      zIndex: 200,
      overflow: "hidden",
      pointerEvents: on ? "auto" : "none"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "-20vh",
      bottom: "-20vh",
      left: 0,
      width: "150vw",
      background: "#1212EE",
      transform: `translateX(${x}) skewX(-18deg)`,
      transition: phase === "idle" ? "none" : "transform 240ms steps(4)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: 0,
      bottom: 0,
      right: "-7vw",
      width: "4vw",
      background: "var(--accent-pop)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: 0,
      bottom: 0,
      right: "-10vw",
      width: "1vw",
      background: "#fff"
    }
  })), loader);
}
/* 遷移のドット — 波紋の先頭からピンク→白→青の三色。押した位置から波紋順にドットが育って画面を覆い(cover)、離れた順に縮んで次の画面を見せる(reveal)。24fps */
function FlowDotCover({
  phase,
  origin,
  label
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
      pc = 18,
      cols = Math.ceil(W / pc),
      rows = Math.ceil(H / pc),
      maxD = Math.max(Math.hypot(ox, oy), Math.hypot(W - ox, oy), Math.hypot(ox, H - oy), Math.hypot(W - ox, H - oy));
    const from = P.current,
      to = phase === "cover" || phase === "hold" ? 1 : 0,
      dur = phase === "cover" ? 250 : phase === "reveal" ? 300 : 0,
      t0 = performance.now();
    let raf, tm;
    const draw = now => {
      clearTimeout(tm);
      const q = dur ? Math.min(1, Math.floor((now - t0) / (1000 / 24)) * (1000 / 24) / dur) : 1,
        p = from + (to - from) * q;
      P.current = p;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      g.fillStyle = "#1212EE";
      if (p >= 1) g.fillRect(0, 0, W, H);else if (p > 0) {
        const cover = to === 1,
          P2 = p * 1.35;
        for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
          const d = Math.hypot((i + .5) * pc - ox, (j + .5) * pc - oy) / maxD,
            dd = cover ? d : 1 - d;
          const f = P2 - dd,
            s = Math.max(0, Math.min(1, f / 0.35));
          if (s <= 0) continue;
          const sz = Math.ceil(s * pc);
          g.fillStyle = f < 0.1 ? "#FF3DCC" : f < 0.2 ? "#FFFFFF" : "#1212EE";
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
      ...flowMono(11),
      color: "#fff"
    }
  }, label)));
}
/* 決定のドット — 押したボタン(from)がドットに崩れ、レールを渡って新しい行(to)に着地し、ドットが育って面になる。
   DotLoader の文法(格子・波紋順の点灯・ドット径の伸縮)を決定アクションに転用。飛んでいる間だけピンク=唯一の差し色。24fpsコマ送り */
function FlowCelebrate({
  fire,
  from,
  to
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
      Bq = to || {
        left: W / 2 - 200,
        top: H / 2 - 40,
        width: 400,
        height: 80
      };
    const pt = 8,
      cols = Math.max(4, Math.round(Bq.width / pt)),
      rows = Math.max(2, Math.round(Bq.height / pt)),
      cw = Bq.width / cols,
      ch = Bq.height / rows;
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
        tx: Bq.left + (i + .5) * cw,
        ty: Bq.top + (j + .5) * ch,
        d: Math.hypot(u - .5, v - .5) * 1.4,
        u,
        j: rnd() * 60
      });
    }
    const T = 1150,
      t0 = performance.now();
    let raf, tm;
    const draw = now => {
      clearTimeout(tm);
      const t = Math.floor((now - t0) / (1000 / 24)) * (1000 / 24);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      const fade = t > 950 ? Math.max(0, 1 - (t - 950) / 200) : 1;
      g.globalAlpha = fade;
      for (const o of D) {
        const lt = t - o.d * 160 - o.j;
        let x,
          y,
          r,
          col = "#FF3DCC";
        if (lt < 0) {
          continue;
        }
        if (lt < 220) {
          x = o.sx;
          y = o.sy;
          r = pt * 0.5 * Math.min(1, lt / 180);
        } else if (lt < 520) {
          const k = Math.ceil((lt - 220) / 300 * 5) / 5;
          x = o.sx + (o.tx - o.sx) * k;
          y = o.sy + (o.ty - o.sy) * k;
          r = pt * 0.5;
        } else {
          x = o.tx;
          y = o.ty;
          const k = Math.min(1, (lt - 520) / 200);
          r = pt * (0.5 + 0.5 * k) / 2 * 2;
          if (lt > 560 + o.u * 140) col = "#1212EE";
        }
        g.fillStyle = col;
        const s = Math.max(1, Math.min(cw, r));
        g.fillRect(Math.round(x - s / 2), Math.round(y - s / 2), Math.ceil(s), Math.ceil(s));
      }
      if (now - t0 < T + 200) {
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
Object.assign(window, {
  Mascot,
  MASCOT_FORMS,
  FlowTransition,
  FlowCelebrate,
  flowMono
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/flow/FlowParts.jsx", error: String((e && e.message) || e) }); }

