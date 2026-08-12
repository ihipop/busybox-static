#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/source.env"
. "$repo_dir/compat/docker-official-1.36.1.provenance"

target=${1:-}
case "$target" in
    aarch64)
        busybox_arch=aarch64
        ;;
    armv7|armv6)
        busybox_arch=arm
        ;;
    x86_64)
        busybox_arch=x86_64
        ;;
    x86)
        busybox_arch=i386
        ;;
    riscv64)
        busybox_arch=riscv64
        ;;
    loongarch64)
        busybox_arch=loongarch64
        ;;
    *)
        echo "usage: $0 {aarch64|armv7|armv6|x86_64|x86|riscv64|loongarch64}" >&2
        exit 2
        ;;
esac

build_root="$repo_dir/.build/$target"
source_archive="$build_root/busybox-$BUSYBOX_VERSION.tar.bz2"
docker_recipe="$build_root/docker-official-$BUSYBOX_VERSION.Dockerfile.builder"
dist_dir="$repo_dir/dist"

rm -rf "$build_root"
mkdir -p "$build_root" "$dist_dir"

for stale_artifact in \
    "$dist_dir/busybox-full-$target" \
    "$dist_dir/busybox-full-$target.config" \
    "$dist_dir/busybox-full-$target.applets" \
    "$dist_dir/busybox-docker-compatible-$target" \
    "$dist_dir/busybox-docker-compatible-$target.config" \
    "$dist_dir/busybox-docker-compatible-$target.applets" \
    "$dist_dir/busybox-docker-compatible-$target.not-needed" \
    "$dist_dir/busybox-docker-official-$target.config" \
    "$dist_dir/busybox-$target.build-env"
do
    rm -f "$stale_artifact"
done

curl --fail --location --retry 5 --retry-all-errors \
    --output "$source_archive" "$BUSYBOX_SOURCE_URL"

printf '%s  %s\n' "$BUSYBOX_SHA256" "$source_archive" | sha256sum -c -

curl --fail --location --retry 5 --retry-all-errors \
    --output "$docker_recipe" "$DOCKER_LIBRARY_BUSYBOX_RECIPE_URL"
printf '%s  %s\n' "$DOCKER_LIBRARY_BUSYBOX_RECIPE_SHA256" "$docker_recipe" \
    | sha256sum -c -

set_bool() {
    symbol=$1
    value=$2
    sed -i \
        -e "/^CONFIG_${symbol}=/d" \
        -e "/^# CONFIG_${symbol} is not set$/d" \
        .config
    if [ "$value" = y ]; then
        printf 'CONFIG_%s=y\n' "$symbol" >>.config
    else
        printf '# CONFIG_%s is not set\n' "$symbol" >>.config
    fi
}

set_number() {
    symbol=$1
    value=$2
    sed -i \
        -e "/^CONFIG_${symbol}=/d" \
        -e "/^# CONFIG_${symbol} is not set$/d" \
        .config
    printf 'CONFIG_%s=%s\n' "$symbol" "$value" >>.config
}

set_value() {
    symbol=$1
    value=$2
    sed -i \
        -e "/^CONFIG_${symbol}=/d" \
        -e "/^# CONFIG_${symbol} is not set$/d" \
        .config
    printf 'CONFIG_%s=%s\n' "$symbol" "$value" >>.config
}

