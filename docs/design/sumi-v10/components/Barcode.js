// components/acid/Barcode.jsx
try { (() => {
function Barcode({
  value = "SUMI-2026-0906",
  width = 160,
  height = 40,
  color = "currentColor",
  label = true,
  style
}) {
  let s = 0;
  for (const ch of value) s = s * 31 + ch.charCodeAt(0) >>> 0;
  const bars = [];
  let x = 0,
    k = 0;
  while (x < width) {
    s = s * 1103515245 + 12345 >>> 0;
    const w = 1 + (s >> 16) % 3,
      gap = 1 + (s >> 8) % 2;
    bars.push(/*#__PURE__*/React.createElement("rect", {
      key: k++,
      x: x,
      y: 0,
      width: w,
      height: height,
      fill: color
    }));
    x += w + gap;
  }
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      flexDirection: "column",
      gap: 4,
      alignItems: "stretch",
      ...style
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: width,
    height: height,
    viewBox: `0 0 ${width} ${height}`,
    "aria-hidden": "true",
    style: {
      display: "block"
    }
  }, bars), label && /*#__PURE__*/React.createElement("span", {
    style: {
      font: "400 9px/1 var(--font-mono)",
      letterSpacing: ".18em",
      color,
      textAlign: "center"
    }
  }, value));
}
Object.assign(__ds_scope, { Barcode });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/acid/Barcode.jsx", error: String((e && e.message) || e) }); }

