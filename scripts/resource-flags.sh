#!/bin/bash
set -euo pipefail
shopt -s nullglob
export LC_ALL=C TZ=UTC
source_dir=$1
work=$2
aconfig=$3
release_flags=$4
prefix=aconfig_value_set-platform_build_release-
sets=$(sed -n 's/^RELEASE_ACONFIG_VALUE_SETS :=\$= //p' "$release_flags")
args=()
for item in $sets; do
    release=${item#"$prefix"}
    files=("$source_dir"/build/release/aconfig/"$release"/android.content.res/*.textproto)
    for file in "${files[@]}"; do
        printf 'value %s\n' "$file"
        args+=(--values "$file")
    done
done
test "${#args[@]}" -gt 0
"$aconfig" create-cache --package android.content.res --container system \
    --declarations "$source_dir/frameworks/base/core/java/android/content/res/flags.aconfig" \
    --cache "$work/android-content-res.pb" --default-permission READ_ONLY --allow-read-write false \
    --force-read-only false \
    --mainline-beta-namespace-config "$source_dir/build/make/tools/aconfig/aconfig/config/mainline_beta_namespaces.json" \
    "${args[@]}"
"$aconfig" dump-cache --cache "$work/android-content-res.pb" \
  --format '{fully_qualified_name}:{permission}={state:bool}' --out "$work/android-content-res-flags.txt"
"$aconfig" create-cpp-lib --mode force-read-only --cache "$work/android-content-res.pb" --out "$work/generated"