prepare_source() {
    profile=$1
    profile_root="$build_root/$profile"
    source_dir="$profile_root/busybox-$BUSYBOX_VERSION"

    mkdir -p "$profile_root"
    tar -xjf "$source_archive" -C "$profile_root"
    cd "$source_dir"

    for patch_file in "$repo_dir"/patches/*.patch; do
        patch -p1 --input="$patch_file"
    done

    export ARCH="$busybox_arch"
    export KCONFIG_NOTIMESTAMP=1
    export SOURCE_DATE_EPOCH
    SOURCE_DATE_EPOCH=$(stat -c '%Y' "$source_dir")
}

configure_docker_official() {
    # Read setConfs and unsetConfs directly from the hash-verified, pinned
    # Docker Official Images musl recipe. Do not maintain a second local copy.
    make defconfig >/dev/null

    set_confs=$(sed -n \
        "/^[[:space:]]*setConfs='/,/^[[:space:]]*';/p" \
        "$docker_recipe" \
        | grep -oE 'CONFIG_[A-Z0-9_]+=[^[:space:]\\]+')
    unset_confs=$(sed -n \
        "/^[[:space:]]*unsetConfs='/,/^[[:space:]]*';/p" \
        "$docker_recipe" \
        | grep -oE 'CONFIG_[A-Z0-9_]+')

    for conf_value in $set_confs; do
        conf=${conf_value%%=*}
        symbol=${conf#CONFIG_}
        value=${conf_value#*=}
        set_value "$symbol" "$value"
    done
    for conf in $unset_confs; do
        set_bool "${conf#CONFIG_}" n
    done
    make oldconfig </dev/null >/dev/null

    # Trust the upstream parser only after checking every extracted directive
    # against the effective BusyBox configuration.
    for conf_value in $set_confs; do
        grep -qx "$conf_value" .config
    done
    for conf in $unset_confs; do
        if grep -q "^$conf=" .config; then
            echo "Docker upstream requested $conf to be disabled" >&2
            exit 1
        fi
    done
}

configure_docker_compatible() {
    configure_docker_official
    docker_base_config="$dist_dir/busybox-docker-official-$target.config"
    cp .config "$docker_base_config"

    # Request the complete internal Unicode tables. A later upstream may
    # already enable some or all of these options.
    set_bool UNICODE_COMBINING_WCHARS y
    set_bool UNICODE_WIDE_WCHARS y
    set_bool UNICODE_BIDI_SUPPORT y
    set_bool UNICODE_NEUTRAL_TABLE y
    make oldconfig </dev/null >/dev/null

    docker_compatible_needed=y
    if cmp -s "$docker_base_config" .config; then
        docker_compatible_needed=n
    fi
}

configure_full() {
    # Start from the mechanical maximum, then remove options that cannot be
    # shipped reliably in a general-purpose static musl binary.
    make allyesconfig >/dev/null

    for symbol in \
        EXTRA_COMPAT \
        PAM \
        FEATURE_UTMP \
        FEATURE_WTMP \
        INSTALL_NO_USR \
        SELINUX \
        FEATURE_CLEAN_UP \
        NOMMU \
        DEBUG \
        DEBUG_PESSIMIZE \
        DEBUG_SANITIZE \
        UNIT_TEST \
        WERROR \
        WARN_SIMPLE_MSG \
        LOCALE_SUPPORT \
        UNICODE_USING_LOCALE \
        FEATURE_TAR_SELINUX \
        WHO \
        W \
        USERS \
        FEATURE_VI_REGEX_SEARCH \
        FEATURE_FIND_CONTEXT \
        LAST \
        FEATURE_LAST_FANCY \
        FEATURE_MOUNT_NFS \
        WALL \
        BBCONFIG \
        FEATURE_COMPRESS_BBCONFIG \
        RUNLEVEL \
        FEATURE_INETD_RPC \
        FEATURE_UPTIME_UTMP_SUPPORT \
        CHCON \
        GETENFORCE \
        GETSEBOOL \
        LOAD_POLICY \
        MATCHPATHCON \
        RUNCON \
        SELINUXENABLED \
        SESTATUS \
        SETENFORCE \
        SETFILES \
        FEATURE_SETFILES_CHECK_OPTION \
        RESTORECON \
        SETSEBOOL \
        SH_IS_HUSH \
        BASH_IS_ASH \
        BASH_IS_HUSH \
        ASH_BASH_SOURCE_CURDIR \
        HUSH_BASH_SOURCE_CURDIR \
        HUSH_MEMLEAK \
        FEATURE_PREFER_APPLETS \
        FEATURE_USE_BSS_TAIL \
        TFTP_DEBUG \
        FEDORA_COMPAT \
        DEVFSD \
        DEVFSD_MODLOAD \
        DEVFSD_FG_NP \
        DEVFSD_VERBOSE \
        FEATURE_DEVFS \
        FEATURE_INIT_COREDUMPS \
        FEATURE_WATCHDOG_OPEN_TWICE \
        FEATURE_SH_NOFORK \
        LOGIN_SESSION_AS_CHILD \
        FEATURE_TLS_SHA1 \
        NUKE
    do
        set_bool "$symbol" n
    done

    set_number LAST_SUPPORTED_WCHAR 0
    for symbol in \
        STATIC \
        UNICODE_SUPPORT \
        UNICODE_COMBINING_WCHARS \
        UNICODE_WIDE_WCHARS \
        UNICODE_BIDI_SUPPORT \
        UNICODE_NEUTRAL_TABLE \
        UNSHARE \
        SH_IS_ASH \
        BASH_IS_NONE \
        SHELL_ASH \
        ASH \
        ASH_OPTIMIZE_FOR_SIZE \
        ASH_INTERNAL_GLOB \
        ASH_BASH_COMPAT \
        ASH_BASH_NOT_FOUND_HOOK \
        ASH_JOB_CONTROL \
        ASH_ALIAS \
        ASH_RANDOM_SUPPORT \
        ASH_EXPAND_PRMT \
        ASH_IDLE_TIMEOUT \
        ASH_MAIL \
        ASH_ECHO \
        ASH_PRINTF \
        ASH_TEST \
        ASH_SLEEP \
        ASH_HELP \
        ASH_GETOPTS \
        ASH_CMDCMD \
        FEATURE_SH_STANDALONE
    do
        set_bool "$symbol" y
    done

    make oldconfig </dev/null >/dev/null
}

build_profile() {
    profile=$1
    prepare_source "$profile"

    case "$profile" in
        full)
            configure_full
            output="$dist_dir/busybox-full-$target"
            ;;
        docker-compatible)
            configure_docker_compatible
            if [ "$docker_compatible_needed" = n ]; then
                marker="$dist_dir/busybox-docker-compatible-$target.not-needed"
                printf '%s\n' \
                    "Docker Official Images BusyBox $BUSYBOX_VERSION musl already enables the complete internal Unicode configuration; no derivative Docker-compatible binary was produced." \
                    >"$marker"
                echo "skipped docker-compatible/$target: Docker upstream already has complete Unicode support"
                return 0
            fi
            output="$dist_dir/busybox-docker-compatible-$target"
            ;;
        *)
            echo "unknown build profile: $profile" >&2
            exit 2
            ;;
    esac

    make -j"$(getconf _NPROCESSORS_ONLN)" busybox
    cp busybox "$output"
    chmod 0755 "$output"
    cp .config "$output.config"

    "$repo_dir/scripts/validate.sh" \
        "$output" \
        "$output.config" \
        "$target" \
        "$profile"
}

build_profile full
build_profile docker-compatible
apk info -v | LC_ALL=C sort >"$dist_dir/busybox-$target.build-env"
