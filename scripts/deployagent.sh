#!/usr/bin/env bash
set -euo pipefail

source_dir=$1
work=$2
protoc=$3
metalava=$4
r8=$5
adb="$source_dir/packages/modules/adb"
protobuf="$source_dir/external/protobuf"
agent="$work/deployagent"
mkdir -p "$agent"/{java,classes,dex,stubs,stub-classes}

awk '
    /^\/\// && !seen_package { print }
    /^package / { seen_package = 1 }
    /^package android[.]util [{]$/ { in_util = 1; next }
    in_util && /^  public final class Log [{]$/ {
        print "package android.util {"
        in_log = 1
    }
    in_log {
        gsub(/@(Nullable|NonNull) /, "")
        gsub(/@Size[(][^)]*[)] /, "")
        print
    }
    in_log && /^  [}]$/ { print "}"; found = 1; exit }
    END { if (!found) exit 1 }
' "$source_dir/frameworks/base/core/api/current.txt" > "$agent/log-api.txt"
"$metalava" --no-color --jdk-home "$JAVA_HOME" --exclude-all-annotations \
    "$agent/log-api.txt" --stubs "$agent/stubs"
"$JAVA_HOME/bin/javac" --release 8 -d "$agent/stub-classes" "$agent/stubs/android/util/Log.java"
"$JAVA_HOME/bin/jar" --create --file "$agent/log-api.jar" -C "$agent/stub-classes" .

"$protoc" -I "$adb/fastdeploy/proto" --java_out="lite:$agent/java" "$adb/fastdeploy/proto/ApkEntry.proto"
sed -n '/name: "libprotobuf-java-lite"/,/java_version:/p' "$protobuf/Android.bp" |
    sed -n "s@^ *\"\(java/core/.*[.]java\)\",\$@$protobuf/\1@p" > "$agent/java-sources.txt"
find "$adb/fastdeploy/deployagent/src" "$agent/java" -name '*.java' | sort >> "$agent/java-sources.txt"
sed -i 's/.*/"&"/' "$agent/java-sources.txt"
"$JAVA_HOME/bin/javac" -source 8 -target 8 -cp "$agent/log-api.jar" -d "$agent/classes" "@$agent/java-sources.txt"
"$JAVA_HOME/bin/jar" --create --file "$agent/agent-classes.jar" -C "$agent/classes" .
"$JAVA_HOME/bin/java" -cp "$r8" com.android.tools.r8.D8 --release --min-api 24 \
    --lib "$agent/log-api.jar" --lib "$JAVA_HOME" --output "$agent/dex" "$agent/agent-classes.jar"
"$JAVA_HOME/bin/jar" --create --no-manifest --date=2026-06-05T00:00:00Z \
    --file "$agent/deployagent.jar" -C "$agent/dex" classes.dex
{
    printf '%s\n' 'unsigned char kDeployAgent[] = {'
    xxd -i < "$agent/deployagent.jar"
    printf '%s\n' '};'
} > "$work/generated/deployagent.inc"
{
    printf '%s\n' 'unsigned char kDeployAgentScript[] = {'
    xxd -i < "$adb/fastdeploy/deployagent/deployagent.sh"
    printf '%s\n' '};'
} > "$work/generated/deployagentscript.inc"
