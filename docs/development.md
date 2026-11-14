# Development

[← README](../README.md)

## Local installation

To load a local checkout instead of installing from GitHub:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/local.nuphy
omarchy plugin validate ~/.config/omarchy/plugins/local.nuphy
omarchy plugin enable local.nuphy
```

Run the symlink command from this project directory. Do not overwrite an existing
plugin with the same ID. Layout changes hot-reload; if plugin code stays cached,
run `omarchy restart shell`. Upgrading from 0.1.0 also requires a restart because
later versions add a service entry point.

## CLI override

For development, the worker accepts an explicit `NUPHYCTL` executable override in
the environment it inherits when launched, for example
`NUPHYCTL=/path/to/nuphyctl/target/debug/nuphyctl`. It applies consistently
to discovery, lighting, keymap and settings commands. The default remains
`nuphyctl` on PATH; the plugin never silently selects a local build. Start the
shell with that environment to use the development backend. The nuphyctl checkout
is a separate project and is not built or modified by this plugin.

## Validation

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

Tests include mocked hardware, actual worker-process protocol/event tests with a
stateful fake CLI, partial-write recovery, bounded I/O and paste, worker startup
recovery, shared QML service/editor behavior, and
offscreen Quickshell interaction tests. They never send HID
commands to your keyboard. The UI test requires installed Omarchy shell components
and Quickshell; it skips when these are unavailable. Sliders support Tab focus
and Left/Right arrow adjustment. Mouse-wheel and touchpad scrolling over sliders
scrolls the popup instead of changing lighting values.

English translations are in `i18n/en.json`;
other Omarchy languages fall back to English.

Release validation and remaining manual checks are recorded in
[0.3.0 validation record](validation-0.3.0.md). Future work is in
[ROADMAP.md](../ROADMAP.md).

Settings integration evidence is recorded in
[settings validation](settings-validation.md).
