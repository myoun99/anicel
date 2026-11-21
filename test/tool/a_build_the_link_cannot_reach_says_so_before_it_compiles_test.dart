import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/gpu_engine/hook/target_link.dart';
import '../helpers/temp_dir.dart';

/// A BUILD WHOSE DEEPEST LINK INPUT LINK.EXE CANNOT REACH THROUGH THE HOOK'S
/// LINK FAILS BEFORE IT COMPILES, AND SAYS HOW MUCH TO CUT (card
/// the-link-fit-check-measures-the-app-depth-only, 2026-11-19).
///
/// tool/lane.sh refuses a lane whose app would not reach; the probe in
/// packages/gpu_engine/example builds 28 characters deeper, and in
/// `lane-two-textures-fill` it died at the link with LNK1104 — 266
/// characters — after its whole compile.
void main() {
  late Directory root;
  late Directory shared;
  late Uri output;
  late String target;

  const windowsDeps = 'x86_64-pc-windows-msvc/release/deps';

  void library(String deps, String name) =>
      File('${shared.path}/$deps/$name').createSync(recursive: true);

  /// A library name in [windowsDeps] that puts the path link.exe opens
  /// through the link at exactly [reach] characters.
  String reaching(int reach) {
    final length = reach - target.length - 1 - '$windowsDeps/'.length;
    return 'lib${'x' * (length - 'lib.rlib'.length)}.rlib';
  }

  FileSystemEntityType standing() =>
      FileSystemEntity.typeSync(target, followLinks: false);

  setUp(() {
    root = Directory.systemTemp.createTempSync('hook-reach');
    shared = Directory('${root.path}/shared')..createSync();
    output = Directory('${root.path}/lane/.dart_tool/hooks_runner/shared/'
            'gpu_engine/build/0123456789/')
        .absolute
        .uri;
    Directory.fromUri(output).createSync(recursive: true);
    target = output.resolve('target').toFilePath();
  });

  tearDown(() => deleteTempQuietly(root));

  test('the deepest input is the longest library in a Windows `deps`, the '
      'target\'s or the host\'s — not Android\'s, not a folder within, not '
      'what is no library', () {
    library(windowsDeps, 'liba.rlib');
    library('release/deps', 'libthe_host_builds_this_one_as_well.rlib');
    library('aarch64-linux-android/release/deps',
        'libandroid_is_linked_by_another_linker_entirely.rlib');
    library('$windowsDeps/inner', 'libinside_a_folder_within_is_never_linked');
    library(windowsDeps, 'gpu_engine-0123456789abcdef.gpu_engine.long.o');

    expect(deepestLinkInput(shared),
        'release/deps/libthe_host_builds_this_one_as_well.rlib');

    library('x86_64-pc-windows-msvc/debug/deps', 'libthe_longest_of_all.lib');
    expect(deepestLinkInput(shared),
        'x86_64-pc-windows-msvc/debug/deps/libthe_longest_of_all.lib');
  });

  test('of libraries as deep, the first in code-unit order — never the one '
      'the folder lists first or last', () {
    // NTFS lists these folded to one case — liba, libB, libc — and ext4 in
    // no fixed order; code-unit order puts libB first.
    for (final name in ['liba.rlib', 'libB.rlib', 'libc.rlib']) {
      library(windowsDeps, name);
    }

    expect(deepestLinkInput(shared), '$windowsDeps/libB.rlib');
  });

  test('a folder that has built nothing yet has nothing to measure', () {
    expect(deepestLinkInput(Directory('${root.path}/never')), isNull);
    expect(deepestLinkInput(shared), isNull);
    expect(whyTheLinkCannotReach(target, shared), isNull);
  });

  test('🚨past $kLinkReach the build fails before anything is built, takes '
      'no link, and says how many characters to cut', () async {
    library(windowsDeps, reaching(kLinkReach + 3));
    var built = false;

    await expectLater(
      withTargetAimed(output, shared.uri, linked: true, () async {
        built = true;
      }),
      throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(
        contains('${kLinkReach + 3} characters'),
        contains('LNK1104'),
        contains('3 character(s) shallower'),
      ))),
    );

    expect(built, isFalse);
    expect(standing(), FileSystemEntityType.notFound);
  });

  test('at $kLinkReach it builds', () async {
    library(windowsDeps, reaching(kLinkReach));
    var built = false;

    await withTargetAimed(output, shared.uri, linked: true, () async {
      built = true;
    });

    expect(built, isTrue);
  });

  test('a build no link.exe links is not measured', () async {
    library(windowsDeps, reaching(kLinkReach + 40));
    var built = false;

    await withTargetAimed(output, shared.uri, () async {
      built = true;
    });

    expect(built, isTrue);
  });

  test('the hook measures every build for Windows — the builds link.exe '
      'links', () {
    final hook = File('packages/gpu_engine/hook/build.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(hook, contains('final windows = input.config.buildCodeAssets &&\n'
        '        input.config.code.targetOS == OS.windows;'));
    expect(hook, contains('await withTargetAimed(input.outputDirectory, '
        'folder, linked: windows,'));
  });

  test('⚠️two readers, not three — lane.sh\'s `fits_the_link` and the hook '
      'name each other', () {
    final lanes = File('tool/lane.sh')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final hook = File('packages/gpu_engine/hook/target_link.dart')
        .readAsStringSync();
    expect(lanes, contains('target_link.dart\n# (`deepestLinkInput`)'));
    expect(hook, contains("tool/lane.sh's `fits_the_link`"));
    expect(hook, contains('`fits_the_link` counts the same files'));
  });
}
