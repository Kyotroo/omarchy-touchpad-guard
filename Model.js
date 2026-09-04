.pragma library

function validMode(mode) {
  return mode === "normal" || mode === "safe" || mode === "off"
}

function nextMode(mode) {
  if (mode === "normal") return "safe"
  if (mode === "safe") return "off"
  return "normal"
}

function modeLabel(mode) {
  if (mode === "safe") return "Typing Safe"
  if (mode === "off") return "Off"
  return "Normal"
}

function modeIcon(mode, status) {
  if (!status || status.ok !== true) return "󰅚"
  if (!Array.isArray(status.devices) || status.devices.length === 0) return "󰌙"
  if (mode === "safe") return "󰒘"
  if (mode === "off") return "󰟾"
  return "󰟸"
}

function modeTooltip(status) {
  if (!status || status.ok !== true) {
    var detail = status && status.error ? String(status.error) : "Controller unavailable"
    return "Touchpad Guard error: " + detail
  }
  if (!Array.isArray(status.devices) || status.devices.length === 0)
    return "Touchpad Guard: No touchpad detected"
  return "Touchpad Guard: " + modeLabel(status.mode)
    + " — left-click to cycle, right-click for settings"
}

function settingEnabled(mode, key) {
  if (mode === "off") return false
  if (mode === "safe" && (key === "tapToClick" || key === "tapAndDrag"))
    return false
  return true
}

function clamp(value, low, high) {
  var number = Number(value)
  if (!isFinite(number)) number = low
  return Math.max(low, Math.min(high, number))
}

function roundTo(value, digits) {
  var scale = Math.pow(10, digits)
  return Math.round(value * scale) / scale
}

function sliderToValue(key, position) {
  var p = clamp(position, 0, 1)
  if (key === "sensitivity") return roundTo(-1 + p * 2, 2)
  if (key === "scrollFactor") return roundTo(p * 2, 2)
  return p
}

function valueToSlider(key, value) {
  if (key === "sensitivity") return clamp((Number(value) + 1) / 2, 0, 1)
  if (key === "scrollFactor") return clamp(Number(value) / 2, 0, 1)
  return clamp(value, 0, 1)
}

function defaultNormal() {
  return {
    sensitivity: 0,
    scrollFactor: 1,
    naturalScroll: false,
    tapToClick: true,
    tapAndDrag: true,
    clickfingerBehavior: false,
    tapButtonMap: "lrm",
    middleButtonEmulation: false,
    dragLock: 0,
    drag3fg: 0,
    disableWhileTyping: true,
    followMouse: 1
  }
}

function errorStatus(message) {
  return {
    schemaVersion: 1,
    ok: false,
    mode: "normal",
    devices: [],
    settings: { schemaVersion: 1, normal: defaultNormal(), protectKeyboardFocus: true },
    effective: defaultNormal(),
    warnings: [],
    error: message || "Invalid controller response"
  }
}

function finiteNumber(value) {
  return typeof value === "number" && isFinite(value)
}

function validNormal(normal) {
  return normal && typeof normal === "object"
    && finiteNumber(normal.sensitivity)
    && normal.sensitivity >= -1 && normal.sensitivity <= 1
    && finiteNumber(normal.scrollFactor)
    && normal.scrollFactor >= 0 && normal.scrollFactor <= 2
    && typeof normal.naturalScroll === "boolean"
    && typeof normal.tapToClick === "boolean"
    && typeof normal.tapAndDrag === "boolean"
    && typeof normal.clickfingerBehavior === "boolean"
    && (normal.tapButtonMap === "lrm" || normal.tapButtonMap === "lmr")
    && typeof normal.middleButtonEmulation === "boolean"
    && (normal.dragLock === 0 || normal.dragLock === 1 || normal.dragLock === 2)
    && (normal.drag3fg === 0 || normal.drag3fg === 1 || normal.drag3fg === 2)
    && typeof normal.disableWhileTyping === "boolean"
    && (normal.followMouse === 0 || normal.followMouse === 1
      || normal.followMouse === 2 || normal.followMouse === 3)
}

function copyNormal(normal) {
  return {
    sensitivity: normal.sensitivity,
    scrollFactor: normal.scrollFactor,
    naturalScroll: normal.naturalScroll,
    tapToClick: normal.tapToClick,
    tapAndDrag: normal.tapAndDrag,
    clickfingerBehavior: normal.clickfingerBehavior,
    tapButtonMap: normal.tapButtonMap,
    middleButtonEmulation: normal.middleButtonEmulation,
    dragLock: normal.dragLock,
    drag3fg: normal.drag3fg,
    disableWhileTyping: normal.disableWhileTyping,
    followMouse: normal.followMouse
  }
}

