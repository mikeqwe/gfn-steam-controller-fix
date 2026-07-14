# GeForce NOW Steam Controller fix for macOS

Build a separate, locally signed GeForce NOW app that accepts Steam's virtual
Xbox gamepad through GFN's HID backend.

The fix was validated end to end on an Apple Silicon Mac: controller input works
in the GeForce NOW interface and inside streamed games. The original GFN app,
Steam installation, controller firmware, and macOS system security settings are
not modified.

> [!IMPORTANT]
> This is an independent compatibility workaround, not an NVIDIA or Valve
> product. It patches a local copy of proprietary software. Review the code and
> the limitations below before using it.

## Tested configuration

- GeForce NOW `2.0.86.124`
- macOS `26.5.2` on Apple Silicon
- Steam Controller hardware `28de:1304`
- Steam virtual `GamePad-1` HID `045e:028e`
- GFN interface input: working
- streamed-game input: working

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

## Requirements

- an Apple Silicon Mac;
- the official GeForce NOW app at `/Applications/GeForceNOW.app`;
- Steam running with the controller configured to expose a virtual gamepad;
- Xcode Command Line Tools (`cc`, `lipo`, `nm`, `otool`, and `codesign`).

CMake, a kernel extension, a DriverKit driver, root access, and disabling SIP
are not required.

## Quick start

```sh
make check
./build.zsh
./verify.zsh
open "$HOME/Applications/GeForceNOW-SteamHID.app"
```

The default output is:

```text
~/Applications/GeForceNOW-SteamHID.app
```

Custom source and output paths are positional arguments:

```sh
./build.zsh /Applications/GeForceNOW.app \
  "$HOME/Applications/GeForceNOW-SteamHID.app"
```

## What the builder does

1. Copies the official GFN app to a staging directory.
2. Extracts the arm64 slice of `libGeronimo.dylib`.
3. Resolves `_GCDeviceInit` from the Mach-O symbol table.
4. Verifies its first eight bytes against the known instruction signature.
5. Replaces the function entry with `mov w0, #0; ret`.
6. Recombines the patched arm64 slice with the untouched x86_64 slice.
7. Ad-hoc signs the staged app and runs strict deep signature verification.
8. Installs the verified copy and preserves any previous build as a timestamped
   backup.

The official app is never patched in place. The builder has no network access
and downloads nothing.

## Verify an installed build

```sh
./verify.zsh
```

The verifier is read-only. It confirms the patched instructions and validates
the full app signature.

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

## Updating GeForce NOW

1. Update the official app normally.
2. Quit the patched copy.
3. Run `./build.zsh` again.
4. Run `./verify.zsh`.
5. Test the GFN interface and one streamed game.

The old patched copy is retained as
`GeForceNOW-SteamHID.app.previous-YYYYMMDD-HHMMSS`.

If NVIDIA changes `_GCDeviceInit`, the builder stops on `unexpected
instructions`. Do not weaken that check blindly; inspect and document the new
function before updating the signature.

## Limitations

- The fix disables `GameController.framework` for **all controllers used by the
  patched GFN copy**, not only Steam Controller. Other controllers may lose
  platform-specific behavior.
- Only arm64 is patched. The preserved x86_64 slice does not contain the fix.
- Force feedback and haptics are not confirmed. The tested GFN log reported no
  force-feedback support for the Steam virtual HID.
- GFN's self-updater may replace patched files. Re-run the builder and verifier
  after any update or unexpected regression.
- The instruction signature is version-sensitive by design.
- Ad-hoc signing may cause macOS to ask for permissions again or treat the copy
  as a different local build.

## Uninstall

Quit and remove `~/Applications/GeForceNOW-SteamHID.app` and any timestamped
backups. No system service, driver, daemon, or privileged helper is installed.

## Development

```sh
make check       # syntax check, compile with warnings as errors, unit tests
make build-app   # build the local patched GFN copy
make verify-app  # verify the installed copy
make clean
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Never commit
NVIDIA binaries, application bundles, authentication material, or unsanitized
GFN logs.

## License and trademarks

The original code in this repository is available under the [MIT License](LICENSE).
GeForce NOW, NVIDIA, Steam, Valve, Xbox, Apple, and macOS are trademarks of
their respective owners. See [NOTICE](NOTICE).
