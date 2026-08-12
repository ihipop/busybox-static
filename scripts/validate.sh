#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 BINARY CONFIG TARGET PROFILE" >&2
    exit 2
fi

binary=$1
config=$2
target=$3
profile=$4
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
docker_baseline="$repo_dir/compat/docker-official-1.36.1-applets.txt"
full_extra="$repo_dir/compat/full-1.36.1-extra-applets.txt"
applets="$binary.applets"

file_output=$(file "$binary")
case "$file_output" in
    *"statically linked"*|*"static-pie linked"*) ;;
    *)
        echo "binary is not statically linked: $file_output" >&2
        exit 1
        ;;
esac

program_headers=$(readelf -l "$binary")
if printf '%s\n' "$program_headers" | grep -q 'Requesting program interpreter'; then
    echo "binary unexpectedly contains a program interpreter" >&2
    exit 1
fi

elf_class=$(readelf -h "$binary" | sed -n 's/^[[:space:]]*Class:[[:space:]]*//p')
elf_machine=$(readelf -h "$binary" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
case "$target" in
    aarch64)
        expected_class=ELF64
        expected_machine=AArch64
        ;;
    armv7|armv6)
        expected_class=ELF32
        expected_machine=ARM
        ;;
    x86_64)
        expected_class=ELF64
        expected_machine='Advanced Micro Devices X86-64'
        ;;
    x86)
        expected_class=ELF32
        expected_machine='Intel 80386'
        ;;
    riscv64)
        expected_class=ELF64
        expected_machine='RISC-V'
        ;;
    loongarch64)
        expected_class=ELF64
        expected_machine=LoongArch
        ;;
    *)
        echo "unknown validation target: $target" >&2
        exit 2
        ;;
esac
if [ "$elf_class" != "$expected_class" ] || [ "$elf_machine" != "$expected_machine" ]; then
    echo "binary architecture mismatch for $target: $elf_class / $elf_machine" >&2
    exit 1
fi

grep -qx 'CONFIG_STATIC=y' "$config"
grep -qx 'CONFIG_UNICODE_SUPPORT=y' "$config"
grep -qx '# CONFIG_UNICODE_USING_LOCALE is not set' "$config"
grep -qx 'CONFIG_LAST_SUPPORTED_WCHAR=0' "$config"
grep -qx 'CONFIG_UNICODE_COMBINING_WCHARS=y' "$config"
grep -qx 'CONFIG_UNICODE_WIDE_WCHARS=y' "$config"
grep -qx 'CONFIG_UNICODE_BIDI_SUPPORT=y' "$config"
grep -qx 'CONFIG_UNICODE_NEUTRAL_TABLE=y' "$config"
grep -qx '# CONFIG_BBCONFIG is not set' "$config"
grep -qx '# CONFIG_FEATURE_COMPRESS_BBCONFIG is not set' "$config"

validation_tmp=$(mktemp -d)
trap 'rm -rf "$validation_tmp"' EXIT HUP INT TERM

"$binary" --list >"$validation_tmp/applets.unsorted"
LC_ALL=C sort -u "$validation_tmp/applets.unsorted" >"$applets"
LC_ALL=C sort -c "$docker_baseline"

case "$profile" in
    docker-compatible)
        base_config="$repo_dir/dist/busybox-docker-official-$target.config"
        unicode_delta='UNICODE_COMBINING_WCHARS|UNICODE_WIDE_WCHARS|UNICODE_BIDI_SUPPORT|UNICODE_NEUTRAL_TABLE'

        # Both files have already passed through oldconfig. Remove the only
        # permitted delta and require the remaining canonical configs to match.
        grep -Ev "^(# )?CONFIG_($unicode_delta)(=.*| is not set)$" \
            "$base_config" >"$validation_tmp/base.config"
        grep -Ev "^(# )?CONFIG_($unicode_delta)(=.*| is not set)$" \
            "$config" >"$validation_tmp/final.config"
        if ! cmp -s "$validation_tmp/base.config" "$validation_tmp/final.config"; then
            echo "Docker-compatible config changes symbols outside the approved Unicode set" >&2
            diff -u "$base_config" "$config" >&2 || true
            exit 1
        fi

        if ! cmp -s "$docker_baseline" "$applets"; then
            echo "Docker-compatible applet list differs from Docker Official Images:" >&2
            diff -u "$docker_baseline" "$applets" >&2 || true
            exit 1
        fi
        ;;
    full)
        for symbol in \
            BASH_IS_ASH \
            DEVFSD \
            FEATURE_DEVFS \
            FEATURE_PREFER_APPLETS \
            ASH_BASH_SOURCE_CURDIR \
            HUSH_BASH_SOURCE_CURDIR \
            TFTP_DEBUG \
            FEDORA_COMPAT \
            FEATURE_USE_BSS_TAIL \
            FEATURE_INIT_COREDUMPS \
            FEATURE_WATCHDOG_OPEN_TWICE \
            FEATURE_SH_NOFORK \
            LOGIN_SESSION_AS_CHILD \
            FEATURE_TLS_SHA1 \
            NUKE
        do
            grep -qx "# CONFIG_$symbol is not set" "$config"
        done

        LC_ALL=C sort -c "$full_extra"
        LC_ALL=C sort -u "$docker_baseline" "$full_extra" \
            >"$validation_tmp/full.expected"
        if [ "$(wc -l <"$validation_tmp/full.expected")" -ne 411 ]; then
            echo "internal error: Full applet baseline is not 411 entries" >&2
            exit 1
        fi
        if ! cmp -s "$validation_tmp/full.expected" "$applets"; then
            echo "Full applet list differs from the audited 411-applet baseline:" >&2
            diff -u "$validation_tmp/full.expected" "$applets" >&2 || true
            exit 1
        fi
        ;;
    *)
        echo "unknown validation profile: $profile" >&2
        exit 2
        ;;
esac

unicode_dir="$validation_tmp/unicode"
mkdir "$unicode_dir"
mkdir "$unicode_dir/中文目录" "$unicode_dir/音乐🎵"
unicode_output=$(LC_ALL=C "$binary" ls -1 "$unicode_dir")
printf '%s\n' "$unicode_output" | grep -qx '中文目录'
printf '%s\n' "$unicode_output" | grep -qx '音乐🎵'

echo "validated $profile/$target: $file_output"
