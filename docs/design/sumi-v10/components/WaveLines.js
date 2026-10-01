// components/acid/WaveLines.jsx
try { (() => {
function WaveLines({
  width = 320,
  height = 120,
  lines = 9,
  amp = 10,
  freq = 1.5,
  phase = 0,
  color = "currentColor",
  animate = false,
  style
}) {
  const [p, setP] = React.useState(phase);
  React.useEffect(() => {
    if (!animate) return;
    let r;
    const f = t => {
      setP(phase + t / 600);
      r = requestAnimationFrame(f);
    };
    r = requestAnimationFrame(f);
    return () => cancelAnimationFrame(r);
  }, [animate, phase]);
  const paths = Array.from({
    length: lines
  }, (_, i) => {
    const y0 = (i + 0.5) * (height / lines);
    let d = "";
    for (let k = 0; k <= 48; k++) {
      const x = k / 48 * width,
        y = y0 + Math.sin(k / 48 * Math.PI * 2 * freq + p + i * 0.35) * amp;
      d += (k ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1) + " ";
    }
    return /*#__PURE__*/React.createElement("path", {
      key: i,
      d: d,
      stroke: color,
      strokeWidth: "1",
      fill: "none"
    });
  });
  return /*#__PURE__*/React.createElement("svg", {
    width: width,
    height: height,
    viewBox: `0 0 ${width} ${height}`,
    style: {
      display: "block",
      ...style
    },
    "aria-hidden": "true"
  }, paths);
}
Object.assign(__ds_scope, { WaveLines });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/WaveLines.jsx", error: String((e && e.message) || e) }); }

