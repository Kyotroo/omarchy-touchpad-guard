import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "Model.js" })

let tests = 0
function test(name, fn) {
  tests += 1
  try {
    fn()
    console.log(`ok ${tests} - ${name}`)
  } catch (error) {
    console.error(`not ok ${tests} - ${name}`)
    throw error
  }
}

const completeStatus = JSON.stringify({
  schemaVersion: 1,
  ok: true,
  mode: "safe",
  devices: ["test-touchpad"],
  settings: {
    schemaVersion: 1,
    normal: {
      sensitivity: 0,
      scrollFactor: 0.4,
      naturalScroll: false,
      tapToClick: true,
      tapAndDrag: true,
      clickfingerBehavior: true,
      tapButtonMap: "lrm",
      middleButtonEmulation: false,
      dragLock: 0,
      drag3fg: 0,
      disableWhileTyping: true,
      followMouse: 1
    },
    protectKeyboardFocus: true
  },
  effective: { tapToClick: false, tapAndDrag: false, followMouse: 0 },
  warnings: [],
  error: ""
})

test("mode ring wraps in the designed order", () => {
  assert.equal(model.nextMode("normal"), "safe")
  assert.equal(model.nextMode("safe"), "off")
  assert.equal(model.nextMode("off"), "normal")
  assert.equal(model.nextMode("invalid"), "normal")
})

test("mode labels are readable", () => {
  assert.equal(model.modeLabel("normal"), "Normal")
  assert.equal(model.modeLabel("safe"), "Typing Safe")
  assert.equal(model.modeLabel("off"), "Off")
})

test("icons distinguish all operating and failure states", () => {
  const status = JSON.parse(completeStatus)
  const icons = [
    model.modeIcon("normal", status),
    model.modeIcon("safe", status),
    model.modeIcon("off", status),
    model.modeIcon("normal", { ...status, devices: [] }),
    model.modeIcon("normal", { ...status, ok: false })
  ]
  assert.equal(icons.every(icon => typeof icon === "string" && icon.length > 0), true)
  assert.equal(new Set(icons).size, icons.length)
})

test("tooltips describe state without relying on the icon", () => {
  const status = JSON.parse(completeStatus)
  assert.match(model.modeTooltip(status), /Typing Safe/)
  assert.match(model.modeTooltip({ ...status, devices: [] }), /No touchpad detected/)
  assert.match(model.modeTooltip({ ...status, ok: false, error: "controller stopped" }), /controller stopped/)
})

test("safe locks only tap and tap-drag while off locks all settings", () => {
  assert.equal(model.settingEnabled("safe", "tapToClick"), false)
  assert.equal(model.settingEnabled("safe", "tapAndDrag"), false)
  assert.equal(model.settingEnabled("safe", "scrollFactor"), true)
  assert.equal(model.settingEnabled("safe", "protectKeyboardFocus"), true)
  assert.equal(model.settingEnabled("off", "scrollFactor"), false)
  assert.equal(model.settingEnabled("normal", "tapToClick"), true)
})

test("slider mappings clamp and round-trip their documented ranges", () => {
  assert.equal(model.sliderToValue("scrollFactor", 1), 2)
  assert.equal(model.sliderToValue("scrollFactor", -1), 0)
  assert.equal(model.valueToSlider("sensitivity", 0), 0.5)
  assert.equal(model.valueToSlider("sensitivity", 5), 1)
  assert.equal(model.sliderToValue("sensitivity", 0), -1)
})

test("valid controller status is normalized without extra properties", () => {
  const status = model.normalizeStatus(completeStatus)
  assert.equal(status.ok, true)
  assert.equal(status.mode, "safe")
  assert.deepEqual(Array.from(status.devices), ["test-touchpad"])
  assert.equal(status.settings.normal.scrollFactor, 0.4)
  assert.equal(status.settings.protectKeyboardFocus, true)
  assert.equal(status.injected, undefined)
})

