# Keyboard settings integration validation

Implemented in the Settings tab:

- Auto Sleep, with timers preserved when disabled.
- Level 1 Sleep (lights off) and Level 2 Sleep (lights and communication off),
  bounded to 5–127 minutes. Level 2 follows Level 1.
- Opt-in Accessory Switch read and Knob / Button selection for compatible boards.
- Shared pending edits, explicit Apply / Discard / Refresh, device-generation
  checks, edited-field conflict checks and verified readback after writes.

Reset Keyboard is excluded. NuPhy IO's Keyboard Layout label selector is not a
firmware setting and is not presented as one. HE configuration is unsupported.

## CLI contract

The integration uses the supplied mechanical-protocol `settings get/set --json`
interface. The local debug executable's `settings`, `settings get` and
`settings set --help` output confirmed its command/selector flags without HID
access. At implementation time, the specified `src/settings_cmd.rs` was absent
and `src/cli.rs` / `docs/usage.md` in the nuphyctl checkout did not contain the
settings changes; no files in that repository were modified. Set-result JSON is
not assumed to imply success: the plugin independently gets settings and checks
requested values after every write attempt, including failed/partial writes.

Older backends produce a clear unavailable error. A missing CLI, unsupported HE
model, malformed response, changed device, CLI timeout, conflicting edited field,
or failed readback cannot enable a write from stale readings. Accessory get
failure leaves verified sleep readings available. All commands use the existing
bounded subprocess runner and explicit device/interface selectors.

`NUPHYCTL` is an explicit executable override inherited by the worker; the
normal default is `nuphyctl` on PATH. The override applies to all worker CLI
operations. Tests override it to their isolated fake CLI.

## Automated evidence

- Full Python/QML suite: **76 tests passed**.
- Affected UI suite rerun after strengthening stale-state handling: **7 passed**.
- `omarchy plugin validate .` and Git whitespace checks pass.
- Unit fixtures cover opt-in accessory reads, partial-field writes, unchanged
  values, conflicts, readback mismatch/failure, unsupported/missing backends,
  invalid timer values, disconnects and devices changing during reads.
- Offscreen QML drives the actual Settings tab and worker against a stateful fake
  CLI. It verifies shared drafts, sleep disabling without timer changes, timer
  bounds, discard, explicit accessory reads/Apply and disconnect invalidation.

No live keyboard settings were changed. Changed-value hardware acceptance,
including physical sleep/wake and accessory behavior, remains untested by this
integration. The handoff's prior live reads/dry-run/unchanged-set results are
context, not additional hardware tests performed here.
