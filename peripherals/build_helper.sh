#!/bin/sh
# Build a native battery helper from <name>.c beside this script, once per
# source version, and print the binary's path. Usage: build_helper.sh <name>

set -eu

[ $# -eq 1 ] || { echo "usage: $0 <helper name>" >&2; exit 2; }
helper_name=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_file="$script_dir/$helper_name.c"
plugin_cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/abhay-power-peripherals"

checksum_output=$(cksum < "$source_file")
source_checksum=${checksum_output%% *}
source_size=${checksum_output#* }
source_size=${source_size%% *}
binary_dir="$plugin_cache_root/$source_checksum-$source_size-v1"
binary_path="$binary_dir/$helper_name"

if [ ! -x "$binary_path" ]; then
    command -v cc >/dev/null 2>&1 || {
        echo "A C compiler is required to build the $helper_name helper" >&2
        exit 2
    }

    mkdir -p "$binary_dir"
    temporary_binary=$(mktemp "$binary_dir/.$helper_name.XXXXXX")
    trap 'rm -f "$temporary_binary"' EXIT HUP INT TERM

    cc -O2 -s -std=c11 -Wall -Wextra -Wpedantic \
        "$source_file" -o "$temporary_binary"
    chmod 700 "$temporary_binary"
    mv "$temporary_binary" "$binary_path"
    trap - EXIT HUP INT TERM
fi

printf '%s\n' "$binary_path"