test("malformed status becomes a safe error state", () => {
  const outOfRange = JSON.parse(completeStatus)
  outOfRange.settings.normal.sensitivity = 99
  const invalidFollowMouse = JSON.parse(completeStatus)
  invalidFollowMouse.settings.normal.followMouse = 4
  const invalids = [
    "not-json",
    "{}",
    JSON.stringify({ ...JSON.parse(completeStatus), schemaVersion: 2 }),
    JSON.stringify({ ...JSON.parse(completeStatus), mode: "danger" }),
    JSON.stringify({ ...JSON.parse(completeStatus), devices: "touchpad" }),
    JSON.stringify({ ...JSON.parse(completeStatus), settings: { normal: "bad" } }),
    JSON.stringify(outOfRange),
    JSON.stringify(invalidFollowMouse)
  ]
  for (const raw of invalids) {
    const status = model.normalizeStatus(raw)
    assert.equal(status.ok, false)
    assert.equal(status.mode, "normal")
    assert.deepEqual(Array.from(status.devices), [])
    assert.equal(typeof status.error, "string")
    assert.notEqual(status.error, "")
  }
})

test("advanced setting definitions expose every controller setting once", () => {
  const definitions = Array.from(model.settingDefinitions())
  const keys = definitions.map(item => item.key)
  assert.deepEqual(keys, [
    "sensitivity",
    "scrollFactor",
    "naturalScroll",
    "tapToClick",
    "tapAndDrag",
    "clickfingerBehavior",
    "tapButtonMap",
    "middleButtonEmulation",
    "dragLock",
    "drag3fg",
    "disableWhileTyping",
    "protectKeyboardFocus"
  ])
  assert.equal(new Set(keys).size, keys.length)
  assert.deepEqual(Array.from(new Set(definitions.map(item => item.group))), [
    "Pointer & scrolling",
    "Clicking & dragging",
    "Typing"
  ])
  for (const definition of definitions) {
    assert.equal(typeof definition.label, "string")
    assert.notEqual(definition.label, "")
    assert.equal(typeof definition.description, "string")
    assert.notEqual(definition.description, "")
    assert.match(definition.type, /^(slider|toggle|enum)$/)
  }
})

test("advanced setting definitions carry usable bounds and options", () => {
  const definitions = Array.from(model.settingDefinitions())
  const sensitivity = definitions.find(item => item.key === "sensitivity")
  const scroll = definitions.find(item => item.key === "scrollFactor")
  const tapMap = definitions.find(item => item.key === "tapButtonMap")
  const drag = definitions.find(item => item.key === "dragLock")
  assert.deepEqual({ min: sensitivity.minimum, max: sensitivity.maximum, step: sensitivity.step }, { min: -1, max: 1, step: 0.05 })
  assert.deepEqual({ min: scroll.minimum, max: scroll.maximum, step: scroll.step }, { min: 0, max: 2, step: 0.05 })
  assert.deepEqual(Array.from(tapMap.options, item => item.value), ["lrm", "lmr"])
  assert.deepEqual(Array.from(drag.options, item => item.value), ["0", "1", "2"])
})

test("formatting and coercion produce controller-ready values", () => {
  assert.equal(model.formatSetting("sensitivity", -0.25), "-0.25")
  assert.equal(model.formatSetting("scrollFactor", 0.4), "0.40×")
  assert.equal(model.coerceSetting("dragLock", "2"), 2)
  assert.equal(model.coerceSetting("naturalScroll", "true"), true)
  assert.equal(model.coerceSetting("tapButtonMap", "lmr"), "lmr")
})

test("setting values come from persistent Normal preferences", () => {
  const status = model.normalizeStatus(completeStatus)
  assert.equal(model.settingValue(status, "tapToClick"), true)
  assert.equal(model.settingValue(status, "protectKeyboardFocus"), true)
  assert.equal(model.settingValue(status, "missing"), undefined)
})

console.log(`1..${tests}`)
