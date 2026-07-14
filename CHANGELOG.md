# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-07-14

### Added

- fail-closed arm64 patcher for GFN `_GCDeviceInit`;
- staged builder that preserves the official app and previous patched builds;
- read-only verifier for patch state and code signature;
- unit tests for unpatched, patched, idempotent, and rejected byte sequences;
- documentation of the verified Steam virtual-HID input path and limitations;
- macOS GitHub Actions workflow.
