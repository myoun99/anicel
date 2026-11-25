import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🗣️관제 · 공통 2026-11-24 01:5x (card the-galaxy-tab-canvas-went-slow-on-
/// build-1095): every Android release is read for what Anicel's engine is
/// asked for by name (tool/flutter_engine/check_android_release.sh — run by
/// hand on made-up releases by check_android_release_test.sh, and on 공통's
/// QA APK and a stock one, 2026-11-24). The names it reads are the ones the
/// patches define and the plugin asks for; a patch that renames one leaves
/// the check reading a name nothing asks for, so the three are pinned here.
///
/// The patches are the Android stack the engine is built with: each
/// `<n>-android-…` patch up to the number `android_patch` names — 0006 and
/// 0007 on it, whose read signal took the method a long and the consumer a
/// `hardwareBufferReadSignal` (2026-11-24) — a name the stock engine holds
/// nowhere, so each ABI's native is read for it as for 0006's.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final check = read('tool/flutter_engine/check_android_release.sh');
  final number = int.parse(read('tool/flutter_engine/android_patch').trim());
  final stack = [
    for (final file in filesUnder('tool/flutter_engine'))
      if (RegExp(r'^(\d{4})-android-.*\.patch$')
              .firstMatch(file.uri.pathSegments.last)
          case final named? when int.parse(named.group(1)!) <= number)
        file.path,
  ]..sort();
  final patch = stack.map(read).join('\n');
  final plugin = read('packages/gpu_engine/android/src/main/kotlin/com/myoun/'
      'gpu_engine/GpuEnginePlugin.kt');

  test('CONTROL: the stack ends with the patch the number names', () {
    final numbers = [
      for (final path in stack)
        path.split(RegExp(r'[\\/]')).last.substring(0, 4),
    ];
    expect(numbers, contains('0006'));
    expect(numbers.last, '$number'.padLeft(4, '0'));
  });

  test('the method the plugin asks for by name is the one the patch defines '
      'and the check reads', () {
    expect(
      plugin,
      matches(
        RegExp(
          r'getMethod\(\s*"createHardwareBufferTexture",\s*'
          r'HardwareBuffer::class\.java,\s*java\.lang\.Long\.TYPE,?\s*\)',
        ),
      ),
    );
    expect(
      patch,
      matches(
        RegExp(
          r'\+  public HardwareBufferTextureEntry createHardwareBufferTexture\(\n'
          r'\+\s*@NonNull HardwareBuffer buffer, long readSignal\)',
        ),
      ),
    );
    expect(check, contains('name == "createHardwareBufferTexture"'));
    expect(
      check,
      contains('index(type, "(Landroid/hardware/HardwareBuffer;J)") == 1'),
    );
  });

  test('the read signal the C++ asks the consumer for by name is the one '
      'the check reads', () {
    expect(patch, contains('+    long hardwareBufferReadSignal();'));
    expect(patch, contains('"hardwareBufferReadSignal", "()J");'));
    expect(
      check,
      contains('name == "hardwareBufferReadSignal" && type == "()J"'),
    );
  });

  test('the consumer the C++ finds by name is the one the check reads', () {
    expect(
      patch,
      contains('"io/flutter/view/TextureRegistry\$HardwareBufferConsumer"'),
    );
    expect(
      patch,
      contains('"acquireLatestHardwareBuffer", '
          '"()Landroid/hardware/HardwareBuffer;"'),
    );
    expect(
      check,
      contains(r'owner == "Lio/flutter/view/TextureRegistry$HardwareBuffer'
          'Consumer;"'),
    );
    expect(check, contains('name == "acquireLatestHardwareBuffer"'));
    expect(check, contains('type == "()Landroid/hardware/HardwareBuffer;"'));
    // Each ABI's native, by the name each patch's asks the embedding for.
    expect(
      check,
      contains("natives=('0006 acquireLatestHardwareBuffer' "
          "'0007 hardwareBufferReadSignal')"),
    );
    expect(check, contains(r'grep -qa "${native#* }" "$lib"'));
  });

  test('a definition is read from dexdump, never a grep of the dex', () {
    expect(check, contains(r'"$dexdump" "${dexes[@]}"'));
    expect(check, contains(r'$0 !~ /ABSTRACT/'));
    expect(RegExp(r'grep[^\n]*\.dex').hasMatch(check), isFalse);
  });
}
