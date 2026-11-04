# Keymap release plan

Status: 0.3.0 implementation and automated/hardware-readback validation updated in November 2026; 0.4.0 remains proposed.

The current `feat/keymap-editor` branch contains the initial editor and declares
version 0.3.0. The validation record in `docs/validation-0.3.0.md` distinguishes completed
checks from remaining physical interaction and desktop acceptance. Complete the 0.3.0 work
below before treating the first release as ready.

## Release 0.3.0: finish the core editor

### 1. Make conflicts explicit

Files: `nuphy_keymap.py`, `Service.qml`, `KeymapEditor.qml`, translations, tests.

- Return structured conflicts containing device identity, layer, key index,
  original assignment, current assignment, and proposed assignment.
- Show the affected keys in the pending-changes list, with readable assignment
  names and numeric fallbacks for unknown codes.
- Offer **Keep keyboard assignment** to remove that edit and **Keep my edit** to
  acknowledge the current value as its new baseline. Neither action writes.
- Disable Apply while conflicts remain unresolved. Do not silently apply only
  the nonconflicting subset.
- Recheck the device and assignments when Apply is subsequently pressed. A new
  external change must produce a new conflict even after an earlier resolution.
- Distinguish conflict, unavailable device, unsupported CLI, failed write, and
  unknown hardware state in the response model. Preserve recovery information.

Acceptance: change a pending key externally, refresh or apply, resolve it using
either choice, and verify the resulting draft and commands. Unrelated changes
must survive. Already-satisfied edits disappear without a write.

### 2. Preserve drafts across reconnects

Files: backend device metadata, `nuphy_worker.py`, `Service.qml`, editor, tests.

- Separate the current connection identity from stable device identification.
  Keep the connection token for every operation and response.
- Use a usable serial number together with vendor/product identification when
  available; verify geometry before reconciling. Do not equate a reused hidraw
  path, product name, or identical matrix with the same physical keyboard.
- On disconnect, preserve the draft and mark its readings stale. Block writes.
- On reconnect to a positively identified keyboard, read current and factory
  mappings, then reconcile each draft against original/current/proposed values
  using the same conflict rules as step 1. Reconnect never applies a draft.
- When identity is uncertain, retain the draft separately and offer an explicit
  **Review draft for this keyboard** action after checking compatibility. Show
  the target keyboard and proposed changes before binding the draft to it.
- Loading a different keyboard must not silently discard or transfer an old
  draft. Provide an explicit discard action and a visible detached-draft state.
- Ignore responses from a previous connection generation. A worker restart
  invalidates readings and requires refresh; a shell restart may still clear
  in-memory drafts in this release.

Acceptance: cover identified reconnect, a device without a serial, another unit
of the same model, reused hidraw paths, changed geometry, ambiguous devices, and
delayed responses. No path may automatically write or silently lose a draft.

### 3. Exercise the complete command and UI flow

Files: `tests/test_keymap.py`, `tests/test_worker.py`, QML smoke fixtures, and a
reusable fake CLI/device fixture.

- Drive successful load and apply through the actual worker process, JSON
  protocol, and shared QML service. Confine the fake device setup to tests.
- Have the fake CLI keep mappings in a temporary file, parse generated TOML,
  create binary backups, and record commands and selectors.
- Cover changes across several layers, no-op apply, partial writes, timeouts,
  failed readback, backup failure, unsupported commands, malformed output,
  and a worker dying during an operation.
- Assert that unresolved edits survive partial success, verified edits clear,
  and unknown state prevents another write until refresh succeeds.
- Exercise two editor instances sharing one service: changes, discard, Apply,
  busy state, errors, and device invalidation must agree in both.
- Interleave lighting/theme events with keymap work and verify serialization,
  request completion, lighting retry behavior, and no keymap automatic retry.
- Test user interactions rather than only directly calling helper functions:
  selecting a key, searching, choosing an assignment, switching layers, closing
  and reopening, keyboard navigation, and resolving a conflict.
- Ensure opening, refreshing, browsing, and reconnecting produce no keymap write.

Acceptance: the complete suite and plugin validation pass with hardware access
isolated. Failures are asserted from actual protocol/UI behavior, not only mocks
of internal methods.

### 4. Verify and polish the live UI

- Inspect the running widget at normal and increased UI scale, on wide and
  narrow available screen areas, and on multiple monitors where available.
