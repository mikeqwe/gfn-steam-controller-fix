# Technical notes

## Input path observed on the test machine

```text
Steam Controller (28de:1304)
        |
        v
     steam_osx
        |
        v
IOHIDUserDevice "GamePad-1" (Virtual, Microsoft, 045e:028e)
        |
        +--> unmodified GFN: GameController.framework -> input not usable
        |
        `--> patched GFN: native HID backend -> standard gamepad ID 0 -> stream
```

IORegistry identified `steam_osx` as the creator of the virtual device. A
read-only `IOHIDManager` probe matched `045e:028e` and received live axis and
button values, including button usage `0x0001` for the mapped A button. This
rules out a placeholder-only virtual device.

## Relevant GFN behavior

GFN logs to `~/Library/Application Support/NVIDIA/GeForceNOW/geronimo.log`. The
unmodified app initialized its native GameController backend and logged:

```text
Enabled GameController.framework backend
Not handling device ... via HID because GameController will take it.
```

It then exposed Steam's `GamePad-1` through the Apple backend with a different
effective product identity and registered a standard gamepad, but the streamed
game did not receive usable input.

With `GCDeviceInit()` returning false, the same GFN build instead logged:

```text
Device Changed 45e 28e 0 1
handleNewGamepad: standard gamepad at effective ID: 0
```

Controller navigation then worked in both the GFN interface and streamed games.

## Why SDL is not part of the final fix

GFN `2.0.86.124` ships SDL `2.32.10`, which does not contain the newer direct
Steam Controller `28de:1304` HIDAPI driver. SDL 3.4.10 can read that hardware
directly, and `sdl2-compat` can expose it through the SDL2 ABI.

That experiment proved direct controller support but did not solve GFN because
GFN's controller pipeline selected its native Forge/GameController backend
instead of SDL joystick input. The final build therefore keeps NVIDIA's stock
SDL2 and changes only GameController backend initialization.

## Patch mechanics

The arm64 function currently begins with a standard stack-frame prologue:

```text
ff c3 00 d1  f4 4f 01 a9
```

The patch replaces those eight bytes with:

```text
00 00 80 52  c0 03 5f d6
```

which disassembles to:

```asm
mov w0, #0
ret
```

The builder resolves the function address dynamically, translates the Mach-O
virtual address to a file offset, and refuses any binary whose original bytes do
not match. This is intentionally narrower than searching for a byte sequence.

## Haptic bridge

GFN's HID backend did not advertise force feedback for Steam's virtual
`045e:028e` device, even though the streamed session delivered rumble commands.
The arm64 patch therefore makes `_Forge_isRumbleSupported` return true and
replaces `_Forge_setRumbleState` with a bounded stub that resolves
`HIDSetRumbleTypeSine` through `dlsym`.

The replacement `libGeronimo.dylib` exports that bridge and re-exports the
patched original as `libGeronimo.original.dylib`. The bridge runs only in the
main `GeForceNOW` process, opens physical Steam Controller interfaces matching
`28de:1304`, maps GFN's 8-bit motor levels to 16-bit amplitudes, and sends this
ten-byte output report:

```text
80 00 00 00 LL LL 00 HH HH 00
```

Changed motor states are forwarded immediately. While a state remains active,
the bridge refreshes the unchanged report on a 40 ms watchdog interval until
GFN's requested duration ends; an explicit zero-amplitude command or the
deadline stops both motors. The watchdog interval is measured from the start of
the preceding HID write, so the write's own latency does not accumulate into
the refresh period. This follows the timing model in
[SDL's Steam Triton driver](https://github.com/libsdl-org/SDL/blob/cc2713c0477118d3074b625abe8df7de7118fe2e/src/joystick/hidapi/SDL_hidapi_steam_triton.c),
which sends changed states directly and uses 40 ms only for hardware-watchdog
refreshes. Unit tests cover amplitude mapping, report encoding, watchdog
scheduling, the arm64 stub, idempotence, and rejection of unknown function
bytes. On the tested machine, vibration was directly felt during a streamed
game.

A runtime trace of GFN `2.0.87.130` observed motor levels from 0 through 231, so
the bridge maps the full 0-255 range.

From `2.0.86.124` to `2.0.88.129`, only the relocation-dependent `adrp` and `bl`
instructions changed in the two 64-byte haptic functions; control flow and
symbol layout stayed the same. The patcher keeps each inspected pair as a
separate exact signature instead of masking those instructions, and rejects
mixed or unknown pairs. Add a new pair only after its disassembly shows the same
control flow.

## Build and install

`install.zsh` builds from the official app at `/Applications/GeForceNOW.app`,
which must have a valid deep signature from NVIDIA team `6KR3T733EC` and GFN's
bundle identifier. The build copies it to a staging directory, patches the
arm64 slice of `libGeronimo.dylib` only if every patched function matches an
exact signature, leaves the x86_64 slice unchanged, adds the bridge, and
ad-hoc signs and verifies the result. The installer then stops GFN's resident
background container, refusing to run while a GFN window is open, replaces only
`/Applications/GeForceNOW-Steam-Controller.app`, verifies the installed copy,
and restores the previous copy if that fails. It adds no privileged helper or
background service.

GFN can also self-update the patched copy: the updater removes
`libGeronimo.original.dylib` and restores an ordinary `libGeronimo.dylib`. When
that copy is newer than the official app, `install.zsh` uses it as the
read-only build source. A copy that still has `libGeronimo.original.dylib` is
never used.

`make check` runs syntax checks and unit tests. `./build.zsh [source-app]
[output-app]` builds without installing and keeps each previous output as a
`.previous-*` copy.

## Input Monitoring

Re-signing a rebuilt app can invalidate its previous Input Monitoring approval.
Gamepad input still works and GFN still dispatches rumble, but
`IOHIDManagerOpen` cannot open the physical controller. The bridge checks
`kIOHIDRequestTypeListenEvent` and requests access once when needed. On the
tested macOS release, `ListenEvent` does not display a normal permission
prompt; the user has to enable GeForce NOW in System Settings and relaunch.

The installer compares the installed and staged apps' designated code
requirements. If they differ, it runs only
`tccutil reset ListenEvent com.nvidia.gfnpc.mall` after the new copy passes
installed verification. This clears a stale decision but does not grant access;
`repair-input-monitoring.zsh` runs the same reset on demand. The official and
patched copies share NVIDIA's bundle identifier, so they share this decision.

## Resident BackgroundAgent collision

GFN intentionally keeps `GeForceNOWContainer` alive after the main window
closes. When a container from another GFN app copy owns
`ReliabilityMonitor/inst.lck` and the local message-bus port, the new copy's
mandatory `GfnBackgroundAgent` fails initialization. The UI reports
`backgroundagent: TimedOut` after 60 seconds and displays the generic **Problem
Detected** dialog even while streaming continues.

`reset-gfn-container.zsh` stops the user's resident containers when no GFN
window or streamer is running and checks that no process still holds the lock.
Verified live: after the reset, the failing state changed from `TimedOut` to
`Success`, and the new container reached both `Initialized` and `Started`.

## Known side effects and future direction

The current workaround disables the GameController backend globally inside the
patched GFN process. A more surgical future implementation could exclude only
Steam's virtual `045e:028e` device from `GCHandlesDevice()` while preventing
duplicate registration. Such a change needs testing with Xbox, DualSense, and
other controllers before it can replace the current known-working patch.

The haptic bridge currently handles only controller ID 0 and the two main rumble
channels. Trigger-specific haptics are accepted by the ABI but ignored. Both
haptic patches apply to every controller: `_Forge_isRumbleSupported` reports
rumble for all of them, and the replaced `_Forge_setRumbleState` contained the
only code reference to GFN's stock `_DEV_setRumble` in the inspected
`2.0.87.131` binary. Other gamepads therefore do not vibrate in the patched
copy.
