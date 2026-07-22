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

The unmodified app initialized its native GameController backend and logged:

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
`28de:1304`, maps GFN's 0-30 motor levels to 16-bit amplitudes, and sends this
ten-byte output report:

```text
80 00 00 00 LL LL 00 HH HH 00
```

Active reports are refreshed every 40 ms until GFN's requested duration ends;
a zero-amplitude report then stops both motors. Unit tests cover amplitude
mapping, report encoding, the arm64 stub, idempotence, and rejection of unknown
function bytes. On the tested machine, vibration was directly felt during a
streamed game.

GFN `2.0.87.130` moved the relevant code and changed the relocation-dependent
`adrp` and `bl` encodings in both 64-byte haptic functions. Their control flow
and symbol layout remained the same. The patcher accepts the newly inspected
64-byte pair as a separate exact signature; it does not mask those changing
instructions or accept arbitrary function bodies.

Re-signing the updated app can invalidate its previous Input Monitoring
approval. In that state gamepad input still works, GFN still dispatches rumble,
but `IOHIDManagerOpen` cannot open the physical controller. The bridge checks
`kIOHIDRequestTypeListenEvent` and requests access once when needed. The user
must grant Input Monitoring and relaunch the patched app before vibration can
resume.

## Resident BackgroundAgent collision

GFN intentionally keeps `GeForceNOWContainer` alive after the main window
closes. When a container from another GFN app copy owns
`ReliabilityMonitor/inst.lck` and the local message-bus port, the new copy's
mandatory `GfnBackgroundAgent` fails initialization. The UI reports
`backgroundagent: TimedOut` after 60 seconds and displays the generic **Problem
Detected** dialog even while streaming continues.

`reset-gfn-container.zsh` is a narrowly scoped troubleshooting utility for this
cross-copy collision. It will not terminate an active GFN window or streamer,
does not launch an app, and verifies that no container or reliability-lock
holder remains. After the reset, the user opens the desired app normally. The
behavior was verified live: the failing state changed from `TimedOut` to
`Success`, and the new container reached both `Initialized` and `Started`.

## Known side effects and future direction

The current workaround disables the GameController backend globally inside the
patched GFN process. A more surgical future implementation could exclude only
Steam's virtual `045e:028e` device from `GCHandlesDevice()` while preventing
duplicate registration. Such a change needs testing with Xbox, DualSense, and
other controllers before it can replace the current known-working patch.

The haptic bridge currently handles only controller ID 0 and the two main rumble
channels. Trigger-specific haptics are accepted by the ABI but ignored.
