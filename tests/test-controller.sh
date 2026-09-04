#!/bin/bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CONTROLLER="$ROOT/bin/touchpad-guard"
FIXTURES="$ROOT/tests/fixtures/bin"
failures=0
tests=0
group=${1:-all}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  return 1
}

assert_json() {
  local json=$1 filter=$2 message=$3
  jq -e "$filter" <<<"$json" >/dev/null || fail "$message"
}

setup_case() {
  CASE_DIR=$(mktemp -d)
  export CASE_DIR
  export TOUCHPAD_GUARD_STATE_DIR="$CASE_DIR/state"
  export HYPRLAND_INSTANCE_SIGNATURE="session-a"
  export FAKE_HYPR_LOG="$CASE_DIR/hypr.log"
  export FAKE_TOGGLE_LOG="$CASE_DIR/toggle.log"
  export FAKE_OSD_LOG="$CASE_DIR/osd.log"
  export TOUCHPAD_GUARD_TOGGLE_MARKER="$CASE_DIR/touchpad-disabled-name"
  export PATH="$FIXTURES:/usr/bin:/bin"
  : >"$FAKE_HYPR_LOG"
  : >"$FAKE_TOGGLE_LOG"
  : >"$FAKE_OSD_LOG"
  unset FAKE_HYPR_FAIL FAKE_HYPR_DEVICES_JSON FAKE_HYPR_FAIL_EVAL_MATCH FAKE_HYPR_DELAY FAKE_TOGGLE_FAIL
}

teardown_case() {
  rm -rf -- "$CASE_DIR"
}

run_test() {
  local name=$1 fn=$2
  tests=$((tests + 1))
  setup_case
  if "$fn"; then
    printf 'ok %d - %s\n' "$tests" "$name"
  else
    failures=$((failures + 1))
    printf 'not ok %d - %s\n' "$tests" "$name" >&2
  fi
  teardown_case
}

test_status_reports_imported_defaults() {
  local result
  result=$($CONTROLLER status) || return 1
  assert_json "$result" '.schemaVersion == 1 and .ok == true and .mode == "normal"' "status envelope is invalid" || return 1
  assert_json "$result" '.devices == ["test-touchpad"]' "touchpad discovery is wrong" || return 1
  assert_json "$result" '.settings.protectKeyboardFocus == true' "focus protection default is wrong"
}

test_initialize_persists_imported_settings() {
  $CONTROLLER initialize >/dev/null || return 1
  jq -e '.schemaVersion == 1 and .mode == "normal" and .hyprlandSignature == "session-a"' "$TOUCHPAD_GUARD_STATE_DIR/session.json" >/dev/null || return 1
  jq -e '.schemaVersion == 1 and .normal.tapToClick == true and .normal.scrollFactor == 0.4 and .protectKeyboardFocus == true' "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >/dev/null
}

test_no_device_is_supported() {
  export FAKE_HYPR_DEVICES_JSON='{"mice":[{"address":"0x2","name":"desk-mouse","defaultSpeed":0.1,"scrollFactor":1.0}],"keyboards":[],"touch":[],"switches":[],"tablets":[]}'
  local result
  result=$($CONTROLLER status) || return 1
  assert_json "$result" '.ok == true and .devices == [] and (.warnings | index("no_touchpad") != null)' "no-device status is wrong"
}

test_multiple_devices_are_retained() {
  export FAKE_HYPR_DEVICES_JSON='{"mice":[{"address":"0x1","name":"built-in-touchpad","defaultSpeed":0.1,"scrollFactor":1.0},{"address":"0x2","name":"desk-mouse","defaultSpeed":0.2,"scrollFactor":1.0},{"address":"0x3","name":"Bluetooth Trackpad","defaultSpeed":-0.3,"scrollFactor":1.0},{"address":"0x4","name":"keyd-virtual-pointer","defaultSpeed":0.0,"scrollFactor":1.0}],"keyboards":[],"touch":[],"switches":[],"tablets":[]}'
  local result
  result=$($CONTROLLER status) || return 1
  assert_json "$result" '.devices == ["built-in-touchpad", "Bluetooth Trackpad"]' "multiple touchpads were not retained"
}

