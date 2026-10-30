#!/usr/bin/env bash
# Builds one platform of a release: `flutter build <platform> --release`
# with the round's number and the commit it is cut from stamped in.
#
#   bash tool/release_build.sh <platform> <build number> [more flutter args]
#
# 🗣️I-139-Q5 (유저 2026-10-28): the feedback forms' Build field reads
# 「빌드 번호 + 커밋」, and 「배포할때도 같은 방식으로 통일하고싶음」 — so the
# number and the commit are stamped HERE, by every place a release is built:
# testflight.yml (iOS), macos-developer-id.yml, linux-release.yml,
# windows-arm64-release.yml, and the control tower's Windows · APK round. The
# app reads them back in lib/src/core/build_stamp.dart;
# every_release_build_is_stamped_one_way_test reads both sides.
#
# ⚠️No `set -u`: the Mac's bash 3.2 calls an empty "$@" unbound.

# The usage statistics' Aptabase App Key (I-70), `A-EU-…` or `A-US-…`. It
# ships inside every build that sends, as any analytics key does, so it is
# written here rather than kept secret (the user made the app, EU region,
# 2026-10-29). The app reads it back in
# lib/src/services/usage_stats/aptabase_client.dart; a build made anywhere
# but here (the IDE, Android Studio, a test) has none, and sends nothing.
aptabase_app_key='A-EU-1462843916'

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
  --dart-define=ANICEL_APTABASE_KEY="$aptabase_app_key" \
  "$@"
