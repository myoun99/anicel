#!/usr/bin/env bash
# What the GPU engine's build hook (packages/gpu_engine/hook/build.dart)
# builds in the trunk's one hook folder — run by hand, FROM A LANE: the
# lane and the trunk are the two checkouts.
#
# 1. QA_CHECKOUT IS WHAT KEEPS A CHECKOUT'S BUILD ITS OWN (관제 2026-11-08
#    00:24, connection-round-checklist — measured 00:21): the hook's cargo,
#    as the hook runs it (from packages/gpu_engine with --manifest-path, so
#    rust/.cargo/config.toml is not read; the pinned toolchain; the hook
#    folder, in its turn), for this machine's own target with nothing else
#    of a checkout's own — as the hook hands every target but Windows, which
#    also gets GPU_ENGINE_DXC_OUT. The lane's engine is marked and dated
#    older than the trunk's build, the trunk builds, then the lane: with the
#    lane's QA_CHECKOUT its library holds the mark; without it, it holds
#    the trunk's (the 11-06 case of src/kernels/shared/one_checkout.rs), so
#    the first answer is not one any build would give.
# 2. WITH NO BASH (Windows): a `flutter test` whose PATH holds no bash
#    builds in a target of the checkout's own and says so in the hook's log.
#
# ⚠️It builds in the trunk's hook folder (a few seconds once the engine is
# there; minutes cold) and puts the lane's src/lib.rs back with git.
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
MARK="probe-$(date +%s)-lane"
CHANNEL="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$LANE/packages/gpu_engine/rust/rust-toolchain.toml")"
HOST="$(RUSTUP_TOOLCHAIN="$CHANNEL" rustc -vV | sed -n 's/^host: //p')"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/engine-hook-checkout.XXXXXX")" || exit 2
trap 'git -C "$LANE" checkout -q -- "$LIB"; rm -rf "$LOGS"' EXIT

pass=0; fail=0
check() { # name, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok    $1"
  else fail=$((fail+1)); echo "FAIL  $1"; fi
}
native() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

# The hook's cargo for this checkout, handing QA_CHECKOUT as the hook does
# (its rust/ folder) when $2 is `with`.
hook_cargo() { # checkout, with|without
  local env=(RUSTUP_TOOLCHAIN="$CHANNEL")
  [ "$2" = with ] && env+=("QA_CHECKOUT=$(native "$1/packages/gpu_engine/rust")/")
  (cd "$1/packages/gpu_engine" && env "${env[@]}" \
    bash "$HERE/cargo_turn.sh" --folder hook build --release \
      --manifest-path rust/Cargo.toml --package gpu_engine --target "$HOST") \
    >>"$LOGS/cargo.log" 2>&1
}
library() {
  ls "$TRUNK"/packages/gpu_engine/rust/target-hook/"$HOST"/release/*gpu_engine_core.{dll,so,dylib} 2>/dev/null | head -1
}

git -C "$LANE" checkout -q -- "$LIB"
printf '\n#[unsafe(no_mangle)]\npub static QA_HOOK_CHECKOUT_PROBE: [u8; %d] = *b"%s";\n' \
  "${#MARK}" "$MARK" >>"$LANE/$LIB"
touch -d "3 hours ago" "$LANE/$LIB"
for hand in with without; do
  hook_cargo "$TRUNK" "$hand" && hook_cargo "$LANE" "$hand"
  built=$?
  lib="$(library)"
  if [ "$hand" = with ]; then
    check "with QA_CHECKOUT, the lane's library is the lane's build" \
      "$([ "$built" -eq 0 ] && grep -q "$MARK" "$lib"; echo $?)"
  else
    check "LIVENESS — without it, the lane's library is the trunk's" \
      "$([ "$built" -eq 0 ] && ! grep -q "$MARK" "$lib"; echo $?)"
  fi
done
[ "$fail" -eq 0 ] || tail -20 "$LOGS/cargo.log"

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
