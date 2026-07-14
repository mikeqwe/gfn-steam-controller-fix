# Security policy

## Supported versions

Only the latest revision on the default branch is supported. Compatibility with
a particular GFN build is listed in the README and enforced by the instruction
signature check.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature when it is enabled for the
repository. If it is unavailable, open a minimal issue requesting a private
contact channel; do not include exploit details, credentials, private logs, or
other sensitive data in a public issue.

Reports should include the affected revision, macOS version, reproduction steps,
impact, and whether the issue can modify the official GFN installation.

## Design boundaries

The builder and verifier must remain unprivileged, offline, fail-closed on
unknown machine instructions, and restricted to a staged or separately
installed copy of GFN.

The installer and uninstaller may elevate only the fixed filesystem operations
needed to replace or remove
`/Applications/GeForceNOW-Steam-Controller.app`. They must not accept an
arbitrary privileged target. The installer must build and verify its candidate
before elevation, must verify the installed copy, and must restore the previous
patched copy if final verification fails. The official GFN app remains a
read-only source.

Changes that weaken any of these properties require explicit security
justification and tests.
