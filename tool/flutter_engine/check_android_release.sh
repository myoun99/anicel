#!/usr/bin/env bash
# Reads a built Android release (.aab or .apk) for what Anicel's engine is
# asked for BY NAME, and fails naming each one that did not survive the build:
#
#   bash tool/flutter_engine/check_android_release.sh <aab|apk>
#
#   ① a public, non-abstract createHardwareBufferTexture(HardwareBuffer,
#      long) defined in the dex — the plugin finds it with getMethod on the
#      texture registry's own class (packages/gpu_engine/android/.../
#      GpuEnginePlugin.kt); patch 0007 added the long, its read signal
#   ② io/flutter/view/TextureRegistry$HardwareBufferConsumer declaring
#      acquireLatestHardwareBuffer()Landroid/hardware/HardwareBuffer; and
#      readSignal()J — the engine's C++ finds them with FindClass /
#      GetMethodID (patches 0006 · 0007, platform_view_android_jni_impl.cc)
#   ③ every ABI's libflutter.so carrying acquireLatestHardwareBuffer — the
#      patched native, not the stock one, in each ABI the release ships.
#      ⚠️No name tells 0007's native from 0006's: `readSignal` is in the
#      stock engine's strings too (🔬arm64 release libflutter.so of
#      06a2e2a1, two hits, 2026-11-24). What keeps 0007's natives under
#      0007's embedding is the one version both are taken at
#      (android/build.gradle.kts, the_android_build_takes_anicels_engine).
#
# Ends `check_android_release: ok — …` (exit 0), or names every miss (exit 1).
#
# 🗣️관제 2026-11-24 01:5x · 공통 01:5x (card the-galaxy-tab-canvas-went-slow-
# on-build-1095): R8 strips or renames what is looked up by name, and a
# release that lost it builds green and shows no canvas — so each release is
# read for it, in the bundle that ships (control-tower release_round.sh
# play_bundle calls this, as it reads the bundle's engine and signature).
#
# ⚠️BY DEFINITION, NOT BY STRING: the dex's string pool holds names and
# literals as one — the plugin's own "createHardwareBufferTexture" literal
# keeps that string alive after R8 has renamed the method — so dexdump's
# method records (name · type · access) are read, never a grep of the dex.
# ⚠️NOT BY CLASS NAME (🔬공통 01:5x, and the QA APK on d19c66834): R8 renames
# FlutterRenderer (`…/renderer/e`) and drops its TextureRegistry interface;
# the keep rule keeps the member's name only, and getMethod asks the
# instance's class, so ① is asked of any class.
set -uo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: check_android_release.sh <aab|apk>" >&2
  exit 2
fi
bundle=$1
here=$(cd "$(dirname "$0")" && pwd)

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -z "$sdk" ] && [ -f "$here/../../android/local.properties" ]; then
  sdk=$(sed -n 's/^sdk\.dir=//p' "$here/../../android/local.properties" |
    sed 's/\\:/:/g; s/\\\\/\//g; s/\\/\//g' | tr -d '\r')
fi
dexdump=
for tools in $(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V -r); do
  for name in dexdump.exe dexdump; do
    if [ -x "$tools$name" ]; then
      dexdump="$tools$name"
      break 2
    fi
  done
done
if [ -z "$dexdump" ]; then
  echo "check_android_release: no dexdump under the Android SDK" \
    "('${sdk:-none}' — ANDROID_HOME or android/local.properties sdk.dir)" >&2
  exit 2
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
# An apk keeps its dex at the root and its natives in lib/<abi>/; a bundle
# keeps both under base/ (base/dex/, base/lib/<abi>/) — named as they are,
# since this unzip's * stops at a slash.
unzip -q -o "$bundle" 'classes*.dex' 'lib/*/libflutter.so' \
  'base/dex/*.dex' 'base/lib/*/libflutter.so' -d "$scratch" 2>/dev/null

misses=()
miss() { misses+=("$*"); }
dexes=()
while IFS= read -r dex; do dexes+=("$dex"); done \
  < <(find "$scratch" -name '*.dex' | sort)
if [ "${#dexes[@]}" -eq 0 ]; then
  miss "no dex in $bundle"
else
  found=$("$dexdump" "${dexes[@]}" 2>/dev/null | awk '
    function value(line) {
      sub(/^[^:]*: \047/, "", line)
      sub(/\047$/, "", line)
      return line
    }
    /^  Class descriptor *: / { owner = value($0) }
    /^      name *: / { name = value($0) }
    /^      type *: / { type = value($0) }
    /^      access *: / {
      if (name == "createHardwareBufferTexture" &&
          index(type, "(Landroid/hardware/HardwareBuffer;J)") == 1 &&
          $0 ~ /PUBLIC/ && $0 !~ /ABSTRACT/)
        print "create " owner
      if (owner == "Lio/flutter/view/TextureRegistry$HardwareBufferConsumer;" &&
          name == "acquireLatestHardwareBuffer" &&
          type == "()Landroid/hardware/HardwareBuffer;")
        print "consumer"
      if (owner == "Lio/flutter/view/TextureRegistry$HardwareBufferConsumer;" &&
          name == "readSignal" && type == "()J")
        print "signal"
    }')
  creator=$(echo "$found" | sed -n 's/^create //p' | head -n 1)
  [ -n "$creator" ] ||
    miss "no public createHardwareBufferTexture(HardwareBuffer, long) is" \
      "defined in the dex — the plugin's getMethod finds none (R8 renamed or" \
      "stripped it, or the embedding is not 0007's)"
  echo "$found" | grep -qx consumer ||
    miss "TextureRegistry\$HardwareBufferConsumer.acquireLatestHardwareBuffer" \
      "is not in the dex by that name — the engine's FindClass/GetMethodID finds none"
  echo "$found" | grep -qx signal ||
    miss "TextureRegistry\$HardwareBufferConsumer.readSignal()J" \
      "is not in the dex by that name — the engine's GetMethodID finds none"
fi

abis=()
while IFS= read -r lib; do
  abi=$(basename "$(dirname "$lib")")
  if grep -qa 'acquireLatestHardwareBuffer' "$lib"; then
    abis+=("$abi")
  else
    miss "$abi's libflutter.so is the stock engine (no patch 0006)"
  fi
done < <(find "$scratch" -path '*/lib/*/libflutter.so' | sort)
[ -n "$(find "$scratch" -name libflutter.so)" ] ||
  miss "no libflutter.so in $bundle"

if [ "${#misses[@]}" -gt 0 ]; then
  for miss in "${misses[@]}"; do
    echo "check_android_release: $miss" >&2
  done
  exit 1
fi
echo "check_android_release: ok — createHardwareBufferTexture on $creator ·" \
  "HardwareBufferConsumer.acquireLatestHardwareBuffer · .readSignal ·" \
  "patched libflutter.so in ${abis[*]}"
