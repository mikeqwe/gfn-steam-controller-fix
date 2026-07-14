# Steam Controller (2026) gamepad fix for GeForce NOW on macOS

If your Steam Controller works as mouse and keyboard input or in the GeForce NOW
menu but is not detected as a gamepad inside streamed games on macOS, this
project builds a separate, locally signed GFN app that routes Steam Input's
virtual Xbox controller through GFN's HID backend.

The fix was validated end to end on an Apple Silicon Mac: controller input works
in the GeForce NOW interface and inside streamed games, with vibration during
streamed gameplay. The original GFN app, Steam installation, controller
firmware, and macOS system security settings are not modified.

> [!IMPORTANT]
> This is an independent compatibility workaround, not an NVIDIA or Valve
> product. It patches a local copy of proprietary software. Review the code and
> the limitations below before using it.

> [!WARNING]
> Using a modified GeForce NOW client may violate the
> [GeForce NOW Terms of Use](https://www.nvidia.com/en-us/geforce-now/terms-of-use/)
> and may result in suspension or termination of the user's GFN account. Users
> are responsible for evaluating the terms and laws that apply to them.

## Tested configuration

- GeForce NOW `2.0.86.124`
- macOS `26.5.2` on Apple Silicon
- Steam Controller hardware `28de:1304`
- Steam virtual `GamePad-1` HID `045e:028e`
- GFN interface input: working
- streamed-game input: working
- vibration during streamed gameplay: working

Other GFN versions may work only when their `_GCDeviceInit` prologue matches the
verified instruction signature. The builder fails closed when it does not.

## Why this is needed

Steam already creates a valid virtual Xbox-compatible HID device on macOS. On
the tested setup it emits live axes and button reports correctly. Unmodified GFN
detects that device through Apple's `GameController.framework`, suppresses its
own HID path, and does not deliver usable gamepad input to the cloud game.

The patched copy disables GFN's GameController backend initialization. GFN then
opens the same Steam virtual controller through its HID backend as `045e:028e`
and forwards it as a standard gamepad.

See [Technical notes](docs/technical-notes.md) for the evidence and data flow.

## Common symptoms and questions

### GFN menu works, but streamed games do not

This is one form of the verified failure. Desktop mouse and keyboard bindings
can still control the GFN interface even when the virtual gamepad is not being
forwarded to the streamed game. The patched copy routes that gamepad through
GFN's HID backend instead.

### The controller only acts as a mouse and keyboard

First choose a Steam layout that emits gamepad controls. This project fixes the
GFN side of the path; it cannot create gamepad reports when the active Steam
layout only emits desktop input.

### Steam Input's virtual gamepad is not detected

The tested virtual device appears as Xbox-compatible HID `045e:028e`. The
builder addresses the case where Steam creates that device successfully but
the native GFN client does not forward its reports as usable gamepad input.

### Does this require disabling System Integrity Protection?

No. SIP can remain enabled. The project patches and ad-hoc signs a separate
copy of GFN in user space; it does not install a kernel extension or DriverKit
driver.

## Requirements

- an Apple Silicon Mac;
- the official GeForce NOW app at `/Applications/GeForceNOW.app`;
- Steam running with the controller configured to expose a virtual gamepad;
- Xcode Command Line Tools (`cc`, `lipo`, `nm`, `otool`, and `codesign`).

The installer may request an administrator password because the patched app is
placed in the system `/Applications` folder.

macOS may ask for **Input Monitoring** when the haptic bridge first opens the
physical Steam Controller. Grant access to the patched GFN copy and relaunch it.

CMake, a kernel extension, a DriverKit driver, a root shell, and disabling SIP
are not required. The installer does not add a privileged helper or background
service.

## Quick start

```sh
./install.zsh
open "/Applications/GeForceNOW-Steam-Controller.app"
```

The installer builds and verifies the patched copy, then places it here:

```text
/Applications/GeForceNOW-Steam-Controller.app
```

It appears in Finder's standard **Applications** folder with the display name
`GeForceNOW-Steam-Controller`, next to but distinct from the official
`NVIDIA GeForce NOW` app. Open the patched app for Steam Controller sessions;
keep the official app installed because it is the clean source for builds and
updates.

For a low-level custom build, `build.zsh` accepts source and output paths as
positional arguments:

```sh
./build.zsh /Applications/GeForceNOW.app \
  "$HOME/Applications/GeForceNOW-Steam-Controller.app"
```

Running `build.zsh` without arguments writes to
`~/Applications/GeForceNOW-Steam-Controller.app`. This developer-oriented path
is not used by `install.zsh`.

## What the installer and builder do

1. Copies the official GFN app to a staging directory.
2. Extracts the arm64 slice of `libGeronimo.dylib`.
3. Resolves `_GCDeviceInit` from the Mach-O symbol table.
4. Verifies its first eight bytes against the known instruction signature.
5. Replaces the function entry with `mov w0, #0; ret`.
6. Recombines the patched arm64 slice with the untouched x86_64 slice.
7. Makes GFN advertise rumble support and redirects its arm64 rumble callback
   to a small local HID bridge.
8. Adds the bridge as a re-exporting `libGeronimo.dylib`; the patched original
   remains beside it as `libGeronimo.original.dylib`.
9. Sets the Finder display name to `GeForceNOW-Steam-Controller` in the main
   and localized bundle metadata.
10. Ad-hoc signs the staged app and runs strict deep signature verification.
11. The installer resets a safe-to-stop resident GFN container, replaces only
    `/Applications/GeForceNOW-Steam-Controller.app`, and verifies the installed
    copy.
12. If replacement or final verification fails, the installer restores the
    previously installed patched copy.

The official app is never patched in place. The builder has no network access
and downloads nothing.

## Verify an installed build

```sh
./verify.zsh
```

The verifier is read-only. It confirms the patched instructions, the haptic
bridge and its re-exported original library, the Finder display name, and the
full app signature.

GFN's local log should contain these lines after launch:

```text
Device Changed 45e 28e 0 1
handleNewGamepad: standard gamepad at effective ID: 0
```

It should not contain this line for the current launch:

```text
Enabled GameController.framework backend
```

The log is normally located at:

```text
~/Library/Application Support/NVIDIA/GeForceNOW/geronimo.log
```

## Troubleshooting: "Problem Detected" after launch

GFN leaves `GeForceNOWContainer` running after its window closes. If that
resident process belongs to the official app or another patched copy, a newly
launched copy can time out while loading the mandatory `GfnBackgroundAgent` and
show a generic **Problem Detected** dialog.

This is not part of the controller fix and does not require a special everyday
launcher. If the dialog appears:

1. Quit every GeForce NOW window.
2. Reset the resident background container:

```sh
./reset-gfn-container.zsh
```

3. Open the desired GFN app normally from Finder, Dock, or with `open`.

The reset script does not modify or launch an application. It refuses to run
while a GFN window or streamer is active, stops only same-user
`GeForceNOWContainer` processes, and verifies that the reliability lock is no
longer held. Use it only for this dialog or a confirmed cross-copy container
conflict.

## Updating GeForce NOW

1. Update the official app normally.
2. Quit every GeForce NOW window.
3. Run `./install.zsh` again.
4. Open `/Applications/GeForceNOW-Steam-Controller.app` normally.
5. Test the GFN interface and one streamed game.

The installer temporarily preserves the previous patched copy and removes that
backup only after the newly installed copy passes verification. Direct custom
builds made with `build.zsh` retain their previous output as
`GeForceNOW-Steam-Controller.app.previous-YYYYMMDD-HHMMSS`.

If NVIDIA changes `_GCDeviceInit`, the builder stops on `unexpected
instructions`. Do not weaken that check blindly; inspect and document the new
function before updating the signature.

## Limitations

- The fix disables `GameController.framework` for **all controllers used by the
  patched GFN copy**, not only Steam Controller. Other controllers may lose
  platform-specific behavior.
- Only arm64 is patched. The preserved x86_64 slice does not contain the fix.
- The haptic bridge targets the physical Steam Controller `28de:1304` and GFN
  controller ID 0. It maps the two main rumble motors; trigger-specific haptics
  are currently ignored.
- Vibration is sent directly to the physical controller. Other gamepads keep
  using GFN's stock HID behavior and are outside the haptic bridge's scope.
- GFN's self-updater may replace patched files. Re-run the builder and verifier
  after any update or unexpected regression.
- The instruction signature is version-sensitive by design.
- Ad-hoc signing may cause macOS to ask for permissions again or treat the copy
  as a different local build.

## Uninstall

Quit every GeForce NOW window, then run:

```sh
./uninstall.zsh
```

The script removes only
`/Applications/GeForceNOW-Steam-Controller.app`. It does not remove or modify
the official GFN app, Steam configuration, shared GFN user data, permissions,
drivers, services, or daemons.

## Development

```sh
make check         # syntax check, compile with warnings as errors, unit tests
make install-app   # build, verify, and install into /Applications
make uninstall-app # remove only the installed patched copy
make build-app     # low-level build into the user Applications folder
make verify-app    # verify the system-installed patched copy
make clean
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Never commit
NVIDIA binaries, application bundles, authentication material, or unsanitized
GFN logs.

## License and trademarks

The original code in this repository is available under the [MIT License](LICENSE).
GeForce NOW, NVIDIA, Steam, Valve, Xbox, Apple, and macOS are trademarks of
their respective owners. See [NOTICE](NOTICE).
