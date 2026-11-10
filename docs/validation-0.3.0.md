# 0.3.0 validation record

This record describes the 0.3.0 implementation merged into `main` through
[PR #2](https://github.com/fldc/omarchy-nuphy/pull/2). Manual release acceptance
remains open; tagging and release publication have not been performed.

Automated result: **54 tests passed**, plugin validation passed, and Git whitespace
checks passed.

## Completed

- Structured per-key conflicts with original, current, and proposed values.
  Both resolution choices are draft-only; unresolved conflicts block the whole
  batch, and subsequent Apply checks again for external changes.
- Drafts remain detached across uncertain device changes. Compatible identified
  reconnects reconcile automatically; generic NuPhy serial strings do not count
  as unique identities. Explicit rebinding cannot bypass geometry/layout checks.
- Stateful fake CLI tests run the actual worker with temporary device discovery,
  selectors, TOML parsing, persisted mappings, backups, and partial-write errors.
- QML integration runs the actual service and two editors against the fake worker,
  chooses an assignment through the picker, clicks Apply, and verifies shared
  draft clearing and hardware readback. Other UI fixtures cover conflict
  resolution, stale editing, identified reconnect, and explicit rebinding.
- Existing lighting, timeout, backup failure, malformed data, and worker tests
  remain part of the suite. Tests never open real HID hardware.
- Wide (760 logical pixels), narrow (360), and 1.5x scale editor renders using
  live keyboard readings were inspected. A clipped action row was found and
  changed to a responsive grid. Current-mode initialization was also corrected.

## Layout follow-up

- The Air75 diagram now follows the supplied NuPhyIO reference's contiguous
  16-unit rows and right Shift width. It previews actual/pending assignments,
  distinguishes the knob press, and exposes full positions in tooltips.
- Unknown layouts use firmware matrix coordinates with separate extra entries,
  horizontal scrolling at narrow widths, and the position selector below.
  Matrix rendering was inspected at wide, narrow and 1.5x scale with a simulated
  unrecognized model. A width binding loop found in rendering was corrected.
- Matrix tests cover row/index mapping, zero-valued keys, pending labels, layer
  switches, selecting a horizontally scrolled column and extra entries.
- The layout-request URL is tested for encoding and its metadata allowlist. It
  opens a GitHub draft; tests do not open a browser or submit an issue.

## Hardware command acceptance

Target: NuPhy Air75 V3, firmware 1.0.23.6, vendor 0x19f5/product 0x1028,
control interface 3, usage page 1/usage 0. Current mode reported Windows.

The acceptance script held the lighting backend state lock to serialize against
background lighting writes. It read all 784 entries, then temporarily changed:

- Layer 0, index 12: Mac base F12 position.
- Layer 4, index 12: Windows base F12 position.
- Layer 4, indices 96 and 97: both knob rotation entries.

The batch applied with no CLI error and all four assignments matched readback.
A binary pre-apply backup was created. A second explicit batch restored the four
original values, after which **all 784 entries matched the initial baseline**.
No factory reset or complete-backup restore was performed.

This verifies protocol writes and readback. It does not verify physical keypress
or knob behavior: those require a person interacting with the keyboard.

## Remaining manual acceptance before publication

- Press the test key in each tested mode/layer and rotate the knob to confirm
  physical behavior, then verify restoration again.
- Physically unplug/reconnect and review the retained detached draft on this
  board, whose reported serial is the generic `NuPhy Keybord 0720`.
- Verify the actual anchored bar popup on multiple monitors, including reopen
  focus, dropdown navigation, Escape ordering, and touchpad scrolling.
- Compare the physical diagram's stagger and labels with the board. CLI indices
  are used for assignments; physical dimensions remain a visual approximation.
- Check an RTL desktop and a second layout/device if available. Unsupported
  physical layouts now use the schematic matrix view plus the position selector.
- Capture final themed screenshots, review the merged implementation, and prepare
  release notes. PR #2 is merged; tagging and publication remain outstanding.

The release gate remains open for these manual checks; automated success must
not be reported as physical desktop or keypress verification.

## Marketplace review follow-up — November 10, 2026

The fixes following review of commit `396c595` pass **62 tests**, plugin
validation, and Git whitespace checks. The marketplace update is tracked in
[request #14596](https://github.com/omacom/omarchy-plugin-marketplace/issues/14596).

- Both text fields route Ctrl+V, Shift+Insert, context-menu paste and middle-click
  PRIMARY paste through an asynchronous `wl-paste` helper. The transfer has a
  4 KiB byte cap and a two-second deadline before insertion into Qt; field lengths
  still apply. Replies are ignored after focus, text or selection changes.
- CLI stdout/stderr are drained concurrently through capped pipes (256 KiB
  lighting/discovery, 4 MiB keymap, 4 KiB stderr), replacing unbounded capture and
  temporary-file output. Overflow or timeout kills the command's process group.
- State/theme reads are isolated behind a one-second deadline. Opens use
  `O_NONBLOCK`, followed by a regular-file check and byte cap (64 KiB state,
  128 bytes theme). The unchanged-state comparison uses the same bounded path.
- The service clears busy/stale state and retries after five seconds when the
  worker's running flag clears, including `FailedToStart` without `exited`.
- New tests exercise infinite stdout/stderr, silent and streaming timeouts,
  inherited pipes, FIFOs, special files, malformed UTF-8, symlink reads, clipboard
  helper overflow/stalls, actual QML paste gestures and failed-start recovery.
  The existing fake-CLI apply/conflict/readback tests also pass.

Clipboard transfer tests use a fake `wl-paste`; UI tests run offscreen. No live
Wayland clipboard-owner attack, physical keyboard writes, or multi-monitor
acceptance was performed for this follow-up. `wl-paste` is a documented paste
runtime dependency; a missing executable leaves typed editing available.
