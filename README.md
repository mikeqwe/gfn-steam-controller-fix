# Steam Controller (2026) gamepad fix for GeForce NOW on macOS

If your Steam Controller works as mouse and keyboard input or in the GeForce NOW
menu but is not detected as a gamepad inside streamed games on macOS, this
project builds a separate, locally signed GFN app that routes Steam Input's
virtual Xbox controller through GFN's HID backend.

The fix was validated end to end on an Apple Silicon Mac: controller input works
in the GeForce NOW interface and inside streamed games, with vibration during
streamed gameplay. The original GFN app, Steam installation, and controller
firmware are not modified. SIP stays enabled, and no kernel extension or
DriverKit driver is installed.

> [!WARNING]
> This is an independent compatibility workaround, not an NVIDIA or Valve
> product. It patches a local copy of proprietary software. Using a modified
> GeForce NOW client may violate the
> [GeForce NOW Terms of Use](https://www.nvidia.com/en-us/geforce-now/terms-of-use/)
> and may result in suspension or termination of your GFN account. Review the
> code and the limitations below before using it.

## Tested configuration

- GeForce NOW `2.0.88.129`
- macOS `26.5.2` on a Mac mini (M4)
- Steam Controller hardware `28de:1304`
- Steam virtual `GamePad-1` HID `045e:028e`

GFN `2.0.86.124` and `2.0.87.130`/`2.0.87.131` are also covered by exact
instruction signatures. Other versions work only if their input and haptic
functions match one of these signatures; otherwise the build stops before
anything is installed.

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
- the official GeForce NOW app at `/Applications/GeForceNOW.app` for the
  initial installation;
- Steam running with a controller layout that emits gamepad controls; this
  project cannot create gamepad input from a layout that only emits mouse and
  keyboard input;
- Xcode Command Line Tools (`xcode-select --install`).

The installer may request an administrator password because the patched app is
placed in the system `/Applications` folder. It does not add a privileged
helper or background service.

## Quick start

```sh
git clone https://github.com/mikeqwe/gfn-steam-controller-fix.git
cd gfn-steam-controller-fix
./install.zsh
open "/Applications/GeForceNOW-Steam-Controller.app"
```

The patched copy appears in **Applications** as `GeForceNOW-Steam-Controller`,
next to the official `NVIDIA GeForce NOW` app. Open it for Steam Controller
sessions, and keep the official app installed: it is the clean source for
builds and updates.

Vibration needs **Input Monitoring**. After the first launch, enable GeForce NOW
under **System Settings → Privacy & Security → Input Monitoring**, then quit and
reopen the patched app. macOS may not show a prompt. Without this permission,
input works but the controller does not vibrate.

## What the installer and builder do

1. Selects an unpatched source: the official app, or the patched copy after
   GFN's updater has restored its original files and made it newer. The source
   must have a valid deep signature from NVIDIA team `6KR3T733EC` and GFN's
   bundle identifier.
2. Copies the source to a staging directory and sets its Finder name to
   `GeForceNOW-Steam-Controller`.
3. Checks `_GCDeviceInit` and GFN's two rumble functions in the arm64 slice of
   `libGeronimo.dylib` against known instruction signatures, then makes
   `_GCDeviceInit` return false, makes GFN advertise rumble support, and
   redirects its rumble callback to a small local HID bridge. The x86_64 slice
   is not changed.
4. Adds the bridge as a re-exporting `libGeronimo.dylib`; the patched original
   remains beside it as `libGeronimo.original.dylib`.
5. Ad-hoc signs the staged app and runs strict deep signature verification.
6. Refuses to continue while GFN is running, stops GFN's resident background
   container, replaces only `/Applications/GeForceNOW-Steam-Controller.app`,
   verifies the installed copy, and restores the previous copy if replacement
   or verification fails.
7. If the app's designated code requirement changed, resets only GFN's stale
   Input Monitoring decision.

The official app is never patched in place, and nothing is downloaded.

## Verify an installed build

```sh
./verify.zsh
```

The verifier is read-only. It confirms the patched instructions, the haptic
bridge and its re-exported original library, the Finder display name, and the
full app signature.

GFN's log, normally
`~/Library/Application Support/NVIDIA/GeForceNOW/geronimo.log`, should contain
these lines after launch:

```text
Device Changed 45e 28e 0 1
handleNewGamepad: standard gamepad at effective ID: 0
```

It should not contain `Enabled GameController.framework backend` for that
launch.

## Troubleshooting: input works, but vibration does not

A rebuilt app has a new ad-hoc signature, which can invalidate the previous
Input Monitoring approval: input still works, but the haptic bridge cannot open
the physical Steam Controller. `install.zsh` normally resets this stale decision
itself. If vibration still does not work:

1. Quit every GeForce NOW window.
2. Run `./repair-input-monitoring.zsh`.
3. In the System Settings pane it opens, enable **GeForce NOW** under
   **Privacy & Security → Input Monitoring**. macOS may not show a prompt.
4. Quit and reopen the patched app, then retest vibration.

The utility resets only GFN's Input Monitoring (`ListenEvent`) decision; it does
not reset microphone, camera, Accessibility, or other privacy permissions. The
official and patched copies use the same NVIDIA bundle identifier, so they share
this decision.

## Troubleshooting: "Problem Detected" after launch

GFN leaves `GeForceNOWContainer` running after its window closes. If that
resident process belongs to the official app or another patched copy, a newly
launched copy can time out while loading the mandatory `GfnBackgroundAgent` and
show a generic **Problem Detected** dialog. This is not part of the controller
fix.

Quit every GeForce NOW window, run `./reset-gfn-container.zsh`, and open the
desired GFN app again. The script refuses to run while a GFN window or streamer
is active, stops only your own `GeForceNOWContainer` processes, and does not
modify or launch an application.

## Updating GeForce NOW

1. Let either the official or patched copy finish its normal GFN update.
2. Quit every GeForce NOW window.
3. Run `git pull` in this repository. New GFN releases may need signatures
   that only a newer revision contains.
4. Run `./install.zsh` again and follow its final instructions. It uses the
   official app when it is current, or the self-updated patched copy when that
   copy is newer and has lost its patch.
5. Open the patched app and test the GFN interface, one streamed game, and
   vibration.

If the build stops with `refusing patch: unexpected instructions`,
`refusing haptic patch: unexpected function bytes`, or `Unexpected Forge rumble
function layout`, this revision of the repository does not support the
installed GFN version. The installer replaces nothing in that case, but a
patched copy that GFN has already self-updated stays unpatched until support is
added. If `git pull` brings no newer revision, open a
[bug report](https://github.com/mikeqwe/gfn-steam-controller-fix/issues/new/choose)
with the GFN version and the installer output.

## Limitations

- The fix disables `GameController.framework` for **all controllers used by the
  patched GFN copy**, not only Steam Controller. Other controllers may lose
  platform-specific behavior.
- The rumble patch replaces GFN's rumble callback for every controller. The
  bridge forwards only GFN controller ID 0, and only to a physical Steam
  Controller `28de:1304`, so other gamepads do not vibrate in the patched copy.
  It maps the two main rumble motors; trigger-specific haptics are ignored.
- GFN's self-updater can remove the patch; repeat
  [Updating GeForce NOW](#updating-geforce-now) after each GFN update.
- Ad-hoc signing may cause macOS to ask for permissions again or treat the copy
  as a different local build.

## Uninstall

Quit every GeForce NOW window, then run:

```sh
./uninstall.zsh
```

The script removes only `/Applications/GeForceNOW-Steam-Controller.app`; the
official GFN app, Steam configuration, and shared GFN user data are not
changed.

## Development

`make check` runs syntax checks, compiles with warnings as errors, and runs the
unit tests.

`./build.zsh [source-app] [output-app]` builds without installing. By default
it reads `/Applications/GeForceNOW.app` and writes
`~/Applications/GeForceNOW-Steam-Controller.app`, which `install.zsh` does not
use. Each rebuild keeps the previous output beside it as
`GeForceNOW-Steam-Controller.app.previous-YYYYMMDD-HHMMSS`, a full copy of GFN
that is never removed automatically.

## License and trademarks

The original code in this repository is available under the [MIT License](LICENSE).
GeForce NOW, NVIDIA, Steam, Valve, Xbox, Apple, and macOS are trademarks of
their respective owners.
