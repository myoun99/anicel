#!/usr/bin/env bash
# Builds one platform of a release: `flutter build <platform> --release`
# with the round's number and the commit it is cut from stamped in.
#
#   bash tool/release_build.sh <platform> <build number> [more flutter args]
#
# 🗣️I-139-Q5 (유저 2026-10-28): the feedback forms' Build field reads
# 「빌드 번호 + 커밋」, and 「배포할때도 같은 방식으로 통일하고싶음」 — so the
# number and the commit are stamped HERE, by every place a release is built:
# testflight.yml (iOS), macos-developer-id.yml, linux-release.yml, and the
# control tower's Windows · APK round. The app reads them back in
# lib/src/core/build_stamp.dart; every_release_build_is_stamped_one_way_test
# reads both sides.
#
# ⚠️No `set -u`: the Mac's bash 3.2 calls an empty "$@" unbound.

platform=$1
number=$2
shift 2

case "$number" in
  ''|*[!0-9]*)
    echo "::error::build number must be digits, got '$number'"
    exit 1
    ;;
esac
commit=$(git rev-parse --short=7 HEAD) || exit 1
echo "build number: $number, commit: $commit"

exec flutter build "$platform" --release \
  --build-number="$number" \
  --dart-define=ANICEL_BUILD="$number" \
  --dart-define=ANICEL_COMMIT="$commit" \
  "$@"
