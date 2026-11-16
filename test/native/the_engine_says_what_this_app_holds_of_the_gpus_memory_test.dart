import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// What the memory tab's VRAM line and the census read of the GPU
/// (`collectMemoryCensus`), asked of the app's engine itself
/// ([appGpuVideoMemory]): every number the OS says on this platform, and
/// none it does not.
///
/// 🗣️관제 2026-11-12 (vram-in-use-shown-in-the-memory-tab): ONE EXPORT —
/// the local use, the budget, the use in the RAM and the GPU's kind.
void main() {
  test('the engine says what this app holds of its adapter\'s memory, '
      'where the OS says it', () {
    appGpuEngine;
    final memory = appGpuVideoMemory!;

    if (Platform.isWindows) {
      expect(memory.used, greaterThan(0));
      expect(memory.budget, greaterThan(0));
      expect(memory.inSystem, isNotNull);
      expect(
        memory.budget,
        isNot(memory.used),
        reason: 'the budget the OS gives is not what the app uses of it',
      );
    } else if (Platform.isMacOS || Platform.isIOS) {
      expect(memory.used, greaterThan(0));
      expect(memory.budget, isNull);
      expect(memory.inSystem, isNull);
    } else {
      expect(memory.used, isNull);
      expect(memory.budget, isNull);
      expect(memory.inSystem, isNull);
    }
  });
}
