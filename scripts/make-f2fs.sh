#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
formatter="$root/libexec/${0##*/}"
original=("$@")
unset GETOPT_COMPATIBLE POSIXLY_CORRECT
parsed=$(getopt --shell bash --options 'qa:b:c:C:d:e:E:g:hHil:mo:O:rR:s:S:z:t:T:U:Vfw:Z:' --longoptions help -- "$@") ||
    exec "$formatter" "${original[@]}"
# GNU getopt quotes every argument for the requested shell.
eval "set -- $parsed"
options=()
size=
sparse=0
extra_device=0
while [[ $1 != -- ]]; do
    case "$1" in
        -S) sparse=1; size=$2; shift 2 ;;
        -c) extra_device=1; options+=("$1" "$2"); shift 2 ;;
        -[abCdeEgloORsztTUwZ])
            options+=("$1" "$2")
            shift 2
            ;;
        *) options+=("$1"); shift ;;
    esac
done
shift
if [[ $sparse == 0 ]]; then
    exec "$formatter" "${original[@]}"
fi
if [[ $# -ne 1 || $extra_device == 1 || ! $size =~ ^[0-9]+$ ]]; then
    printf '%s\n' 'Sparse F2FS formatting requires a size in bytes and one output file.' >&2
    exit 2
fi
output=$1
if [[ -e $output && ! -f $output ]]; then
    printf '%s\n' 'Sparse F2FS output must be a regular file.' >&2
    exit 2
fi
work=$(mktemp -d -- "$(dirname -- "$output")/.f2fs.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
truncate -s "$size" "$work/raw.img"
"$formatter" "${options[@]}" -t 0 "$work/raw.img"
"$root/libexec/img2simg" -s "$work/raw.img" "$work/sparse.img"
cat -- "$work/sparse.img" > "$output"
