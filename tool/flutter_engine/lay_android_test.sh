#!/usr/bin/env bash
# lay_android.sh on a made-up baked out folder, by hand:
#
#   bash tool/flutter_engine/lay_android_test.sh
#
# Each case says what it checks; the run ends `lay_android_test: N passed`
# or names the first that failed.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lay="$here/lay_android.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
passed=0

fail() {
  echo "lay_android_test: FAILED — $1" >&2
  exit 1
}

pom_of() { # <artifactId> <version>
  cat <<EOF
<project>
  <groupId>io.flutter</groupId>
  <artifactId>$1</artifactId>
  <version>$2</version>
  <dependencies>
    <dependency>
      <groupId>androidx.annotation</groupId>
      <artifactId>annotation</artifactId>
      <version>1.9.1</version>
    </dependency>
  </dependencies>
</project>
EOF
}

sdk="$scratch/sdk"
mkdir -p "$sdk/bin/cache"
echo "06a2e2a1stamp" > "$sdk/bin/cache/engine.stamp"
patch=$(tr -d '[:space:]' < "$here/android_patch")
want="1.0.0-06a2e2a1stamp-anicel.$patch"

out="$scratch/out_release"
mkdir -p "$out"
for name in flutter_embedding_release arm64_v8a_release; do
  pom_of "$name" "1.0.0-9584c6713b" > "$out/$name.pom"
  echo "jar of $name" > "$out/$name.jar"
done
echo "sources" > "$out/flutter_embedding_release-sources.jar"
root="$scratch/maven"

# 1 — each module under the patched name, its pom's own version written
# over and its dependencies' left as they were.
bash "$lay" "$out" "$sdk" "$root" > /dev/null || fail "a whole mode was refused"
for name in flutter_embedding_release arm64_v8a_release; do
  dir="$root/io/flutter/$name/$want"
  [ -f "$dir/$name-$want.jar" ] || fail "no $name jar under $want"
  grep -q "<version>$want</version>" "$dir/$name-$want.pom" ||
    fail "$name's pom does not name $want"
  grep -q "1.0.0-9584c6713b" "$dir/$name-$want.pom" &&
    fail "$name's pom still names the baked version"
  grep -q "<version>1.9.1</version>" "$dir/$name-$want.pom" ||
    fail "$name's dependency version changed"
done
passed=$((passed + 1))

# 2 — nothing is left beside a laid mode, and laying again replaces it.
ls "$root/io/flutter/arm64_v8a_release" | grep -q laying &&
  fail "a .laying folder was left"
echo "jar again" > "$out/arm64_v8a_release.jar"
bash "$lay" "$out" "$sdk" "$root" > /dev/null || fail "laying again failed"
grep -q "jar again" \
  "$root/io/flutter/arm64_v8a_release/$want/arm64_v8a_release-$want.jar" ||
  fail "laying again kept the old jar"
passed=$((passed + 1))

# 3 — a mode with one of its two modules is refused, and lays nothing new.
half="$scratch/out_half"
mkdir -p "$half"
pom_of flutter_embedding_debug "1.0.0-9584c6713b" > "$half/flutter_embedding_debug.pom"
echo jar > "$half/flutter_embedding_debug.jar"
bash "$lay" "$half" "$sdk" "$scratch/maven_half" > /dev/null 2>&1 &&
  fail "half a mode was laid without a word"
[ -e "$scratch/maven_half" ] && fail "half a mode laid its one module"
passed=$((passed + 1))

# 4 — a pom with no jar beside it is refused.
nojar="$scratch/out_nojar"
mkdir -p "$nojar"
pom_of flutter_embedding_debug "1.0.0-9584c6713b" > "$nojar/flutter_embedding_debug.pom"
pom_of arm64_v8a_debug "1.0.0-9584c6713b" > "$nojar/arm64_v8a_debug.pom"
echo jar > "$nojar/flutter_embedding_debug.jar"
bash "$lay" "$nojar" "$sdk" "$scratch/maven_nojar" > /dev/null 2>&1 &&
  fail "a pom with no jar was laid"
[ -e "$scratch/maven_nojar" ] && fail "a mode missing a jar laid the other"
passed=$((passed + 1))

# 5 — another ABI's bake lays its own library beside the embedding.
x64="$scratch/out_x64"
mkdir -p "$x64"
for name in flutter_embedding_release x86_64_release; do
  pom_of "$name" "1.0.0-9584c6713b" > "$x64/$name.pom"
  echo "jar of $name" > "$x64/$name.jar"
done
bash "$lay" "$x64" "$sdk" "$root" > /dev/null || fail "an x86_64 bake was refused"
[ -f "$root/io/flutter/x86_64_release/$want/x86_64_release-$want.jar" ] ||
  fail "no x86_64 library under $want"
passed=$((passed + 1))

echo "lay_android_test: $passed passed"