test_hostile_device_names_remain_data() {
  export FAKE_HYPR_DEVICES_JSON='{"mice":[{"name":"evil\\path\"; os.execute(\"pwn\") -- touchpad","defaultSpeed":0},{"name":"line\nbreak-touchpad","defaultSpeed":0}],"keyboards":[],"touch":[],"switches":[],"tablets":[]}'

  $CONTROLLER initialize >/dev/null || return 1
  $CONTROLLER mode safe >/dev/null || return 1

  grep -F 'name = "evil\\path\"; os.execute(\"pwn\") -- touchpad"' "$FAKE_HYPR_LOG" >/dev/null || return 1
  ! grep -F 'line' "$FAKE_HYPR_LOG" >/dev/null
}

write_valid_settings() {
  mkdir -p "$TOUCHPAD_GUARD_STATE_DIR"
  printf '%s\n' '{"schemaVersion":1,"normal":{"sensitivity":0,"scrollFactor":0.4,"naturalScroll":false,"tapToClick":true,"tapAndDrag":true,"clickfingerBehavior":true,"tapButtonMap":"lrm","middleButtonEmulation":false,"dragLock":0,"drag3fg":0,"disableWhileTyping":true,"followMouse":1},"protectKeyboardFocus":true}' >"$TOUCHPAD_GUARD_STATE_DIR/settings.json"
}

test_same_session_retains_mode() {
  write_valid_settings
  printf '%s\n' '{"schemaVersion":1,"hyprlandSignature":"session-a","mode":"safe"}' >"$TOUCHPAD_GUARD_STATE_DIR/session.json"
  local result
  result=$($CONTROLLER initialize) || return 1
  assert_json "$result" '.mode == "safe"' "same-session mode was not retained"
}

test_new_session_resets_mode() {
  write_valid_settings
  printf '%s\n' '{"schemaVersion":1,"hyprlandSignature":"session-old","mode":"off"}' >"$TOUCHPAD_GUARD_STATE_DIR/session.json"
  local result
  result=$($CONTROLLER initialize) || return 1
  assert_json "$result" '.mode == "normal"' "new session did not reset to normal" || return 1
  jq -e '.hyprlandSignature == "session-a" and .mode == "normal"' "$TOUCHPAD_GUARD_STATE_DIR/session.json" >/dev/null
}

test_corrupt_state_is_quarantined() {
  mkdir -p "$TOUCHPAD_GUARD_STATE_DIR"
  printf 'not json\n' >"$TOUCHPAD_GUARD_STATE_DIR/settings.json"
  $CONTROLLER initialize >/dev/null || return 1
  jq -e '.schemaVersion == 1' "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >/dev/null || return 1
  compgen -G "$TOUCHPAD_GUARD_STATE_DIR/settings.json.invalid-*" >/dev/null
}

test_symlink_state_never_overwrites_target() {
  mkdir -p "$TOUCHPAD_GUARD_STATE_DIR"
  printf 'do-not-touch\n' >"$CASE_DIR/victim"
  ln -s "$CASE_DIR/victim" "$TOUCHPAD_GUARD_STATE_DIR/settings.json"
  $CONTROLLER initialize >/dev/null || return 1
  [[ $(<"$CASE_DIR/victim") == "do-not-touch" ]] || return 1
  [[ -f "$TOUCHPAD_GUARD_STATE_DIR/settings.json" && ! -L "$TOUCHPAD_GUARD_STATE_DIR/settings.json" ]]
}

test_symlink_lock_never_overwrites_target() {
  mkdir -p "$TOUCHPAD_GUARD_STATE_DIR"
  printf 'do-not-touch\n' >"$CASE_DIR/victim"
  ln -s "$CASE_DIR/victim" "$TOUCHPAD_GUARD_STATE_DIR/controller.lock"

  $CONTROLLER initialize >/dev/null || return 1

  [[ $(<"$CASE_DIR/victim") == "do-not-touch" ]]
}

