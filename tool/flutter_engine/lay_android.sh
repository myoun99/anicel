#!/usr/bin/env bash
# Lays one baked mode of Anicel's Flutter Android engine into the Maven
# repository the app's Gradle build takes it from (android/build.gradle.kts).
#
#   bash tool/flutter_engine/lay_android.sh <engine out> <flutter sdk> <maven root>
#
#   <engine out>   a baked out folder: android_release_arm64 or
#                  android_debug_arm64 — its root holds
#                  flutter_embedding_<mode>.jar/.pom and arm64_v8a_<mode>.jar/.pom
#   <flutter sdk>  the SDK the app is built with: its bin/cache/engine.stamp
#                  names the engine the patches sit on
#   <maven root>   the repository: <Dropbox>/anicel-flutter-engine/maven on
#                  the machines that build the app (the Gradle block says why)
#
# 🗣️관제 2026-11-24 00:32 (card the-galaxy-tab-canvas-went-slow-on-build-1095):
# the patched engine is laid under A NAME OF ITS OWN,
# 1.0.0-<engine.stamp>-anicel.<patch>, never the stock coordinates — with
# those, the stock jar a Gradle cache already holds could win without a
# word; with its own, a build that finds no patched engine fails by name.
# The patch number is the one line of tool/flutter_engine/android_patch,
# read here and by the Gradle block alike.
#
# ⚠️The baked poms name the engine's commit (args.gn engine_version), not
# the stamp the SDK asks by — so the version is written over, in the pom's
# text and in the file names, and nothing else of the pom changes (the
# embedding's androidx dependencies are the stock ones: the patch is Java
# and C++ only).
#
# A mode is laid whole or not at all: both its modules are found before
# either is laid, and each is written beside its place and renamed in, so
# a synced folder never shows another machine half a module.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: lay_android.sh <engine out> <flutter sdk> <maven root>" >&2
  exit 2
fi
out=$1
sdk=$2
root=$3
here=$(cd "$(dirname "$0")" && pwd)

patch=$(tr -d '[:space:]' < "$here/android_patch")
stamp=$(tr -d '[:space:]' < "$sdk/bin/cache/engine.stamp")
version="1.0.0-$stamp-anicel.$patch"

poms=()
for pom in "$out"/flutter_embedding_*.pom "$out"/arm64_v8a_*.pom; do
  [ -f "$pom" ] || continue
  name=$(basename "$pom" .pom)
  if [ ! -f "$out/$name.jar" ]; then
    echo "lay_android: $pom has no $name.jar beside it" >&2
    exit 1
  fi
  if ! grep -q '<version>1\.0\.0-[^<]*</version>' "$pom"; then
    echo "lay_android: $pom names no engine version" >&2
    exit 1
  fi
  poms+=("$pom")
done
if [ "${#poms[@]}" -ne 2 ]; then
  echo "lay_android: $out held ${#poms[@]} of the two a mode is" \
    "(flutter_embedding_<mode> and arm64_v8a_<mode>) — nothing laid" >&2
  exit 1
fi

for pom in "${poms[@]}"; do
  name=$(basename "$pom" .pom)
  jar="$out/$name.jar"
  baked=$(sed -n 's:.*<version>\(1\.0\.0-[^<]*\)</version>.*:\1:p' "$pom" |
    head -n 1)
  place="$root/io/flutter/$name/$version"
  beside="$place.laying"
  rm -rf "$beside"
  mkdir -p "$beside"
  sed "s:<version>$baked</version>:<version>$version</version>:" "$pom" \
    > "$beside/$name-$version.pom"
  cp "$jar" "$beside/$name-$version.jar"
  rm -rf "$place"
  mv "$beside" "$place"
  echo "laid io.flutter:$name:$version"
done
