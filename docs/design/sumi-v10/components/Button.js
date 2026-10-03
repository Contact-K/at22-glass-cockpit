// components/core/Button.jsx
try { (() => {
function Button({
  variant = "primary",
  size = "md",
  disabled = false,
  children,
  onClick,
  style
}) {
  const pad = size === "sm" ? "7px 14px" : size === "lg" ? "13px 26px" : "10px 20px";
  const fs = size === "sm" ? 11 : size === "lg" ? 14 : 12;
  const [hov, setHov] = React.useState(false),
    [act, setAct] = React.useState(false);
  const kinds = {
    primary: {
      background: hov && !disabled ? "var(--accent-hover)" : "var(--accent)",
      color: "var(--accent-ink)",
      border: "1px solid var(--accent)"
    },
    secondary: {
      background: hov && !disabled ? "var(--fg)" : "transparent",
      color: hov && !disabled ? "var(--bg)" : "var(--fg)",
      border: "1px solid var(--fg)"
    },
    ghost: {
      background: hov && !disabled ? "var(--bg-3)" : "transparent",
      color: "var(--fg-2)",
      border: "1px solid transparent"
    },
    danger: {
      background: hov && !disabled ? "var(--status-danger)" : "var(--status-danger)",
      color: "var(--bg)",
      border: "1px solid var(--status-danger)"
    }
  };
  return /*#__PURE__*/React.createElement("button", {
    onClick: disabled ? undefined : onClick,
    onMouseEnter: () => setHov(true),
    onMouseLeave: () => {
      setHov(false);
      setAct(false);
    },
    onMouseDown: () => setAct(true),
    onMouseUp: () => setAct(false),
    style: {
      font: `400 ${fs}px/1 var(--font-mono)`,
      textTransform: "uppercase",
      letterSpacing: ".08em",
      padding: pad,
      borderRadius: 0,
      cursor: disabled ? "default" : "pointer",
      opacity: disabled ? .4 : 1,
      display: "inline-flex",
      alignItems: "center",
      gap: 8,
      transform: act ? "translate(1px,1px)" : "none",
      transition: "background var(--dur-fast) var(--ease-smooth)",
      ...(kinds[variant] || kinds.primary),
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

