import 'dart:io';

import 'package:anicel/src/core/build_stamp.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨EVERY RELEASE IS BUILT THROUGH `tool/release_build.sh`.
///
/// 🗣️I-139-Q5 (유저 2026-10-28): the feedback forms' Build field reads the
/// round's number and the commit, stamped one way for every release
/// (「배포할때도 같은 방식으로 통일하고싶음」). A workflow that called
/// `flutter build … --release` itself would ship a build that says `dev`
/// while looking like any other — so a release build anywhere else is
/// named here. (The control tower's Windows · APK round lives outside the
/// repository; it calls the same script.)
void main() {
  test('no workflow builds a release but through the script', () {
    final own = <String>[];
    for (final file in filesUnder('.github/workflows')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#')) continue;
        if (line.contains('flutter build') && line.contains('--release')) {
          own.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(own, isEmpty, reason: 'bash tool/release_build.sh <platform> <N>');
  });

  test('the four release workflows build through it', () {
    for (final name in const [
      '.github/workflows/testflight.yml',
      '.github/workflows/macos-developer-id.yml',
      '.github/workflows/linux-release.yml',
      '.github/workflows/windows-arm64-release.yml',
    ]) {
      expect(
        File(name).readAsStringSync(),
        contains('bash tool/release_build.sh '),
        reason: name,
      );
    }
  });

  test('the script stamps the two defines the app reads', () {
    final script = File('tool/release_build.sh').readAsStringSync();
    expect(script, contains('--dart-define=$buildNumberDefine='));
    expect(script, contains('--dart-define=$buildCommitDefine='));
    expect(script, contains('--build-number='));
  });

  test('and passes the usage statistics\' key the app reads — a build made '
      'anywhere else has none, and sends nothing (I-70)', () {
    final script = File('tool/release_build.sh').readAsStringSync();
    expect(script, contains('--dart-define=$aptabaseKeyDefine='));
    // A key that names no region would ship builds that never send.
    final key = RegExp(
      r"^aptabase_app_key='([^']*)'\r?$",
      multiLine: true,
    ).firstMatch(script)?.group(1);
    expect(key, isNotNull, reason: 'the script names its key on one line');
    expect(AptabaseClient.endpointFor(key!), isNotNull, reason: key);
    expect(
      AptabaseClient().endpoint,
      isNull,
      reason: '시험은 키를 받지 않은 빌드다',
    );
  });

  test('a stamped build says its number and commit; an unstamped one, dev',
      () {
    expect(stampOf(number: '1060', commit: 'a1b2c3d'), '1060 (a1b2c3d)');
    expect(stampOf(number: '', commit: ''), 'dev');
    expect(buildStamp, 'dev', reason: '시험은 아무도 새기지 않은 빌드다');
  });
}