function normalizeStatus(raw) {
  var value
  try {
    value = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (error) {
    return errorStatus("Invalid controller response")
  }

  if (!value || typeof value !== "object" || value.schemaVersion !== 1)
    return errorStatus("Unsupported controller response")
  if (value.ok !== true) return errorStatus(String(value.error || "Controller command failed"))
  if (!validMode(value.mode) || !Array.isArray(value.devices))
    return errorStatus("Invalid controller state")
  if (!value.settings || value.settings.schemaVersion !== 1
      || !validNormal(value.settings.normal)
      || typeof value.settings.protectKeyboardFocus !== "boolean")
    return errorStatus("Invalid controller settings")

  var devices = []
  for (var i = 0; i < value.devices.length; i++) {
    if (typeof value.devices[i] !== "string") return errorStatus("Invalid touchpad list")
    devices.push(value.devices[i])
  }

  var warnings = []
  if (Array.isArray(value.warnings)) {
    for (var j = 0; j < value.warnings.length; j++)
      if (typeof value.warnings[j] === "string") warnings.push(value.warnings[j])
  }

  var effective = validNormal(value.effective)
    ? copyNormal(value.effective)
    : copyNormal(value.settings.normal)

  return {
    schemaVersion: 1,
    ok: true,
    mode: value.mode,
    devices: devices,
    settings: {
      schemaVersion: 1,
      normal: copyNormal(value.settings.normal),
      protectKeyboardFocus: value.settings.protectKeyboardFocus
    },
    effective: effective,
    warnings: warnings,
    error: ""
  }
}

function settingDefinitions() {
  return [
    {
      key: "sensitivity",
      group: "Pointer & scrolling",
      type: "slider",
      label: "Pointer sensitivity",
      description: "Adjust touchpad pointer speed without changing an external mouse.",
      minimum: -1,
      maximum: 1,
      step: 0.05
    },
    {
      key: "scrollFactor",
      group: "Pointer & scrolling",
      type: "slider",
      label: "Scroll speed",
      description: "Scale two-finger scrolling from stopped to twice the normal distance.",
      minimum: 0,
      maximum: 2,
      step: 0.05
    },
    {
      key: "naturalScroll",
      group: "Pointer & scrolling",
      type: "toggle",
      label: "Natural scrolling",
      description: "Move content in the same direction as your fingers."
    },
    {
      key: "tapToClick",
      group: "Clicking & dragging",
      type: "toggle",
      label: "Tap to click",
      description: "Turn one-, two-, and three-finger taps into mouse buttons."
    },
    {
      key: "tapAndDrag",
      group: "Clicking & dragging",
      type: "toggle",
      label: "Tap and drag",
      description: "Start a drag by tapping and then moving a finger."
    },
    {
      key: "clickfingerBehavior",
      group: "Clicking & dragging",
      type: "toggle",
      label: "Clickfinger buttons",
      description: "Map physical presses with one, two, or three fingers to left, right, and middle click."
    },
    {
      key: "tapButtonMap",
      group: "Clicking & dragging",
      type: "enum",
      label: "Tap button order",
      description: "Choose whether two-finger tap is right or middle click.",
      options: [
        { value: "lrm", label: "Left · Right · Middle" },
        { value: "lmr", label: "Left · Middle · Right" }
      ]
    },
    {
      key: "middleButtonEmulation",
      group: "Clicking & dragging",
      type: "toggle",
      label: "Middle-button emulation",
      description: "Treat simultaneous left and right presses as a middle click."
    },
    {
      key: "dragLock",
      group: "Clicking & dragging",
      type: "enum",
      label: "Drag lock",
      description: "Keep a tap-drag active briefly or until another tap.",
      options: [
        { value: "0", label: "Off" },
        { value: "1", label: "Locked" },
        { value: "2", label: "Sticky" }
      ]
    },
    {
      key: "drag3fg",
      group: "Clicking & dragging",
      type: "enum",
      label: "Multi-finger drag",
      description: "Reserve three or four fingers for physical dragging.",
      options: [
        { value: "0", label: "Off" },
        { value: "1", label: "3 finger" },
        { value: "2", label: "4 finger" }
      ]
    },
    {
      key: "disableWhileTyping",
      group: "Typing",
      type: "toggle",
      label: "Hyprland disable while typing",
      description: "Use Hyprland's native suppression; effectiveness depends on the input stack."
    },
    {
      key: "protectKeyboardFocus",
      group: "Typing",
      type: "toggle",
      label: "Protect keyboard focus in Typing Safe",
      description: "Stop pointer motion changing focus in Safe mode. This also affects external mice."
    }
  ]
}

function settingValue(status, key) {
  if (!status || !status.settings) return undefined
  if (key === "protectKeyboardFocus") return status.settings.protectKeyboardFocus
  var normal = status.settings.normal
  if (!normal || normal[key] === undefined) return undefined
  return normal[key]
}

function coerceSetting(key, value) {
  if (key === "sensitivity") return clamp(value, -1, 1)
  if (key === "scrollFactor") return clamp(value, 0, 2)
  if (key === "dragLock" || key === "drag3fg") {
    var integer = Math.round(Number(value))
    return integer === 1 || integer === 2 ? integer : 0
  }
  if (key === "naturalScroll" || key === "tapToClick" || key === "tapAndDrag"
      || key === "clickfingerBehavior" || key === "middleButtonEmulation"
      || key === "disableWhileTyping" || key === "protectKeyboardFocus")
    return value === true || String(value) === "true"
  if (key === "tapButtonMap") return value === "lmr" ? "lmr" : "lrm"
  return value
}

function formatSetting(key, value) {
  if (key === "sensitivity") return clamp(value, -1, 1).toFixed(2)
  if (key === "scrollFactor") return clamp(value, 0, 2).toFixed(2) + "×"
  return String(value)
}
