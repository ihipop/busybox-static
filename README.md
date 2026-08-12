# Static BusyBox

This repository builds two statically linked BusyBox 1.36.1 profiles for
common Linux architectures. GitHub Actions builds inside
architecture-matched Alpine containers and publishes the binaries, effective
configuration, applet list, and build-package versions.

| Target | Docker platform | Full binary | Docker-compatible binary |
| --- | --- | --- | --- |
| AArch64 / ARM64 | `linux/arm64` | `busybox-full-aarch64` | `busybox-docker-compatible-aarch64` |
| ARMv7 hard-float | `linux/arm/v7` | `busybox-full-armv7` | `busybox-docker-compatible-armv7` |
| ARMv6 hard-float | `linux/arm/v6` | `busybox-full-armv6` | `busybox-docker-compatible-armv6` |
| x86-64 / AMD64 | `linux/amd64` | `busybox-full-x86_64` | `busybox-docker-compatible-x86_64` |
| x86 / i386 | `linux/386` | `busybox-full-x86` | `busybox-docker-compatible-x86` |
| RISC-V 64 | `linux/riscv64` | `busybox-full-riscv64` | `busybox-docker-compatible-riscv64` |
| LoongArch64 | `linux/loong64` | `busybox-full-loongarch64` | `busybox-docker-compatible-loongarch64` |

The Docker Official `alpine:3.23` image does not include a `linux/loong64`
manifest, although Alpine publishes an official LoongArch64 minirootfs. CI
downloads that rootfs directly from Alpine, verifies its pinned checksum,
constructs the target container from it, and runs it through the pinned
`qemu-loongarch64` user-mode emulator. Alpine package names use
`loongarch64`; the OCI platform identifier uses `linux/loong64` for the same
architecture.

## Shared source patches

Both profiles apply the same two downstream compatibility patches used by the
pinned Docker Official Images BusyBox 1.36.1 recipe:

- [`hackfix-to-disable-HW-acceleration-for-MD5-SHA1-on-x86-1.36.patch`](patches/hackfix-to-disable-HW-acceleration-for-MD5-SHA1-on-x86-1.36.patch)
  comes from Alpine aports. It keeps the SHA hardware-acceleration path on
  x86-64 but disables that path on 32-bit x86, where musl builds can otherwise
  contain read-only-segment relocations and crash at runtime.
- [`no-cbq.patch`](patches/no-cbq.patch) comes from the BusyBox bug tracker and
  is also carried by Docker Official Images and Debian. It removes obsolete CBQ
  parsing from the `tc` applet after Linux removed the corresponding UAPI;
  the rest of the `tc` applet remains available.

Each patch file retains its author, original URL, and related issue references.
They are applied to a fresh source tree before either profile is configured, so
Full and Docker-compatible use the same patched source baseline.

## Full profile

The Full profile starts from BusyBox `allyesconfig` and retains the maximum
practical runtime feature set for a general-purpose static musl binary. It has
an audited baseline of exactly **411 applets**.

Options that require unavailable static dependencies, build-only diagnostics,
PAM, SELinux, locale databases, legacy RPC/utmp support, or otherwise conflict
with the static release model are disabled. The public profile also excludes:

- the fake `bash` alias (`BASH_IS_ASH`), obsolete `devfsd`, and the accidental
  `rm -rf` alias `nuke`;
- experimental applet-preference and no-fork execution paths;
- non-standard current-directory fallback for `source` in Ash and Hush;
- TFTP packet debugging, init core-dump debugging, and the watchdog
  open-twice driver workaround;
- Fedora-specific `uname` behavior and deprecated SHA-1 TLS cipher support;
- `FEATURE_USE_BSS_TAIL`, so buffer limits and the build process remain
  deterministic across architectures without a layout-dependent second pass.

The Full profile is an independent maximum-capability profile. It is not
intended to reproduce Docker Official Images command behavior.

## Docker-compatible profile

