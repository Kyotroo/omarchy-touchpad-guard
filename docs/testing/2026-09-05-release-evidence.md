# Release evidence — Touchpad Guard 1.0.0

Release candidate verification was completed on 2026-09-05. The public
release is identified by the immutable `v1.0.0` tag.

## Automated gate

- 23 controller integration tests passed.
- 12 pure QML-model tests passed.
- The manifest, package, preview, privacy, and executable-bit contract passed.
- Every Bash entry point passed `bash -n`.

## Live gate

The installed plugin was exercised on Hyprland 0.56.2 with Quickshell 0.3.1.
Normal, Typing Safe, Off, keyboard recovery, shell restart, configuration
reload, all advanced controls, panel rendering, and state restoration passed.
The session ended in Normal with Omarchy's disabled-touchpad marker absent.

Detailed results are in
[`2026-09-05-live-verification.md`](2026-09-05-live-verification.md).

## Preview and privacy

- `preview.png` is a 1440×900, 8-bit sRGB PNG captured from the running plugin.
- Visual inspection and OCR found only the Touchpad Guard UI, Omarchy bar, and
  a technical touchpad identifier.
- The PNG contains no EXIF or textual PNG metadata chunks.
- The public branch is built as one clean root commit with a GitHub noreply
  author identity. Development history and internal planning files are not
  published.
- Tracked text and release history contain no private home path, email address,
  household/profile name, credential, or unrelated media.

## Publication

- Repository: <https://github.com/Kyotroo/omarchy-touchpad-guard>
- Release: <https://github.com/Kyotroo/omarchy-touchpad-guard/releases/tag/v1.0.0>

Outbound delivery acceptance is recorded locally after publication so an
email address or provider message identifier never becomes part of the public
repository.

Keyboard-safe recovery remains:

```bash
omarchy toggle touchpad on
```
