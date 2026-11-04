# Keymap release plan

Status: updated November 4, 2026. The 0.3.0 implementation is merged into
`main` through [PR #2](https://github.com/fldc/omarchy-nuphy/pull/2).
The manifest declares 0.3.0; no release tag or GitHub release has been published.
Release 0.4.0 remains planned work.

## Current progress

| Workstream | Completed | Remaining |
| --- | --- | --- |
| Core editor | Read current/factory mappings, shared drafts, explicit batch Apply, backup and readback | Physical input acceptance |
| Conflicts and reconnects | Per-key resolution, repeat conflict checks, detached drafts, explicit compatible rebinding, generic serial handling | Physical unplug/reconnect and a second keyboard |
| Air75 V3 diagram | NuPhyIO-style FN0–FN7 labels, contiguous 16-unit geometry, corrected right Shift, current/pending key labels, knob press and rotation controls | Compare against the physical board and exercise the anchored popup |
| Other layouts | Scrollable firmware matrix, selectable zero-valued entries, separate extra controls, position selector | Validate on another actual model |
| Layout requests | Repository issue template and prefilled issue link shown only for unsupported layouts; model/geometry metadata only | Use incoming requests to add verified physical layouts |
| Automated checks | 54 passing tests, plugin validation, whitespace checks; fake-CLI worker and shared-editor interaction coverage | Review the unverified scenarios listed below |
| Visual checks | Wide, narrow and 1.5x scale renders; clipping and width binding-loop fixes | Actual multi-monitor popup, RTL, keyboard focus/navigation and final themed screenshots |
| Hardware protocol | Air75 V3 firmware 1.0.23.6: batch writes across both modes and knob directions, verified restoration of all 784 entries | Physical keypress/knob behavior and reconnect acceptance |
| Delivery | PR #2 merged into main | Release notes, final acceptance, tag and publication |

Detailed evidence and outstanding manual checks are recorded in
[the 0.3.0 validation record](docs/validation-0.3.0.md). The layout issue template
is in [.github/ISSUE_TEMPLATE/keyboard-layout.md](.github/ISSUE_TEMPLATE/keyboard-layout.md).
Passing tests and rendered previews do not establish physical input or desktop
acceptance.

## Release 0.3.0: finish acceptance and publication

The detailed behavior and acceptance criteria below remain the release checklist.
The progress table above distinguishes implemented behavior from checks still
needing evidence.

### 1. Conflict handling — implemented

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

### 2. Reconnect drafts — implemented; physical acceptance pending

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

### 3. Worker and UI coverage — current suite passing

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

### 4. UI polish — implemented; desktop acceptance pending

- Inspect the running widget at normal and increased UI scale, on wide and
  narrow available screen areas, and on multiple monitors where available.
- Compare every drawn Air75 V3 key and knob control against the physical board
  and CLI index map. Correct spacing, widths, labels, and index associations.
- Check that the matrix fallback, position selector, action footer, pending list, and search
  results remain reachable without clipping or unreadable text.
- Check Tab, Enter/Space, arrow navigation, focus on reopen, and Escape ordering
  across dropdowns, the assignment picker, and the outer popup.
- Check selected, modified-from-factory, pending, conflicting, busy, and stale
  states. Keep meanings distinguishable without relying only on color.
- Check right-to-left text layout while retaining physical keyboard order.
- Show a clear success/no-change result and actionable failure information.

Acceptance: record the checked display/scale configurations and capture the
final UI for review. Resolve any QML warnings caused by these interactions.

### 5. Hardware and release — readback verified; manual checks pending

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
- PR #2 is merged. Finish the acceptance record, review the merged implementation,
  rerun affected checks after any fixes, then prepare release notes, tagging,
  and publication as separate explicit release actions.

Coverage follow-up before closing acceptance: audit which intended paths have
integration evidence, particularly worker death during an operation, delayed
responses, changed geometry/reused device paths, lighting/theme events during
keymap work, and full keyboard-driven popup interactions. Existing unit or helper
coverage should not be recorded as a completed end-to-end check without evidence.

Release gate: close the outstanding checks in the validation record, establish
that there are no unresolved write/recovery defects, and document remaining
device/layout limitations. The gate remains open for manual acceptance.

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
- **Additional physical layouts:** use the merged issue template to collect
  model/variant, geometry, and full-board references. Add each verified physical
  index/geometry definition with selection and label coverage; use the existing
  matrix view until that model is verified.
- **Automatic profiles, full-layout profile replacement, persistent unfinished
  drafts, and backup retention policies:** design separately after the explicit
  workflows have been exercised in practice.

## Remaining delivery order

1. Complete 0.3.0 physical keypress/knob and unplug/reconnect acceptance, restoring
   and comparing the full baseline after any test writes.
2. Complete anchored-popup, multi-monitor, RTL and keyboard-navigation acceptance;
   capture final themed screenshots and fix any findings.
3. Audit outstanding integration scenarios above, adding targeted coverage where
   needed. Update the validation record with evidence rather than assumptions.
4. Finish 0.3.0 release notes and publication steps after the acceptance gate closes.
5. Begin 0.4.0 with common operation previews, CLI capability checks and backup
   metadata, then TOML import/export, named profiles, reviewed backup restore,
   and mode-scoped factory reset, in that dependency order.
6. Complete the 0.4.0 tests, visual review, hardware acceptance and release record.

Keep focused tests with each behavioral change. Each release should be validated
and usable before beginning the next release's feature work. Layout requests can
be collected now; the matrix fallback is already available on main.