The Docker-compatible profile reconstructs the Docker Official Images BusyBox
1.36.1 musl configuration from pinned upstream commit
[`c7624fc5c725ca94aedd0d570c3978a16fc8da35`](https://github.com/docker-library/busybox/commit/c7624fc5c725ca94aedd0d570c3978a16fc8da35).
The upstream recipe starts with `defconfig`, applies Docker's explicit settings,
and uses the same two downstream compatibility patches described above.
Provenance is recorded in
[`compat/docker-official-1.36.1.provenance`](compat/docker-official-1.36.1.provenance).

After preserving that effective configuration, the current compatible build
changes exactly four symbols:

| Symbol | Docker Official | Docker-compatible |
| --- | --- | --- |
| `CONFIG_UNICODE_COMBINING_WCHARS` | disabled | enabled |
| `CONFIG_UNICODE_WIDE_WCHARS` | disabled | enabled |
| `CONFIG_UNICODE_BIDI_SUPPORT` | disabled | enabled |
| `CONFIG_UNICODE_NEUTRAL_TABLE` | disabled | enabled |

No applets or other configuration symbols may differ. If a later upstream
recipe enables some of these options, the compatible profile changes only the
remaining disabled subset. This provides Docker Official command and applet
compatibility with BusyBox's complete internal Unicode width,
combining-character, bidirectional, and neutral-character tables enabled. It
does not depend on a target locale database.

The build compares the effective upstream configuration before and after
requesting those four options. If a future Docker Official recipe already
enables all four and `oldconfig` produces no change, CI does not build, upload,
or publish a redundant `busybox-docker-compatible-*` binary.

As one compatibility example, `emby/embyserver:4.9.5.0` uses BusyBox 1.36.1
from this Docker Official configuration line. The repository itself contains
no application-specific configuration or artifacts.

## Verification and release assets

Every CI build must pass all of these checks before upload:

- ELF is statically linked and has no program interpreter;
- ELF class and machine match the declared release target;
- Full matches the exact 411-applet audited baseline;
- Docker-compatible matches the exact Docker Official applet baseline;
- Docker-compatible differs from the reconstructed upstream config only by
  Unicode symbols from the four-item allowlist;
- both profiles enable internal Unicode tables and preserve UTF-8 filenames
  under `LC_ALL=C`;
- `CONFIG_BBCONFIG` remains disabled;
- all supported architectures produce byte-identical effective configs and
  applet lists; each architecture records its own build-package inventory.

Tagged releases currently contain fourteen architecture binaries plus shared
metadata:

```text
busybox-full-{aarch64,armv7,armv6,x86_64,x86,riscv64,loongarch64}
busybox-docker-compatible-{aarch64,armv7,armv6,x86_64,x86,riscv64,loongarch64}
busybox-full.config
busybox-full.applets
busybox-docker-compatible.config
busybox-docker-compatible.applets
busybox-docker-official.config
busybox-{aarch64,armv7,armv6,x86_64,x86,riscv64,loongarch64}.build-env
SHA256SUMS
```

If Docker Official Images gains the complete Unicode configuration, the seven
Docker-compatible binaries and their two metadata files are automatically
omitted; the Full binaries and upstream configuration record remain.

The BusyBox source version, official download URL, and official SHA256 are
pinned in [`source.env`](source.env). Source archives come directly from the
BusyBox project and are verified before extraction.

Run the same build locally with:

```sh
docker build --platform linux/arm64 -f Dockerfile.build -t busybox-static-build .
docker run --rm --platform linux/arm64 \
  -v "$PWD:/workspace" -w /workspace \
  busybox-static-build \
  ./scripts/build.sh aarch64
```

Local output is written to `dist/`. Official release assets are produced only
by the tagged GitHub Actions workflow.

## License

BusyBox and the build scripts in this repository are distributed under
GPL-2.0-only. See [`LICENSE`](LICENSE).
