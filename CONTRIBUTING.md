# Contributing

Contributions are welcome when they keep the project narrow, inspectable, and
fail-closed.

## Before opening a pull request

1. Explain the exact GFN version, macOS version, CPU architecture, and
   controller path tested.
2. Add or update tests for any patcher or installer behavior.
3. Run `make check`.
4. For a binary-signature update, document the disassembly and why the new
   instructions are semantically equivalent to the supported function.
5. Update `CHANGELOG.md` when user-visible behavior changes.

## Evidence standards

- Distinguish local controller enumeration from input inside a streamed game.
- Verify both the GFN interface and at least one streamed game.
- State clearly when a conclusion is inferred rather than directly observed.
- Do not broaden an instruction signature merely to make a new version pass.

## Do not submit

- NVIDIA or Valve binaries, app bundles, resources, or decompiled source;
- code-signing identities, credentials, tokens, or account identifiers;
- raw GFN logs containing user IDs, device IDs, session IDs, or URLs with
  credentials;
- generated `.app`, `.dylib`, object, or build-output files.

Sanitized log excerpts should contain only the lines required to support the
controller-path finding.

## Scope

The repository currently targets Apple Silicon, Steam's virtual Xbox HID, and
physical Steam Controller rumble. Intel support, per-device GameController
filtering, additional controllers, and trigger-specific haptics are welcome only
with reproducible tests and explicit limitations.
