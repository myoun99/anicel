import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/zstd_payload.dart';

/// The zstd payload decoder's contract — the one of the two service laws
/// this file used to carry that is still its own function. The other, the
/// whole-project cut walk, is `updateCutAnywhere` now and is pinned in
/// `project_tree_editor_test.dart`.
void main() {
  group('decompressZstdPayload', () {
    test('🚨with no engine it is a FormatException NAMING what could not be '
        'read — "no engine" is something the user can act on, and it must '
        'not reach the screen as "corrupt"', () {
      // The engine is optional at runtime, and this test bench has none.
      expect(
        () => decompressZstdPayload(Uint8List.fromList([1, 2, 3]), 'drawing'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('drawing'), contains('zstd')),
          ),
        ),
      );
    });

    test('the name travels — a caller says what it was reading', () {
      expect(
        () => decompressZstdPayload(Uint8List(0), 'sound'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sound'),
          ),
        ),
      );
    });
  });
}
