import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️관제 2026-11-24 00:3x (card the-galaxy-tab-canvas-went-slow-on-build-
/// 1095): the Play bundle, the user's Studio build and CI take the Android
/// engine by ONE block of android/build.gradle.kts, under a version of its
/// own — and the patch number is one line both that block and the script
/// that lays the engine read. What Gradle does with it was measured by hand
/// (`gradlew :app:dependencies`, 2026-11-24: none laid — debug warns and is
/// stock, release is refused by name; laid — the four modules, and the
/// plugins' embedding, on `1.0.0-<stamp>-anicel.0006`, the other ABIs stock),
/// and tool/flutter_engine/lay_android_test.sh runs the script by hand.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final gradle = read('android/build.gradle.kts');
  final lay = read('tool/flutter_engine/lay_android.sh');

  test('the patch number is one line, read by the block and the script', () {
    expect(
      read('tool/flutter_engine/android_patch').trim(),
      matches(RegExp(r'^\d{4}$')),
    );
    expect(
      gradle,
      contains('val patch = file("../tool/flutter_engine/android_patch")'
          '.readText().trim()'),
    );
    expect(gradle, contains(r'"1.0.0-$stamp-anicel.$patch"'));
    expect(
      lay,
      contains(r'''patch=$(tr -d '[:space:]' < "$here/android_patch")'''),
    );
    expect(lay, contains(r'version="1.0.0-$stamp-anicel.$patch"'));
  });

  test('the embedding and every ABI go on that version in one place, from '
      'its own repository only', () {
    expect(
      gradle,
      contains('val anicelEngineModules =\n'
          '    setOf("flutter_embedding", "armeabi_v7a", "arm64_v8a", '
          '"x86_64")'),
    );
    expect(
      RegExp(r'useVersion\(').allMatches(gradle),
      hasLength(1),
      reason: 'one place puts a module on the patched engine',
    );
    expect(
      gradle,
      contains('embeddingLaid && anicelEngineLaid(requested.name) ->\n'
          '                    useVersion(anicelEngineVersion)'),
    );
    expect(
      gradle,
      contains(r'includeVersionByRegex("io\\.flutter", ".*", '
          r'".*-anicel\\..*")'),
    );
  });

  test('a release with none laid is refused by name; a debug build warns', () {
    expect(gradle, contains('mode == "release" ->\n'
        '                    throw GradleException('));
    expect(gradle, contains('⚠️the STOCK Flutter engine'));
  });

  test('an ABI not laid under a laid embedding stops the build by name', () {
    // 🔬공통 2026-11-24 01:2x: the plugin ships every ABI it targets, and
    // two went out stock under the patched embedding.
    expect(gradle, contains('        embeddingLaid ->\n'
        '                    throw GradleException('));
    expect(gradle, contains('its stock library would ship under '
        "\" +\n                            \"Anicel's embedding"));
  });
}
