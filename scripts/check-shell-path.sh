#!/bin/sh
# Verify behavior independently of Kconfig: external tools follow PATH while
# normal shell builtins keep their shell semantics.
set -eu
[ "$#" -eq 1 ] || { echo "usage: $0 BINARY" >&2; exit 2; }
case "$1" in /*) binary=$1;; *) binary=$(pwd)/$1;; esac
[ -x "$binary" ]
work=$(mktemp -d)
cleanup() {
    rm -f "$work/ip" "$work/tc" "$work/brctl" "$work/printf"
    rmdir "$work"
}
trap cleanup EXIT HUP INT TERM
for name in ip tc brctl; do
    printf '#!/bin/sh\nprintf "external:%s\\n"\n' "$name" >"$work/$name"
    chmod 0755 "$work/$name"
done
# This deliberately must not override the shells' printf builtin.
printf '#!/bin/sh\nexit 73\n' >"$work/printf"
chmod 0755 "$work/printf"
expected=$(printf 'external:ip\nexternal:tc\nexternal:brctl\nbuiltin')
for shell in sh ash hush; do
    output=$(PATH="$work:$PATH" "$binary" "$shell" -ec '
        ip
        tc
        brctl
        printf "%s" builtin
    ')
    if [ "$output" != "$expected" ]; then
        echo "$shell did not honor external command PATH or shell builtins" >&2
        exit 1
    fi
done
output=$(printf '%s\n' probe | PATH="$work:$PATH" "$binary" xargs ip)
[ "$output" = external:ip ] || { echo 'xargs bypassed external PATH' >&2; exit 1; }
output=$(PATH="$work:$PATH" "$binary" find "$work/ip" -exec tc '{}' ';')
[ "$output" = external:tc ] || { echo 'find -exec bypassed external PATH' >&2; exit 1; }
echo 'validated shell, xargs, find PATH precedence and printf builtin'