test_oversized_state_is_quarantined() {
  write_valid_settings
  local oversized
  oversized=$(jq --arg padding "$(printf '%070000d' 0)" '.protectKeyboardFocus=false | .padding=$padding' "$TOUCHPAD_GUARD_STATE_DIR/settings.json")
  printf '%s\n' "$oversized" >"$TOUCHPAD_GUARD_STATE_DIR/settings.json"
  $CONTROLLER initialize >/dev/null || return 1
  jq -e '.protectKeyboardFocus == true and has("padding") == false' "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >/dev/null || return 1
  compgen -G "$TOUCHPAD_GUARD_STATE_DIR/settings.json.invalid-*" >/dev/null
}

test_out_of_range_state_is_quarantined() {
  write_valid_settings
  jq '.normal.sensitivity = 999 | .normal.scrollFactor = -5 | .normal.followMouse = 99' \
    "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >"$CASE_DIR/out-of-range.json"
  mv "$CASE_DIR/out-of-range.json" "$TOUCHPAD_GUARD_STATE_DIR/settings.json"

  $CONTROLLER initialize >/dev/null || return 1

  jq -e '. as $root |
    .normal.sensitivity >= -1 and .normal.sensitivity <= 1
    and .normal.scrollFactor >= 0 and .normal.scrollFactor <= 2
    and ([0,1,2,3] | index($root.normal.followMouse) != null)
  ' "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >/dev/null || return 1
  compgen -G "$TOUCHPAD_GUARD_STATE_DIR/settings.json.invalid-*" >/dev/null
}

test_failed_hyprland_read_preserves_settings() {
  write_valid_settings
  local before after
  before=$(sha256sum "$TOUCHPAD_GUARD_STATE_DIR/settings.json")
  export FAKE_HYPR_FAIL=devices
  if $CONTROLLER initialize >/dev/null 2>&1; then return 1; fi
  after=$(sha256sum "$TOUCHPAD_GUARD_STATE_DIR/settings.json")
  [[ $before == "$after" ]]
}

test_mode_cycle_applies_safe_off_and_normal() {
  $CONTROLLER initialize >/dev/null || return 1
  local result
  result=$($CONTROLLER mode safe) || return 1
  assert_json "$result" '.ok == true and .mode == "safe" and .effective.tapToClick == false and .effective.tapAndDrag == false and .effective.followMouse == 0' "safe status is wrong" || return 1
  grep -F 'tap_to_click = false' "$FAKE_HYPR_LOG" >/dev/null || return 1
  grep -F 'tap_and_drag = false' "$FAKE_HYPR_LOG" >/dev/null || return 1
  grep -F 'follow_mouse = 0' "$FAKE_HYPR_LOG" >/dev/null || return 1

  result=$($CONTROLLER cycle) || return 1
  assert_json "$result" '.ok == true and .mode == "off"' "safe did not cycle to off" || return 1
  grep -Fx 'off' "$FAKE_TOGGLE_LOG" >/dev/null || return 1

  result=$($CONTROLLER cycle) || return 1
  assert_json "$result" '.ok == true and .mode == "normal"' "off did not cycle to normal" || return 1
  grep -Fx 'on' "$FAKE_TOGGLE_LOG" >/dev/null
}

test_safe_preserves_and_normal_restores_preferences() {
  $CONTROLLER initialize >/dev/null || return 1
  $CONTROLLER mode safe >/dev/null || return 1
  jq -e '.normal.tapToClick == true and .normal.tapAndDrag == true and .normal.followMouse == 1' "$TOUCHPAD_GUARD_STATE_DIR/settings.json" >/dev/null || return 1
  : >"$FAKE_HYPR_LOG"
  local result
  result=$($CONTROLLER mode normal) || return 1
  assert_json "$result" '.effective.tapToClick == true and .effective.tapAndDrag == true and .effective.followMouse == 1' "normal preferences were not restored" || return 1
  grep -F 'tap_to_click = true' "$FAKE_HYPR_LOG" >/dev/null || return 1
  grep -F 'tap_and_drag = true' "$FAKE_HYPR_LOG" >/dev/null || return 1
  grep -F 'follow_mouse = 1' "$FAKE_HYPR_LOG" >/dev/null
}

