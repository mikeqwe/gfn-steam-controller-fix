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

## Known side effects and future direction

The current workaround disables the GameController backend globally inside the
patched GFN process. A more surgical future implementation could exclude only
Steam's virtual `045e:028e` device from `GCHandlesDevice()` while preventing
duplicate registration. Such a change needs testing with Xbox, DualSense, and
other controllers before it can replace the current known-working patch.

Haptics remain outside the verified scope. The HID path reported no force-
feedback reference on the tested virtual device.
