# Changelog

Notable changes to this packaging project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Tags use `v<BusyBox version>-static.<packaging revision>`. The packaging revision
can change while the BusyBox source version stays the same.

## [Unreleased]

## [1.36.1-static.2] - 2026-11-26

BusyBox source remains 1.36.1 with the same pinned source archive and patches.

### Fixed

- Full's `sh`, `ash`, and `hush` now honor `PATH` for external commands. Disable
  `FEATURE_SH_STANDALONE`, so an independent executable such as `ip` placed first
  in `PATH` takes precedence over the BusyBox applet. Shell builtins keep their
  normal behavior, and explicit `busybox <applet>` invocation remains available.
- Limit PATH regression-test cleanup to the temporary files owned by that test.

### Added

- Runtime regression checks for shell PATH precedence, `xargs`, `find -exec`,
  and preservation of the `printf` shell builtin.
- Release notes are published from the matching version section of this changelog.

### Changed

- Full's audited `--list` baseline is 410 listed tools. The previous 411-entry
  list also included the `busybox` frontend; upstream omits that entry when
  standalone shell mode is disabled. The frontend remains callable and no
  functional tool is removed.
- Document deployment choices concerning independent tools, SUID installation,
  shell builtins, and the external OpenSSL dependency for certificate verification.

The Docker-compatible profile still follows its pinned Docker Official
configuration. Its standalone shell lookup, no-fork execution, and applet
preference remain disabled. Enabled shell builtins are independent of those
settings; for example, its Ash enables `echo`, `printf`, `test`, and `sleep`.

## [1.36.1-static.1] - 2026-08-12

### Added

- Initial static BusyBox 1.36.1 packaging with Full and Docker-compatible profiles
  for aarch64, armv7, armv6, x86_64, x86, riscv64, and loongarch64.
- Architecture, static-link, Unicode, configuration, and applet-list verification,
  with binaries and build metadata published by GitHub Actions.

### Shell lookup policy in this release

Full enabled `FEATURE_SH_STANDALONE`. Its shells could resolve an applet name
internally instead of selecting an independent executable through `PATH`.
Its 411-entry `--list` baseline included the `busybox` frontend.

Docker-compatible followed the pinned Docker Official configuration, with
`FEATURE_SH_STANDALONE`, `FEATURE_SH_NOFORK`, and `FEATURE_PREFER_APPLETS`
disabled. It still enabled normal shell builtins. Standalone applet lookup and
shell builtins are separate mechanisms.

This historical clarification does not change the original tag or binaries.

[Unreleased]: https://github.com/ihipop/busybox-static/compare/v1.36.1-static.2...HEAD
[1.36.1-static.2]: https://github.com/ihipop/busybox-static/compare/v1.36.1-static.1...v1.36.1-static.2
[1.36.1-static.1]: https://github.com/ihipop/busybox-static/releases/tag/v1.36.1-static.1