test_set_clamps_numeric_values() {
  $CONTROLLER initialize >/dev/null || return 1
  local result
  result=$($CONTROLLER set scrollFactor 8) || return 1
  assert_json "$result" '.settings.normal.scrollFactor == 2 and .effective.scrollFactor == 2' "scroll factor was not clamped"
}

test_invalid_settings_do_not_mutate() {
  $CONTROLLER initialize >/dev/null || return 1
  local before
  before=$(sha256sum "$TOUCHPAD_GUARD_STATE_DIR/settings.json")
  : >"$FAKE_HYPR_LOG"
  if $CONTROLLER set notASetting true >/dev/null 2>&1; then return 1; fi
  if $CONTROLLER set naturalScroll perhaps >/dev/null 2>&1; then return 1; fi
  if $CONTROLLER set tapButtonMap xyz >/dev/null 2>&1; then return 1; fi
  [[ $before == "$(sha256sum "$TOUCHPAD_GUARD_STATE_DIR/settings.json")" ]] || return 1
  [[ ! -s $FAKE_HYPR_LOG ]]
}

test_every_supported_setting_round_trips() {
  $CONTROLLER initialize >/dev/null || return 1
  local key value filter result
  while IFS='|' read -r key value filter; do
    result=$($CONTROLLER set "$key" "$value") || return 1
    jq -e "$filter" <<<"$result" >/dev/null || return 1
  done <<'CASES'
sensitivity|-0.25|.settings.normal.sensitivity == -0.25
scrollFactor|0.75|.settings.normal.scrollFactor == 0.75
naturalScroll|true|.settings.normal.naturalScroll == true
tapToClick|false|.settings.normal.tapToClick == false
tapAndDrag|false|.settings.normal.tapAndDrag == false
clickfingerBehavior|false|.settings.normal.clickfingerBehavior == false
tapButtonMap|lmr|.settings.normal.tapButtonMap == "lmr"
middleButtonEmulation|true|.settings.normal.middleButtonEmulation == true
dragLock|2|.settings.normal.dragLock == 2
drag3fg|1|.settings.normal.drag3fg == 1
disableWhileTyping|false|.settings.normal.disableWhileTyping == false
protectKeyboardFocus|false|.settings.protectKeyboardFocus == false
CASES
}

test_safe_failure_rolls_back_to_normal() {
  $CONTROLLER initialize >/dev/null || return 1
  export FAKE_HYPR_FAIL_EVAL_MATCH='follow_mouse = 0'
  local result status
  result=$($CONTROLLER mode safe 2>/dev/null)
  status=$?
  (( status != 0 )) || return 1
  assert_json "$result" '.ok == false and .mode == "normal"' "safe failure did not report normal rollback" || return 1
  jq -e '.mode == "normal"' "$TOUCHPAD_GUARD_STATE_DIR/session.json" >/dev/null || return 1
  grep -F 'follow_mouse = 1' "$FAKE_HYPR_LOG" >/dev/null
}

test_off_failure_retains_previous_mode() {
  $CONTROLLER initialize >/dev/null || return 1
  $CONTROLLER mode safe >/dev/null || return 1
  export FAKE_TOGGLE_FAIL=1

  local result status
  result=$($CONTROLLER mode off 2>/dev/null)
  status=$?

  (( status != 0 )) || return 1
  assert_json "$result" '.ok == false and .mode == "safe" and .effective.tapToClick == false' \
    "failed Off transition did not report the retained Safe mode" || return 1
  jq -e '.mode == "safe"' "$TOUCHPAD_GUARD_STATE_DIR/session.json" >/dev/null || return 1
  grep -F 'follow_mouse = 0' "$FAKE_HYPR_LOG" >/dev/null
}

