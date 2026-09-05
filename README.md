# Touchpad Guard

Stop accidental touchpad taps while you type—without giving up two-finger scrolling.

Touchpad Guard is a persistent, mode-first bar widget for the Quickshell-based Omarchy shell. One click or shortcut moves between everyday touchpad behavior, a safer typing mode, and fully Off. The same panel also keeps Hyprland's useful touchpad settings in one place.

![Touchpad Guard panel](preview.png)

## Three clear modes

| Mode | Tap and tap-drag | Scroll and pointer movement | Physical clickpad press | Pointer-driven focus |
|---|---|---|---|---|
| **Normal** | Your saved preference | Available | Available | Your saved Hyprland behavior |
| **Typing Safe** | Forced off | Available | Available | Protected by default |
| **Off** | Off | Off | Off | Unchanged |

Typing Safe is deliberately explicit. It does not guess when you are typing, and it does not install a low-level input filter.

## Install

Requires the Quickshell-based Omarchy shell and Hyprland 0.56 or newer.

```bash
omarchy plugin add https://github.com/Kyotroo/omarchy-touchpad-guard.git
omarchy plugin enable kdm.touchpad-guard
```

The widget is added to the right side of the Omarchy bar. Move it with Omarchy's bar settings if you prefer another position.

### Add the shortcut

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Cycle touchpad guard", "omarchy-shell kdm.touchpad-guard cycle")
o.bind("SUPER + CTRL + SHIFT + T", "Touchpad guard settings", "omarchy-shell kdm.touchpad-guard toggle")
```

Add both. The second one matters more than it looks: the touchpad is the thing
this plugin turns off, so the panel needs a way in that does not depend on it.

Then reload Hyprland:

```bash
hyprctl reload
```

If that key is already bound to `omarchy toggle touchpad`, replace that one binding instead of adding a duplicate.

## Use

- **Click** the bar icon to open the mode and settings panel. Left and right
  both open it.
- **Middle-click** to refresh detected hardware and state.
- Press **Super + Shift + T** to cycle Normal → Typing Safe → Off → Normal.
- Press **Super + Ctrl + Shift + T** to open the panel without the touchpad.

Clicking the icon never changes the mode. On a clickpad the hardware reports a
single button and libinput decides what a press means, so a press meant as a
right-click can arrive as a left-click. If that click cycled the mode, a misread
press could reach Off — switching off the touchpad you were trying to click
with. Mode changes are deliberate: the panel's mode row, the shortcut, or IPC.

The icon and tooltip always identify Normal, Typing Safe, Off, unavailable hardware, or an error. Successful mode changes also produce an Omarchy OSD.

Keyboard users can navigate the panel with `j`/`k` or the arrow keys, adjust sliders and option rows with `h`/`l`, activate with Enter or Space, and close with Escape.

## Advanced settings

Touchpad Guard reads the current Hyprland values the first time it runs, then saves the Normal profile independently:

- Pointer sensitivity
- Two-finger scroll speed
- Natural scrolling
- Tap-to-click
- Tap-and-drag
- Clickfinger behavior
- Tap button order
- Middle-button emulation
- Drag lock
- Three- or four-finger drag
- Hyprland's native Disable while typing
- Keyboard-focus protection in Typing Safe

Changes apply immediately. Typing Safe visibly locks tap-to-click and tap-and-drag off but leaves the saved Normal choices untouched. Off keeps every preference ready for restoration.

### Keyboard-focus protection

Hyprland's `follow_mouse` setting is global. When **Protect keyboard focus in Typing Safe** is enabled, Touchpad Guard temporarily sets it to zero so incidental pointer motion cannot move keyboard focus. That also changes focus-following behavior for an external mouse while Safe is active. Normal restores the value imported for the Normal profile.

### Disable while typing

The panel exposes Hyprland's native `disable_while_typing` option, but some input stacks still allow simultaneous typing and touchpad use. Touchpad Guard does not claim that native option will work on every machine. Typing Safe is the reliable manual protection this plugin provides.

## Sessions and state

Preferences are stored under:

```text
~/.local/state/omarchy/kdm-touchpad-guard/
```

Touchpad Guard never edits `~/.config/hypr/input.lua` or files under `/usr/share/omarchy`.

Every new Hyprland login starts in Normal. Restarting only the Omarchy shell during the same login retains the selected mode. A Hyprland configuration reload silently reapplies that mode, and device changes are reconciled automatically.

Reconciliation is event-driven. Touchpad Guard reapplies the active profile when
Hyprland reloads its config or a pointer device appears or disappears — not on a
repeating timer. It polls its own status once a minute so the icon stays honest,
but that poll is read-only. This is worth knowing if you experiment by hand: a
value you set yourself now survives until the next reload, rather than being
overwritten seconds later. Omarchy's Lua config rejects `hyprctl keyword`, so
experiment with `eval`:

```bash
hyprctl eval 'hl.config({ input = { touchpad = { clickfinger_behavior = false } } })'
```

That lasts until the next config reload. To make a change Touchpad Guard keeps,
set it through the plugin instead:

```bash
omarchy-shell kdm.touchpad-guard set clickfingerBehavior false
```

Touchpads and trackpads are detected from Hyprland's pointer list by their device names, following Omarchy's existing hardware-detection convention. Multiple matching devices receive the same mode and preferences.

**Reset to current Omarchy config** reloads Hyprland, imports the resulting touchpad values, replaces the saved Normal profile, and returns to Normal.

## Command interface

The bar widget exposes a small IPC interface:

```bash
omarchy-shell kdm.touchpad-guard status
omarchy-shell kdm.touchpad-guard cycle
omarchy-shell kdm.touchpad-guard normal
omarchy-shell kdm.touchpad-guard safe
omarchy-shell kdm.touchpad-guard off
omarchy-shell kdm.touchpad-guard set scrollFactor 0.6
omarchy-shell kdm.touchpad-guard reset
```

The controller can also be called directly from the installed plugin directory. Its machine-readable commands return a versioned JSON object.

## Recovery and troubleshooting

### Right-click acts like a left-click

This is usually the click method, not a fault. Most laptop touchpads are
clickpads: the hardware has one button and reports every press as `BTN_LEFT`,
so libinput synthesises the right button. Check which way it does that:

```bash
hyprctl getoption input:touchpad:clickfinger_behavior
```

Omarchy's default is `true`. With clickfinger on, right-click is a **two-finger
press**, and the bottom-right corner is not a right-click zone — a one-finger
press there is a left-click, by design. Two-finger **tap** also right-clicks
while tap-to-click is on, which Typing Safe deliberately turns off.

To use the bottom-right corner instead, switch to button areas through the
plugin so the setting is saved in your Normal profile:

```bash
omarchy-shell kdm.touchpad-guard set clickfingerBehavior false
```

Confirm what the kernel exposes if you want to be certain the pad has no real
right button:

```bash
grep -A6 'Touchpad' /proc/bus/input/devices
```

`PROP=5` includes `INPUT_PROP_BUTTONPAD`, and a `KEY=` bitmap with bit 272 but
not 273 means `BTN_LEFT` with no `BTN_RIGHT`.

### Other recovery

If the touchpad is Off and the widget or shell is unavailable, re-enable it from the keyboard:

```bash
omarchy toggle touchpad on
```

Refresh plugin discovery and inspect cached state:

```bash
omarchy-shell shell rescanPlugins
omarchy-shell kdm.touchpad-guard status | jq
```

During local plugin development, a full `omarchy restart shell` may be required after changing QML methods because the running component cache can retain the earlier interface.

If no touchpad appears, compare the hardware Omarchy detects with Hyprland's pointer list:

```bash
omarchy-hw-touchpad
hyprctl -j devices | jq '.mice'
```

## Remove

Switch to Normal before removal so saved preferences are restored and Omarchy's disabled-touchpad marker is cleared:

```bash
omarchy-shell kdm.touchpad-guard normal
omarchy plugin remove kdm.touchpad-guard
```

If the plugin has already been removed while Off, use `omarchy toggle touchpad on`.

Omarchy intentionally does not run plugin install or removal hooks, so Touchpad Guard does not modify bindings automatically. Remove its `SUPER + SHIFT + T` line manually if you no longer want the shortcut.

## Security and privacy

- No sudo, telemetry, network calls, install hooks, or runtime downloads.
- QML starts the bundled controller with an argument array, never a shell command string.
- Commands, settings, enums, numeric ranges, and device names are validated.
- State writes are size-bounded, ownership-checked, and atomically replaced.
- Invalid or unsafe state is quarantined and rebuilt from live Hyprland values.
- Device names are treated as data and escaped before reaching Hyprland's Lua evaluator.

## Development

Run the deterministic controller, model, package, concurrency, and failure-path suites:

```bash
bash tests/run
```

The tests use isolated command fixtures and never mutate the real touchpad.

## License

MIT

