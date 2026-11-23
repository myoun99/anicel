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

# pack <out> <dex dir in it> <lib dir in it> <dex> <abi=patched|0006|stock>…
# — patched is 0006 · 0007's native; the stock one holds `readSignal`, as
# the stock engine's strings do.
pack() {
  local out=$1 dexdir=$2 libdir=$3 dex=$4
  local tree="$scratch/tree_$(basename "$1")"
  shift 4
  mkdir -p "$tree/$dexdir"
  cp "$dex" "$tree/$dexdir/classes.dex"
  for abi in "$@"; do
    mkdir -p "$tree/$libdir/${abi%%=*}"
    case "${abi#*=}" in
    patched)
      printf 'ELF io/flutter/view/TextureRegistry$HardwareBufferConsumer\0acquireLatestHardwareBuffer\0hardwareBufferReadSignal\0' \
        > "$tree/$libdir/${abi%%=*}/libflutter.so" ;;
    0006)
      printf 'ELF io/flutter/view/TextureRegistry$HardwareBufferConsumer\0acquireLatestHardwareBuffer\0readSignal\0' \
        > "$tree/$libdir/${abi%%=*}/libflutter.so" ;;
    *)
      printf 'ELF stock engine\0readSignal\0' > "$tree/$libdir/${abi%%=*}/libflutter.so" ;;
    esac
  done
  "$jdk/bin/jar" cfM "$out" -C "$tree" . || fail "jar could not pack $out"
}

consumer='io/flutter/view/TextureRegistry.java=package io.flutter.view;
public interface TextureRegistry {
  interface HardwareBufferConsumer {
    android.hardware.HardwareBuffer acquireLatestHardwareBuffer();
    long hardwareBufferReadSignal();
  }
}'
renderer='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object createHardwareBufferTexture(
      android.hardware.HardwareBuffer buffer, long readSignal) {
    return null;
  }
}'
# What R8 does to an unkept member: a short name — and the plugin's
# getMethod literal keeps the old name in the dex's string pool.
renamed='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object a(android.hardware.HardwareBuffer buffer, long readSignal) {
    return null;
  }
}'
literal='com/myoun/gpu_engine/P.java=package com.myoun.gpu_engine;
public final class P {
  public static String asked() { return "createHardwareBufferTexture"; }
}'
declared='io/flutter/view/R.java=package io.flutter.view;
public interface R {
  Object createHardwareBufferTexture(
      android.hardware.HardwareBuffer buffer, long readSignal);
}'
consumer_renamed='io/flutter/view/a.java=package io.flutter.view;
public interface a {
  android.hardware.HardwareBuffer acquireLatestHardwareBuffer();
  long hardwareBufferReadSignal();
}'
# 0006's consumer: no read signal for the C++ to ask by name.
consumer_unsignalled='io/flutter/view/TextureRegistry.java=package io.flutter.view;
public interface TextureRegistry {
  interface HardwareBufferConsumer {
    android.hardware.HardwareBuffer acquireLatestHardwareBuffer();
  }
}'
other_door='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object createHardwareBufferTexture(Object buffer) { return null; }
}'
# 0006's door: the buffer alone, no read signal — getMethod asks for both.
old_door='io/flutter/embedding/engine/renderer/e.java=package io.flutter.embedding.engine.renderer;
public final class e {
  public Object createHardwareBufferTexture(android.hardware.HardwareBuffer buffer) {
    return null;
  }
}'

dex_of good "$consumer" "$renderer" "$literal"
dex_of renamed "$consumer" "$renamed" "$literal"
dex_of declared "$consumer" "$declared" "$literal"
dex_of consumer_renamed "$consumer_renamed" "$renderer" "$literal"
dex_of other_door "$consumer" "$other_door" "$literal"
dex_of old_door "$consumer" "$old_door" "$literal"
dex_of consumer_unsignalled "$consumer_unsignalled" "$renderer" "$literal"

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

# 4b — the name on a method that takes no HardwareBuffer: getMethod asks
# for (HardwareBuffer, long), and finds nothing.
pack "$scratch/other_door.apk" . lib "$scratch/other_door.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/other_door.apk" 2>&1) && fail "another signature passed"
echo "$said" | grep -q 'no public createHardwareBufferTexture' ||
  fail "the other signature is not named: $said"
passed=$((passed + 1))

# 4c — 0006's door, the buffer alone: an embedding without 0007's read
# signal is refused by name.
pack "$scratch/old_door.apk" . lib "$scratch/old_door.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/old_door.apk" 2>&1) && fail "0006's door passed"
echo "$said" | grep -q 'no public createHardwareBufferTexture(HardwareBuffer, long)' ||
  fail "0006's door is not named: $said"
passed=$((passed + 1))

# 4d — 0006's consumer, no readSignal: the C++ GetMethodID finds nothing,
# and that alone is named.
pack "$scratch/unsignalled.apk" . lib "$scratch/consumer_unsignalled.dex" arm64-v8a=patched
said=$(bash "$check" "$scratch/unsignalled.apk" 2>&1) && fail "a consumer with no signal passed"
echo "$said" | grep -q 'HardwareBufferConsumer.hardwareBufferReadSignal()J is not' ||
  fail "the missing signal is not named: $said"
echo "$said" | grep -q 'acquireLatestHardwareBuffer is not' &&
  fail "the kept acquire was refused: $said"
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
[ "$(echo "$said" | grep -c 'carries no patch')" -eq 1 ] &&
  echo "$said" | grep -q "armeabi-v7a's libflutter.so carries no patch 0006 0007" ||
  fail "the stock ABI is not named alone: $said"
passed=$((passed + 1))

# 6b — one ABI on 0006's native alone, the lay mixed: named by that ABI and
# the patch it lacks (관제 2026-11-24 03:1x).
pack "$scratch/mixed_0006.aab" base/dex base/lib "$scratch/good.dex" \
  arm64-v8a=patched armeabi-v7a=patched x86_64=0006
said=$(bash "$check" "$scratch/mixed_0006.aab" 2>&1) && fail "an ABI of 0006 alone passed"
[ "$(echo "$said" | grep -c 'carries no patch')" -eq 1 ] &&
  echo "$said" | grep -q "x86_64's libflutter.so carries no patch 0007$" ||
  fail "the ABI of 0006 alone is not named alone: $said"
passed=$((passed + 1))

# 7 — a release with no libflutter.so at all is refused.
pack "$scratch/nolib.apk" . lib "$scratch/good.dex"
said=$(bash "$check" "$scratch/nolib.apk" 2>&1) && fail "a release with no native passed"
echo "$said" | grep -q 'no libflutter.so' || fail "the missing native is not named: $said"
passed=$((passed + 1))

echo "check_android_release_test: $passed passed"
