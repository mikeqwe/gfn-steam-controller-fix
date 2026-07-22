# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.2.1] - 2026-07-22

### Changed

- add exact haptic-function signatures for GeForce NOW `2.0.87.130` while
  retaining fail-closed rejection of unknown binaries;
- explicitly request Input Monitoring when an updated ad-hoc build no longer
  has permission to open the physical Steam Controller for vibration;
- document the app-scoped `tccutil` recovery used when macOS retains a stale
  Input Monitoring denial after an update;
- list GeForce NOW `2.0.87.130` as the current tested release;
- the README now leads with the affected Steam Controller (2026) symptoms and
  answers common gamepad-routing questions.

## [0.2.0] - 2026-07-14

### Added

- fail-closed arm64 patches for GFN rumble capability and dispatch;
- a local HID bridge for physical Steam Controller vibration;
- unit tests for rumble mapping, report encoding, haptic patching, and reset
  utility argument validation;
- installer and uninstaller scripts for the standard system Applications
  folder, including installed-build verification and rollback;
- isolated transaction tests for successful replacement, verifier-triggered
  rollback, and idempotent removal;
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
  mandatory BackgroundAgent timeout;
- documentation now states the possible GeForce NOW Terms of Use and account
  risks of running a modified client;
- CI now pins third-party Actions to immutable commits and receives automated
  GitHub Actions dependency update proposals;
- the security policy now constrains elevated installation operations to the
  fixed patched-app target.

## [0.1.0] - 2026-07-14

### Added

- fail-closed arm64 patcher for GFN `_GCDeviceInit`;
- staged builder that preserves the official app and previous patched builds;
- read-only verifier for patch state and code signature;
- unit tests for unpatched, patched, idempotent, and rejected byte sequences;
- documentation of the verified Steam virtual-HID input path and limitations;
- macOS GitHub Actions workflow.
