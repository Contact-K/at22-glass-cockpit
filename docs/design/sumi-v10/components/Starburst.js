// components/acid/Starburst.jsx
try { (() => {
function Starburst({
  size = 40,
  points = 4,
  inner = 0.18,
  color = "currentColor",
  fill = false,
  spin = false,
  style
}) {
  const c = size / 2,
    R = c - 1,
    r = R * inner,
    n = points * 2,
    pts = Array.from({
      length: n
    }, (_, i) => {
      const a = i / n * Math.PI * 2 - Math.PI / 2,
        rad = i % 2 ? r : R;
      return (c + Math.cos(a) * rad).toFixed(2) + "," + (c + Math.sin(a) * rad).toFixed(2);
    }).join(" ");
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: `0 0 ${size} ${size}`,
    style: {
      display: "inline-block",
      verticalAlign: "middle",
      animation: spin ? "sumi-spin 12s linear infinite" : "none",
      ...style
    },
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("style", null, "@keyframes sumi-spin{to{transform:rotate(360deg)}}"), /*#__PURE__*/React.createElement("polygon", {
    points: pts,
    fill: fill ? color : "none",
    stroke: color,
    strokeWidth: "1",
    strokeLinejoin: "miter"
  }));
}
Object.assign(__ds_scope, { Starburst });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/Starburst.jsx", error: String((e && e.message) || e) }); }

