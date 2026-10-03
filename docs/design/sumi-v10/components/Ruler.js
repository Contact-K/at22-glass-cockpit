// components/ornaments/Ruler.jsx
try { (() => {
function Ruler({
  orientation = "horizontal",
  length = "100%",
  step = 8,
  major = 5,
  thickness = 10,
  color = "currentColor",
  numbers = false,
  style
}) {
  const h = orientation === "horizontal",
    deg = h ? "90deg" : "0deg";
  const minor = `repeating-linear-gradient(${deg},${color} 0 1px,transparent 1px ${step}px)`;
  const maj = `repeating-linear-gradient(${deg},${color} 0 1px,transparent 1px ${step * major}px)`;
  const box = h ? {
    width: length,
    height: thickness
  } : {
    width: thickness,
    height: length
  };
  const minorSize = h ? `100% ${thickness * 0.5}px` : `${thickness * 0.5}px 100%`;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      ...box,
      ...style
    },
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      backgroundImage: `${maj},${minor}`,
      backgroundSize: `100% 100%,${minorSize}`,
      backgroundRepeat: "repeat,repeat",
      backgroundPosition: h ? "0 0,left bottom" : "0 0,right top",
      opacity: .9
    }
  }), numbers && h && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      top: thickness + 2,
      display: "flex",
      justifyContent: "space-between",
      font: "400 9px/1 var(--font-mono)",
      color,
      opacity: .7
    }
  }, Array.from({
    length: 6
  }, (_, i) => /*#__PURE__*/React.createElement("span", {
    key: i
  }, String(i * 20).padStart(3, "0")))));
}
Object.assign(__ds_scope, { Ruler });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/ornaments/Ruler.jsx", error: String((e && e.message) || e) }); }

