import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️관제 · 공통 2026-11-24 01:5x (card the-galaxy-tab-canvas-went-slow-on-
/// build-1095): every Android release is read for what Anicel's engine is
/// asked for by name (tool/flutter_engine/check_android_release.sh — run by
/// hand on made-up releases by check_android_release_test.sh, and on 공통's
/// QA APK and a stock one, 2026-11-24). The names it reads are the ones the
/// patch defines and the plugin asks for; a patch that renames one leaves
/// the check reading a name nothing asks for, so the three are pinned here.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final check = read('tool/flutter_engine/check_android_release.sh');
  final number = read('tool/flutter_engine/android_patch').trim();
  final patch = read(
    Directory('tool/flutter_engine')
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) =>
            file.uri.pathSegments.last.startsWith('$number-') &&
            file.path.endsWith('.patch'))
        .path,
  );
  final plugin = read('packages/gpu_engine/android/src/main/kotlin/com/myoun/'
      'gpu_engine/GpuEnginePlugin.kt');

  test('the method the plugin asks for by name is the one the patch defines '
      'and the check reads', () {
    expect(
      plugin,
      contains('getMethod("createHardwareBufferTexture", '
          'HardwareBuffer::class.java)'),
    );
    expect(
      patch,
      contains('createHardwareBufferTexture(@NonNull HardwareBuffer buffer)'),
    );
    expect(check, contains('name == "createHardwareBufferTexture"'));
    expect(
      check,
      contains('index(type, "(Landroid/hardware/HardwareBuffer;)") == 1'),
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
    expect(check, contains("grep -qa 'acquireLatestHardwareBuffer'"));
  });

  test('a definition is read from dexdump, never a grep of the dex', () {
    expect(check, contains(r'"$dexdump" "${dexes[@]}"'));
    expect(check, contains(r'$0 !~ /ABSTRACT/'));
    expect(RegExp(r'grep[^\n]*\.dex').hasMatch(check), isFalse);
  });
}
