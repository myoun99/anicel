#!/usr/bin/env bash
# check_android_release.sh on made-up releases, by hand:
#
#   bash tool/flutter_engine/check_android_release_test.sh
#
# The dex is real — javac and the SDK's d8 compile a few classes named as
# R8 leaves them — and the natives are files with or without the patch's
# name. Each case says what it checks; the run ends
# `check_android_release_test: N passed` or names the first that failed.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
check="$here/check_android_release.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
passed=0

fail() {
  echo "check_android_release_test: FAILED — $1" >&2
  exit 1
}

sdk=$(sed -n 's/^sdk\.dir=//p' "$here/../../android/local.properties" |
  sed 's/\\:/:/g; s/\\\\/\//g; s/\\/\//g' | tr -d '\r')
android_jar=$(ls -d "$sdk"/platforms/android-*/android.jar | sort -V | tail -n 1)
d8_jar=$(ls -d "$sdk"/build-tools/*/lib/d8.jar | sort -V | tail -n 1)
jdk=${JAVA_HOME:-"C:/Program Files/Android/Android Studio/jbr"}
[ -f "$android_jar" ] && [ -f "$d8_jar" ] || fail "no android.jar or d8.jar under $sdk"

# dex_of <name> <java files…>: compiles the sources into $scratch/<name>.dex.
dex_of() {
  local name=$1
  local src="$scratch/src_$name" classes="$scratch/classes_$name"
  shift
  mkdir -p "$src" "$classes" "$scratch/dex_$name"
  for pair in "$@"; do
    mkdir -p "$src/$(dirname "${pair%%=*}")"
    printf '%s\n' "${pair#*=}" > "$src/${pair%%=*}"
  done
  "$jdk/bin/javac" -nowarn -source 11 -target 11 -classpath "$android_jar" \
    -d "$classes" $(find "$src" -name '*.java') 2> "$scratch/javac_$name.log" ||
    fail "javac: $(cat "$scratch/javac_$name.log")"
  "$jdk/bin/java" -cp "$d8_jar" com.android.tools.r8.D8 --min-api 26 \
    --lib "$android_jar" --output "$scratch/dex_$name" \
    $(find "$classes" -name '*.class') > "$scratch/d8_$name.log" 2>&1 ||
    fail "d8: $(cat "$scratch/d8_$name.log")"
  mv "$scratch/dex_$name/classes.dex" "$scratch/$name.dex"
}

# pack <out> <dex dir in it> <lib dir in it> <dex> <abi=patched|stock>…
pack() {
  local out=$1 dexdir=$2 libdir=$3 dex=$4
  local tree="$scratch/tree_$(basename "$1")"
  shift 4
  mkdir -p "$tree/$dexdir"
  cp "$dex" "$tree/$dexdir/classes.dex"
  for abi in "$@"; do
    mkdir -p "$tree/$libdir/${abi%%=*}"
    if [ "${abi#*=}" = patched ]; then
      printf 'ELF io/flutter/view/TextureRegistry$HardwareBufferConsumer\0acquireLatestHardwareBuffer\0' \
        > "$tree/$libdir/${abi%%=*}/libflutter.so"
    else
      printf 'ELF stock engine\0' > "$tree/$libdir/${abi%%=*}/libflutter.so"
    fi
  done
  "$jdk/bin/jar" cfM "$out" -C "$tree" . || fail "jar could not pack $out"
}

consumer='io/flutter/view/TextureRegistry.java=package io.flutter.view;
public interface TextureRegistry {
  interface HardwareBufferConsumer {
    android.hardware.HardwareBuffer acquireLatestHardwareBuffer();
  }
}'
renderer='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object createHardwareBufferTexture(android.hardware.HardwareBuffer buffer) {
    return null;
  }
}'
# What R8 does to an unkept member: a short name — and the plugin's
# getMethod literal keeps the old name in the dex's string pool.
renamed='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object a(android.hardware.HardwareBuffer buffer) { return null; }
}'
literal='com/myoun/gpu_engine/P.java=package com.myoun.gpu_engine;
public final class P {
  public static String asked() { return "createHardwareBufferTexture"; }
}'
declared='io/flutter/view/R.java=package io.flutter.view;
public interface R {
  Object createHardwareBufferTexture(android.hardware.HardwareBuffer buffer);
}'
consumer_renamed='io/flutter/view/a.java=package io.flutter.view;
public interface a {
  android.hardware.HardwareBuffer acquireLatestHardwareBuffer();
}'

dex_of good "$consumer" "$renderer" "$literal"
dex_of renamed "$consumer" "$renamed" "$literal"
dex_of declared "$consumer" "$declared" "$literal"
dex_of consumer_renamed "$consumer_renamed" "$renderer" "$literal"

# 1 — an apk that kept every name, on the patched native, is ok and says
# the class the method is on.
pack "$scratch/good.apk" . lib "$scratch/good.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/good.apk" 2>&1) || fail "a good apk was refused: $said"
echo "$said" | grep -q 'on Lio/flutter/embedding/engine/renderer/e;' ||
  fail "the class is not said: $said"
passed=$((passed + 1))

# 2 — a bundle keeps its dex and natives under base/: every ABI is read.
pack "$scratch/good.aab" base/dex base/lib "$scratch/good.dex" \
  arm64-v8a=patched armeabi-v7a=patched x86_64=patched
said=$(bash "$check" "$scratch/good.aab" 2>&1) || fail "a good bundle was refused: $said"
echo "$said" | grep -q 'in arm64-v8a armeabi-v7a x86_64$' ||
  fail "a bundle's ABIs are not all read: $said"
passed=$((passed + 1))

# 3 — the method renamed while its NAME lives on as the plugin's literal:
# a grep of the dex would pass this.
pack "$scratch/renamed.apk" . lib "$scratch/renamed.dex" arm64-v8a=patched
strings_hit=$(grep -ac createHardwareBufferTexture "$scratch/renamed.dex")
[ "$strings_hit" -gt 0 ] || fail "the made-up dex lost the literal"
said=$(bash "$check" "$scratch/renamed.apk" 2>&1) && fail "a renamed method passed"
echo "$said" | grep -q 'no public createHardwareBufferTexture' ||
  fail "the renamed method is not named: $said"
echo "$said" | grep -q HardwareBufferConsumer && fail "the kept consumer was refused: $said"
passed=$((passed + 1))

# 4 — only an abstract declaration of the name: nothing getMethod can invoke.
pack "$scratch/declared.apk" . lib "$scratch/declared.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/declared.apk" 2>&1) && fail "an abstract method passed"
echo "$said" | grep -q 'no public createHardwareBufferTexture' ||
  fail "the abstract-only dex is not named: $said"
passed=$((passed + 1))

# 5 — the consumer interface renamed: the C++ FindClass finds nothing.
pack "$scratch/consumer.apk" . lib "$scratch/consumer_renamed.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/consumer.apk" 2>&1) && fail "a renamed consumer passed"
echo "$said" | grep -q 'HardwareBufferConsumer.acquireLatestHardwareBuffer is not' ||
  fail "the renamed consumer is not named: $said"
passed=$((passed + 1))

# 6 — one ABI on the stock native fails by that ABI, and only it.
pack "$scratch/mixed.aab" base/dex base/lib "$scratch/good.dex" \
  arm64-v8a=patched armeabi-v7a=stock x86_64=patched
said=$(bash "$check" "$scratch/mixed.aab" 2>&1) && fail "a stock ABI passed"
[ "$(echo "$said" | grep -c 'stock engine')" -eq 1 ] &&
  echo "$said" | grep -q "armeabi-v7a's libflutter.so is the stock engine" ||
  fail "the stock ABI is not named alone: $said"
passed=$((passed + 1))

# 7 — a release with no libflutter.so at all is refused.
pack "$scratch/nolib.apk" . lib "$scratch/good.dex"
said=$(bash "$check" "$scratch/nolib.apk" 2>&1) && fail "a release with no native passed"
echo "$said" | grep -q 'no libflutter.so' || fail "the missing native is not named: $said"
passed=$((passed + 1))

echo "check_android_release_test: $passed passed"
