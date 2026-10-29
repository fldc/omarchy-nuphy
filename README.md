# NuPhy for Omarchy

A native Quickshell bar plugin for NuPhy keyboards supported by `nuphyctl`.
The title follows the connected keyboard’s reported product name; when the CLI
cannot identify an automatic target, it falls back to “NuPhy keyboard”.

- Independent backlight, side and decorative lighting controls.
- All 20 main effects and all five side/decorative effects exposed by nuphyctl.
- Custom `#RRGGBB`, brightness, animation speed and main-light direction.
- Per-zone automatic sync with `~/.local/state/omarchy/current/theme/keyboard.rgb`.
- Theme sync preserves each zone’s chosen effect, brightness and speed.
- Verified NuPhy targets with explicit HID interface selectors on every write.
- One persistent service shared by all monitors, with serialized HID writes.
- Event-driven theme and hotplug detection, with a 60-second discovery fallback.
- 12-second HID command timeout, 30-second failure retry cooldown.
- Device-specific sync cache, invalidated on reconnect and worker restart.
- Lazy popup creation, per-zone editing drafts, and keyboard-adjustable sliders.
- Atomic preferences with safe recovery and backups of damaged state.
- Persistent preferences; no keymap access, network access or elevated privileges.

## Install

Requires Omarchy’s Quickshell-based shell, Python 3 and `nuphyctl` on PATH.
The keyboard’s control interface must be accessible to your user.

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/local.nuphy
omarchy plugin validate ~/.config/omarchy/plugins/local.nuphy
omarchy plugin enable local.nuphy
```

Run the symlink command from this project directory. Do not overwrite an existing
plugin with the same ID. Layout changes hot-reload; if plugin code stays cached,
run `omarchy restart shell`. The 0.2.0 update adds a service entry point and needs
one shell restart when upgrading from 0.1.0.

## Use

Click the keyboard icon, select a lighting zone, edit its preferences and click
**Apply lighting**. To sync a zone, check **Follow Omarchy theme** and Apply.
Sync is initially disabled for every zone: installing the widget never changes
the keyboard on its own. Linux inotify watches the theme file, its symlink
ancestors, and HID device-node changes. Events are coalesced for 200 milliseconds;
theme changes do not spawn helper processes unless enabled lighting needs a write.
One slow fallback enumerates devices every 60 seconds, regardless of monitor count.

**Sync enabled zones now** forces a reapply, useful after reconnecting or changing
lighting with the keyboard itself. Preferences are not live hardware readings;
`nuphyctl` currently provides lighting writes but no lighting-state readback.
Pending edits survive zone switches while the popup component is loaded.
Apply saves a zone’s preferences
even if the device is disconnected; enabled sync retries after 30 seconds.
Manual (non-sync) writes can be retried with Apply.

Decorative lighting is experimental in `nuphyctl`. Its offset defaults to 17;
some layouts use 35. It is not written unless you explicitly Apply that zone or
enable its sync. Consult your model/protocol documentation before changing it.

State lives in `$XDG_STATE_HOME/omarchy-nuphy/state.json` (normally
`~/.local/state/omarchy-nuphy/state.json`). All bar instances use the same service;
a singleton worker lock prevents competing writers. State lock acquisition times
out after two seconds. Discovery happens outside the state lock.

Damaged preferences are retained as `state.corrupt-<timestamp>.json` before safe
defaults are restored with sync disabled. A restart/reconnect reapplies enabled
zones once: cached success does not imply the hardware retained its settings.
Multiple equally ranked NuPhy keyboards are deliberately treated as ambiguous;
no lighting commands are sent until one unambiguous target is available.

Open from a keybinding or terminal:

```bash
omarchy-shell nuphy toggle
```

## Development

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

Tests include mocked hardware, actual worker-process protocol/event tests with a
fake CLI, and an offscreen Quickshell editor smoke test. They never send HID
commands to your keyboard. The UI test requires installed Omarchy shell components
and Quickshell; it skips when these are unavailable. Sliders support Tab focus
and Left/Right arrow adjustment.

English translations are in `i18n/en.json`;
other Omarchy languages fall back to English.
