// components/ornaments/RegMark.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function RegMark({
  kind = "cross",
  size = 12,
  color = "currentColor",
  style
}) {
  const s = size,
    c = s / 2,
    st = {
      stroke: color,
      strokeWidth: 1,
      fill: "none",
      shapeRendering: "crispEdges"
    };
  const body = {
    cross: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("line", {
      x1: c,
      y1: "0",
      x2: c,
      y2: s
    }), /*#__PURE__*/React.createElement("line", {
      x1: "0",
      y1: c,
      x2: s,
      y2: c
    })),
    target: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("circle", {
      cx: c,
      cy: c,
      r: c * 0.55,
      shapeRendering: "auto"
    }), /*#__PURE__*/React.createElement("line", {
      x1: c,
      y1: "0",
      x2: c,
      y2: s
    }), /*#__PURE__*/React.createElement("line", {
      x1: "0",
      y1: c,
      x2: s,
      y2: c
    })),
    dot: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("circle", {
      cx: c,
      cy: c,
      r: c * 0.55,
      shapeRendering: "auto"
    }), /*#__PURE__*/React.createElement("circle", {
      cx: c,
      cy: c,
      r: "1",
      fill: color,
      stroke: "none"
    })),
    star: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("line", {
      x1: c,
      y1: "0",
      x2: c,
      y2: s
    }), /*#__PURE__*/React.createElement("line", {
      x1: "0",
      y1: c,
      x2: s,
      y2: c
    }), /*#__PURE__*/React.createElement("line", {
      x1: c * 0.3,
      y1: c * 0.3,
      x2: s - c * 0.3,
      y2: s - c * 0.3,
      shapeRendering: "auto"
    }), /*#__PURE__*/React.createElement("line", {
      x1: s - c * 0.3,
      y1: c * 0.3,
      x2: c * 0.3,
      y2: s - c * 0.3,
      shapeRendering: "auto"
    })),
    globe: /*#__PURE__*/React.createElement("g", _extends({}, st, {
      shapeRendering: "auto"
    }), /*#__PURE__*/React.createElement("circle", {
      cx: c,
      cy: c,
      r: c - 0.5
    }), /*#__PURE__*/React.createElement("ellipse", {
      cx: c,
      cy: c,
      rx: c * 0.45,
      ry: c - 0.5
    }), /*#__PURE__*/React.createElement("line", {
      x1: "0",
      y1: c,
      x2: s,
      y2: c
    })),
    tick: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("line", {
      x1: c,
      y1: "0",
      x2: c,
      y2: s
    }), /*#__PURE__*/React.createElement("line", {
      x1: c - 3,
      y1: "0.5",
      x2: c + 3,
      y2: "0.5"
    })),
    corner: /*#__PURE__*/React.createElement("g", st, /*#__PURE__*/React.createElement("polyline", {
      points: `0,${s} 0,0 ${s},0`
    }))
  };
  return /*#__PURE__*/React.createElement("svg", {
    width: s,
    height: s,
    viewBox: `0 0 ${s} ${s}`,
    style: {
      display: "inline-block",
      verticalAlign: "middle",
      overflow: "visible",
      ...style
    },
    "aria-hidden": "true"
  }, body[kind] || body.cross);
}
Object.assign(__ds_scope, { RegMark });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/ornaments/RegMark.jsx", error: String((e && e.message) || e) }); }

