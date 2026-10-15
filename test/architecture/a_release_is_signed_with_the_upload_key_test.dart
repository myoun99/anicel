import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨AN ANDROID RELEASE IS SIGNED WITH THE PLAY UPLOAD KEY, OR IT IS NOT
/// BUILT.
///
/// Until 2026-10-09 the release build type carried the Flutter template's
/// `signingConfig = signingConfigs.getByName("debug")`: every APK the
/// release rounds put in `rel` was signed with this machine's debug key,
/// which Play refuses, and nothing said so (card
/// android-release-signed-with-debug-key; 유저 answered Q1 「지금 업로드
/// 키를 만든다」). The key lives outside the repository, so what can be
/// pinned here is the shape: the release reads the upload key, and a build
/// without one stops instead of falling back to the debug key.
///
/// 🧪What the shape does was measured with real Gradle runs on the lane
/// (the card has them): a throwaway key → an APK whose certificate is that
/// key's; no key → the build stops at `preReleaseBuild` naming what is
/// missing.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('the release build type is never signed with the debug key', () {
    final release = RegExp(r'release\s*\{[^}]*\}').firstMatch(gradle);
    expect(release, isNotNull, reason: 'the release block moved');
    expect(release!.group(0), isNot(contains('"debug"')));
    expect(
      release.group(0),
      contains('signingConfigs.findByName("upload")'),
      reason: 'LIVENESS — the release takes the upload key',
    );
  });

  test('a release without the upload key stops before it builds', () {
    final stop = RegExp(
      r'it\.name == "preReleaseBuild"[\s\S]*?uploadKeyMissing\.isNotEmpty\(\)'
      r'[\s\S]*?throw GradleException',
    );
    expect(gradle, matches(stop));
  });
}