- Compare every drawn Air75 V3 key and knob control against the physical board
  and CLI index map. Correct spacing, widths, labels, and index associations.
- Check that the key selector fallback, action footer, pending list, and search
  results remain reachable without clipping or unreadable text.
- Check Tab, Enter/Space, arrow navigation, focus on reopen, and Escape ordering
  across dropdowns, the assignment picker, and the outer popup.
- Check selected, modified-from-factory, pending, conflicting, busy, and stale
  states. Keep meanings distinguishable without relying only on color.
- Check right-to-left text layout while retaining physical keyboard order.
- Show a clear success/no-change result and actionable failure information.

Acceptance: record the checked display/scale configurations and capture the
final UI for review. Resolve any QML warnings caused by these interactions.

### 5. Perform hardware acceptance and prepare release

- Record keyboard model, firmware, CLI build/version, and control interface.
- Save and verify a full baseline backup before the first test write.
- Compare initial UI readings to CLI output.
- Change one nonessential key, apply, verify readback and physical behavior,
  then restore its exact original assignment.
- Repeat with a small batch across layers and supported knob assignments.
- Test an external-edit conflict and reconnect behavior. Keep deliberate
  mid-write disconnects and failure injection in the fake-device tests.
- Read the full keymap afterward and compare with the original baseline so
  unrelated existing customizations are preserved.
- Update README behavior, supported-device notes, dependency requirements,
  screenshots, and release notes to match the verified implementation.
- Review the complete branch, rerun affected checks, and prepare the 0.3.0 PR.
  Merge, tagging, and publication are separate release actions.

Release gate: steps 1–5 have evidence, no unresolved write/recovery defects, and
remaining device/layout limitations are documented.

## Release 0.4.0: reusable mappings and recovery controls

Build on the conflict, identity, preview, and readback behavior from 0.3.0.
Keep these features in a secondary **Profiles and recovery** view so the ordinary
key editor remains compact.

### 1. Establish operation previews and backup metadata

- Create a common preview model for imports, profiles, restores, and resets:
  target identity, source, affected modes/layers, old/new assignments, and the
  read revision used for the preview.
- Revalidate before writing. If readings or the target changed after preview,
  require an updated preview rather than executing an obsolete one.
- Store backup metadata alongside new widget backups: schema version, timestamp,
  device identifiers, firmware, geometry, content hash, operation, and outcome.
- Write metadata atomically and keep backup bytes private. Preserve the last
  known recovery reference across refresh and worker restart.
- Treat legacy binary backups as having unknown provenance; byte length alone
  cannot prove device compatibility. They need explicit target review.
- Detect required CLI capabilities lazily and explain unavailable features.
  `keymap export` produces TOML text; it does not use the JSON command helper.

Acceptance: stale previews cannot write; mismatched or damaged backup/metadata
pairs are rejected; a restart retains usable recovery history.

### 2. Import and export TOML mappings

- **Export keyboard mappings** uses the applied keyboard state, including
  differences from factory, through `nuphyctl keymap export`.
- **Export pending edits** is a separate explicit action. It serializes the
  proposed assignments without applying them.
- Import a local TOML file, bound its size, validate it against the target, and
  use CLI dry-run output to obtain the canonical changes where possible.
- Stage the imported assignments in the shared draft and show a preview before
  Apply. Opening a file never writes mappings.
- If a draft already exists, offer merge or replacement of the draft. Surface
  overlapping assignments for review instead of silently overwriting them.
- Explain that omitted keys keep their current assignments. Preserve unknown
  numeric codes and accept the CLI's documented naming/index syntax.
- A file picker cancellation leaves state unchanged. Resolve overwrite choices
  before exporting over an existing file; store app-owned exports atomically.

Acceptance: round-trip known and unknown codes, multiple layers, invalid TOML,
unsupported addresses, duplicate assignments, empty diffs, and canceled actions.
Exports must clearly reflect the chosen source: keyboard or pending draft.

### 3. Add named local profiles

- Save, list, rename, duplicate, and delete named profiles using local atomic
  storage with a versioned metadata schema and opaque internal IDs.
- Store mappings as interoperable TOML plus descriptive metadata: display name,
  intended layout/geometry, optional device association, and creation/update time.
- Define profiles as collections of listed mappings. **Load into draft** shows
  exactly what will change; omitted keys stay as they are. Do not imply that a
  profile represents or replaces the whole keyboard configuration.
