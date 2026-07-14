# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] - 2026-07-14

### Added

- fail-closed arm64 patches for GFN rumble capability and dispatch;
- a local HID bridge for physical Steam Controller vibration;
- unit tests for rumble mapping, report encoding, haptic patching, and reset
  utility argument validation;
- installer and uninstaller scripts for the standard system Applications
  folder, including installed-build verification and rollback;
- an opt-in troubleshooting utility that resets resident
  `GeForceNOWContainer` collisions without becoming the normal app launcher.

### Changed

- the verifier now checks the haptic patch, bridge re-export, original library,
  Finder display name, and deep app signature;
- the default bundle and Finder display name is now
  `GeForceNOW-Steam-Controller`;
- the normal installation path is now
  `/Applications/GeForceNOW-Steam-Controller.app`, so the patched copy appears
  in Finder's standard Applications folder;
- documentation now covers Input Monitoring, verified vibration, and GFN's
  mandatory BackgroundAgent timeout.

## [0.1.0] - 2026-07-14

### Added

- fail-closed arm64 patcher for GFN `_GCDeviceInit`;
- staged builder that preserves the official app and previous patched builds;
- read-only verifier for patch state and code signature;
- unit tests for unpatched, patched, idempotent, and rejected byte sequences;
- documentation of the verified Steam virtual-HID input path and limitations;
- macOS GitHub Actions workflow.
