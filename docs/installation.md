# Installation

[← README](../README.md)

Requires Omarchy’s Quickshell-based shell, Python 3 and
[`nuphyctl`](https://github.com/fldc/nuphyctl) on PATH. Keyboard settings require
**nuphyctl 0.7.0 or newer**.
**Manual setup is required:** installing this plugin does not install its CLI
dependency or grant access to the keyboard's HID control interface.
Clipboard paste uses `wl-paste` from `wl-clipboard` (included with Omarchy);
normal typing and the color picker remain available if it is missing.

Install `nuphyctl` from the AUR using the
[`nuphyctl-bin`](https://aur.archlinux.org/packages/nuphyctl-bin) package:

```bash
omarchy pkg aur add nuphyctl-bin
```

The documented `nuphyctl-bin` package version is **`0.7.0-1`**, built from
[`nuphyctl v0.7.0`](https://github.com/fldc/nuphyctl/releases/tag/v0.7.0).
That release includes signed build provenance for both architectures' executables
and archives; see the [upstream verification instructions](https://github.com/fldc/nuphyctl/blob/64f0dd5267dd3a3da1bae486753609a23d39f832/docs/releases.md).

Check the installed package with `pacman -Q nuphyctl-bin`; settings need
`0.7.0-1` or newer. AUR metadata can briefly lag a newly pushed package version.
The package version describes the documented release, not an exact-version pin.

The package also installs architecture-specific third-party license notices under
`/usr/share/licenses/nuphyctl-bin/THIRD-PARTY-NOTICES/`, including the bundled
HIDAPI implementation and Rust standard-library attributions.

The package installs a udev rule
that grants the active local seat access to NuPhy hidraw devices. After installing
or updating it, disconnect and reconnect the keyboard while logged into your
local desktop session. Run Omarchy and `nuphyctl` as your normal user, not root.
For source builds or other CLI installation methods, follow the
[upstream device-permissions instructions](https://github.com/fldc/nuphyctl/blob/master/docs/setup.md#linux-device-permissions).

The permission grants HID device access, not a lighting-only permission. Other
programs running as your account may use that access too. This plugin invokes
device enumeration, validated lighting, keymap and settings commands with explicit
interface selectors. Keymap writes require **Apply changes** and keyboard settings
writes require **Apply settings**; it never
invokes raw-report commands. The plugin itself
does not install udev rules, elevate privileges, or change device permissions.
An empty capability list from an automated marketplace scan does **not** mean
that the external CLI and device-permission setup are unnecessary.

Install and enable the plugin directly from GitHub:

```bash
omarchy plugin add https://github.com/fldc/omarchy-nuphy.git --enable
```

This installs the plugin and adds its keyboard icon to the bar. If you install
without `--enable`, enable it later with:

```bash
omarchy plugin enable local.nuphy
```

After upgrading to 0.3.0, restart the shell so the persistent worker loads the
keymap backend:

```bash
omarchy restart shell
```

## Disable or remove

Disable the plugin without uninstalling it:

```bash
omarchy plugin disable local.nuphy
```

Remove an installed plugin:

```bash
omarchy plugin remove local.nuphy
```

Disabling or removing stops the plugin's automatic sync; it does not restore
previous keyboard colors. Saved preferences in
`~/.local/state/omarchy-nuphy/` are retained. The plugin does not install udev
rules or overwrite other application settings. Applied keymaps remain on the
keyboard after the plugin is removed.
