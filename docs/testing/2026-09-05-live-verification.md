# Live verification — 2026-09-05

Touchpad Guard 1.0.0 was verified on a real Omarchy session with Hyprland
0.56.2 and Quickshell 0.3.1. The machine exposed one built-in touchpad. Hardware
identifiers and user-specific paths are intentionally omitted from this record.

## Results

| Check | Result |
|---|---|
| Plugin discovery and persistent right-bar placement | Pass |
| Normal → Typing Safe → Off → Normal cycle over shell IPC | Pass |
| Typing Safe effective values | Pass: tap-to-click off, tap-and-drag off, `follow_mouse = 0` |
| Normal restoration | Pass: all imported preferences restored exactly |
| Off integration | Pass: Omarchy's disabled-touchpad marker was created and then cleared on recovery |
| Configuration reload while Typing Safe | Pass: the widget observed the reload and silently reapplied Safe |
| Omarchy shell restart while Typing Safe | Pass: Safe survived the shell restart in the same Hyprland session |
| All twelve advanced controls | Pass: every value was changed through live IPC, confirmed, and restored |
| Panel open, close, and keyboard layer | Pass |
| Shortcut registration | Pass: `SUPER + SHIFT + T` is loaded with the expected description and IPC payload |
| Runtime warnings attributable to this plugin | Pass: none after a fresh shell restart and panel open/close |

The focus-protection check used Hyprland's reported effective setting rather
than claiming that a compositor cursor warp was physical touchpad input.
Programmatic cursor warps do not generate the same focus event as real pointer
motion. The controller did set `input:follow_mouse` to `0` in Typing Safe and
restore the imported value `1` in Normal, which is the native Hyprland mechanism
the feature is designed around.

## Automated suite

`bash tests/run` passed with:

- 23 controller integration tests
- 12 QML model tests
- the manifest, package, privacy, and executable-bit contract

The controller tests use isolated fixtures and do not mutate the live touchpad.
Live tests ended in Normal mode with Omarchy's disabled-touchpad marker absent.
