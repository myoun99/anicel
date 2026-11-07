#!/usr/bin/env bash
# What the GPU engine's build hook (packages/gpu_engine/hook/build.dart)
# builds in the trunk's one hook folder — run by hand, FROM A LANE: the
# lane and the trunk are the two checkouts.
#
# 1. QA_CHECKOUT IS WHAT KEEPS A CHECKOUT'S BUILD ITS OWN (관제 2026-11-08
#    00:24, connection-round-checklist — measured 00:21): the hook's cargo,
#    as the hook runs it (from packages/gpu_engine with --manifest-path, so
#    rust/.cargo/config.toml is not read; the pinned toolchain; the hook
#    folder, in its turn), for a target that is not Windows — the hook hands
#    those nothing else of a checkout's own. The lane's engine is changed and
#    dated older than the trunk's build; the trunk builds, then the lane:
#    with the lane's QA_CHECKOUT cargo builds the lane's engine again;
#    without it, it calls the trunk's build fresh for the lane (the 11-06
#    case of src/kernels/shared/one_checkout.rs), so the first answer is not
#    one any build would give. `check`, not `build`: the same freshness, and
#    no Android linker. ⚠️Not the Windows target: there build.rs names a
#    file in the hook folder for cargo to watch, which cargo writes down
#    relative to the trunk's package and whole for a lane's — so trunk and
#    lane build again for that alone (measured 2026-11-08, "the
#    rerun-if-changed instructions changed").
# 2. WITH NO BASH (Windows): a `flutter test` whose PATH holds no bash
#    builds in a target of the checkout's own and says so in the hook's log.
#
# ⚠️It builds in the trunk's hook folder (seconds once the engine is there;
# minutes cold) and puts the lane's src/lib.rs back with git.
# usage: bash tool/engine_hook_checkout_test.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE="$(cd "$HERE/.." && pwd)"
COMMON="$(git -C "$LANE" rev-parse --path-format=absolute --git-common-dir)"
TRUNK="$(cd "$COMMON/.." && pwd)"
if [ "$LANE" = "$TRUNK" ]; then
  echo "engine_hook_checkout_test: run it from a lane — it needs the trunk as a second checkout" >&2
  exit 2
fi
LIB=packages/gpu_engine/rust/src/lib.rs
# The two engines alike but for the change: a file one holds and the other
# not makes cargo build again whatever it was handed (the first run of
# this test, a lane behind master — 2026-11-08).
ENGINE=packages/gpu_engine/rust
if ! git -C "$LANE" diff --quiet "$(git -C "$TRUNK" rev-parse HEAD)" -- "$ENGINE" \
  || ! git -C "$TRUNK" diff --quiet HEAD -- "$ENGINE"; then
  echo "engine_hook_checkout_test: the lane's $ENGINE is not the trunk's — rebase the lane on master first" >&2
  exit 2
fi
CHANNEL="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$LANE/$ENGINE/rust-toolchain.toml")"
TARGET=aarch64-linux-android
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/engine-hook-checkout.XXXXXX")" || exit 2
trap 'git -C "$LANE" checkout -q -- "$LIB"; rm -rf "$LOGS"' EXIT

pass=0; fail=0
check() { # name, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok    $1"
  else fail=$((fail+1)); echo "FAIL  $1"; fi
}
native() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

# The hook's cargo for this checkout, handing QA_CHECKOUT as the hook does
# (its rust/ folder) when $2 is `with`; its log is $3.
hook_cargo() { # checkout, with|without, log
  local env=(RUSTUP_TOOLCHAIN="$CHANNEL")
  [ "$2" = with ] && env+=("QA_CHECKOUT=$(native "$1/$ENGINE")/")
  (cd "$1/packages/gpu_engine" && env "${env[@]}" \
    bash "$HERE/cargo_turn.sh" --folder hook check --release \
      --manifest-path rust/Cargo.toml --package gpu_engine --target "$TARGET") \
    >"$3" 2>&1
}

check "the hook hands QA_CHECKOUT for every target, as this test hands it" \
  "$(grep -qE "^ *'QA_CHECKOUT': input\.packageRoot\.resolve\('rust/'\)\.toFilePath\(\),$" \
    "$LANE/packages/gpu_engine/hook/build.dart"; echo $?)"
git -C "$LANE" checkout -q -- "$LIB"
printf '\npub static QA_HOOK_CHECKOUT_PROBE: u32 = %d;\n' "$(date +%s)" >>"$LANE/$LIB"
touch -d "3 hours ago" "$LANE/$LIB"
for hand in with without; do
  hook_cargo "$TRUNK" "$hand" "$LOGS/trunk_$hand.log" \
    && hook_cargo "$LANE" "$hand" "$LOGS/lane_$hand.log"
  built=$?
  again="$(grep -cF "Checking gpu_engine v" "$LOGS/lane_$hand.log")"
  if [ "$hand" = with ]; then
    check "with QA_CHECKOUT, cargo builds the lane's engine for the lane" \
      "$([ "$built" -eq 0 ] && [ "$again" -eq 1 ]; echo $?)"
  else
    check "LIVENESS — without it, cargo calls the trunk's build fresh for the lane" \
      "$([ "$built" -eq 0 ] && [ "$again" -eq 0 ]; echo $?)"
  fi
done
[ "$fail" -eq 0 ] || tail -5 "$LOGS"/*.log


if [ -n "$WINDIR" ] && command -v cmd >/dev/null; then
  no_bash="$(cmd //c "echo %PATH%" | tr -d '\r' | tr ';' '\n' \
    | grep -viE 'Git.(usr.bin|usr.local.bin|mingw64.bin|bin)$' | grep -v '^$' | paste -sd ';')"
  printf '@echo off\r\nset "PATH=%s"\r\ncd /d "%s"\r\nflutter test test\\architecture\\tests_do_not_race_the_code_test.dart\r\n' \
    "$no_bash" "$(native "$LANE")" >"$LOGS/no_bash.bat"
  bash "$HERE/run.sh" test_queue cmd //c "$(cd "$LOGS" && pwd -W)\\no_bash.bat" >"$LOGS/no_bash.log" 2>&1
  ran=$?
  said="$(grep -h '^gpu_engine:' "$LANE"/.dart_tool/hooks_runner/gpu_engine/*/stdout.txt 2>/dev/null)"
  check "with no bash on PATH, the test is green" "$([ "$ran" -eq 0 ]; echo $?)"
  check "and the hook says it built in a target of the checkout's own" \
    "$(printf '%s' "$said" | grep -q "no bash .* own target"; echo $?)"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