- Reuse import validation, draft merge choices, and operation previews.
- Saving a profile never writes hardware. Applying is always explicit, and
  there is no automatic profile selection on startup or reconnect in 0.4.0.
- Validate compatibility before staging and require explicit review when device
  association is uncertain. Geometry equality alone is not layout equivalence.

Acceptance: profiles survive restart, corrupted files are handled without losing
other profiles, names cannot affect filesystem paths, and applying a profile
preserves all unlisted assignments.

### 4. Add backup browsing and reviewed restore

- List widget-created backups with keyboard, timestamp, operation, and outcome.
- Permit opening a legacy or CLI-created backup through a local file picker.
- Use `keymap restore-backup --dry-run --json` to preview the changes, including
  their full mode/layer scope, before enabling Restore.
- Explain that restoring a full backup may replace later unrelated edits. Keep
  this operation separate from reverting a pending edit or applying a profile.
- Preserve existing pending drafts separately; reconcile them against restored
  readings after completion rather than mixing them into the restore operation.
- Create a fresh pre-restore recovery backup, run the serialized restore, and
  read back. Recover partial failures using the same rules as ordinary Apply.
- Offer explicit backup deletion. Defer automatic pruning until retention rules
  can protect the recovery point for a failed or unresolved operation.

Acceptance: restore a known fixture, reject corrupted/incompatible inputs, handle
stale previews and partial failure, and preserve a valid pre-restore recovery path.

### 5. Add factory reset for a selected mode

- Offer **Reset Mac mode**, **Reset Windows mode**, and **Reset all modes** in the
  recovery view, with exact affected layers and the current-to-factory diff.
- Build the preview from current and factory reads; the current reset command
  does not offer `--dry-run`.
- Require an explicit final Reset action naming its scope. Only then invoke
  `keymap reset --mode ... --yes --json` with the verified device selectors.
- Save a pre-reset backup and reconcile pending drafts after readback, as for
  restore. Disable reset when the reported modes do not match supported scopes.

Acceptance: mode-specific resets preserve the other mode, all-mode reset matches
factory data, cancel does not write, and failure retains recovery information.

### 6. Validate and prepare 0.4.0

- Extend the fake CLI and UI tests for every new operation and failure path.
- Perform live visual checks for file selection, profile lists, previews, long
  names, empty/error states, and recovery navigation.
- On hardware, export the baseline, apply and undo a small imported/profile
  mapping, and verify a reviewed backup restore. Exercise resets against a
  backed-up test setup, then restore and compare the full original map.
- Update documentation, screenshots, translations, capability requirements, and
  release notes. Review storage migration and damaged-file recovery behavior.

Release gate: previews and backups are reliable for every write operation, no
implicit writes occur, existing lighting/keymap tests pass, and hardware returns
to the recorded baseline after acceptance.

## Later work requiring separate design or upstream support

- **Macro editing:** first determine whether supported keyboard firmware exposes
  macro storage and execution, then add documented CLI read/write/validation
  support. A raw keycode picker cannot substitute for a macro programming API.
  Schedule the widget editor only after those capabilities are verified.
- **Atomic conflict protection:** investigate a CLI conditional-apply operation
  that accepts expected old values and checks them in the write session. Document
  any remaining firmware/external-client race; host-side checks cannot promise
  device-level atomicity by themselves.
- **Automatic profiles, full-layout profile replacement, persistent unfinished
  drafts, additional physical layouts, and backup retention policies:** design
  separately after the explicit workflows have been exercised in practice.

## Suggested implementation order and commits

1. `fix(keymap): expose and resolve per-key conflicts`
2. `fix(keymap): retain drafts across keyboard reconnects`
3. `test(keymap): cover full worker and shared editor flows`
4. UI fixes and acceptance documentation for 0.3.0, scoped to findings.
5. `feat(keymap): add operation previews and backup metadata`
6. `feat(keymap): import and export TOML mappings`
7. `feat(keymap): manage named local profiles`
8. `feat(keymap): preview and restore recovery backups`
9. `feat(keymap): reset selected modes to factory mappings`
10. Acceptance documentation and release preparation for 0.4.0.

Keep focused tests with each behavioral change; the dedicated test step adds
coverage across component boundaries. Each release should be reviewable and
usable before beginning the next release's feature work.