test_reset_reimports_current_configuration() {
  $CONTROLLER initialize >/dev/null || return 1
  $CONTROLLER set scrollFactor 1.5 >/dev/null || return 1
  export FAKE_SCROLL_FACTOR=0.6
  local result
  result=$($CONTROLLER reset) || return 1
  assert_json "$result" '.mode == "normal" and .settings.normal.scrollFactor == 0.6' "reset did not re-import current config" || return 1
  grep -Fx 'reload' "$FAKE_HYPR_LOG" >/dev/null
}

test_concurrent_settings_are_serialized() {
  $CONTROLLER initialize >/dev/null || return 1
  export FAKE_HYPR_DELAY=0.08
  $CONTROLLER set naturalScroll true >"$CASE_DIR/first.json" &
  local first=$!
  $CONTROLLER set scrollFactor 0.9 >"$CASE_DIR/second.json" &
  local second=$!
  wait "$first" || return 1
  wait "$second" || return 1
  local result
  result=$($CONTROLLER status) || return 1
  assert_json "$result" '.settings.normal.naturalScroll == true and .settings.normal.scrollFactor == 0.9' "concurrent updates lost a setting"
}

test_reapply_keeps_mode_without_osd() {
  $CONTROLLER initialize >/dev/null || return 1
  $CONTROLLER mode safe >/dev/null || return 1
  : >"$FAKE_HYPR_LOG"
  : >"$FAKE_OSD_LOG"
  local result
  result=$($CONTROLLER reapply) || return 1
  assert_json "$result" '.ok == true and .mode == "safe"' "reapply changed the active mode" || return 1
  grep -F 'tap_to_click = false' "$FAKE_HYPR_LOG" >/dev/null || return 1
  [[ ! -s $FAKE_OSD_LOG ]]
}

if [[ $group == all || $group == state ]]; then
  run_test "status reports imported defaults" test_status_reports_imported_defaults
  run_test "initialize persists imported settings" test_initialize_persists_imported_settings
  run_test "no touchpad is a supported status" test_no_device_is_supported
  run_test "multiple touchpads are retained" test_multiple_devices_are_retained
  run_test "hostile device names remain escaped data" test_hostile_device_names_remain_data
  run_test "same Hyprland session retains mode" test_same_session_retains_mode
  run_test "new Hyprland session resets mode" test_new_session_resets_mode
  run_test "corrupt state is quarantined" test_corrupt_state_is_quarantined
  run_test "symlink state cannot overwrite its target" test_symlink_state_never_overwrites_target
  run_test "symlink lock cannot overwrite its target" test_symlink_lock_never_overwrites_target
  run_test "oversized state is quarantined" test_oversized_state_is_quarantined
  run_test "out-of-range state is quarantined" test_out_of_range_state_is_quarantined
  run_test "failed Hyprland read preserves settings" test_failed_hyprland_read_preserves_settings
fi

if [[ $group == all || $group == modes ]]; then
  run_test "mode cycle applies Safe, Off, and Normal" test_mode_cycle_applies_safe_off_and_normal
  run_test "Safe preserves and Normal restores preferences" test_safe_preserves_and_normal_restores_preferences
  run_test "numeric settings clamp to supported ranges" test_set_clamps_numeric_values
  run_test "invalid settings never mutate state" test_invalid_settings_do_not_mutate
  run_test "every advertised setting round-trips" test_every_supported_setting_round_trips
  run_test "failed Safe application rolls back to Normal" test_safe_failure_rolls_back_to_normal
  run_test "failed Off application retains the previous mode" test_off_failure_retains_previous_mode
  run_test "reset reloads and imports current configuration" test_reset_reimports_current_configuration
  run_test "concurrent settings are serialized" test_concurrent_settings_are_serialized
  run_test "reapply keeps mode and stays silent" test_reapply_keeps_mode_without_osd
fi

printf '1..%d\n' "$tests"
(( failures == 0 ))
