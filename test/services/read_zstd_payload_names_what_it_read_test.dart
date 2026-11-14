import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/zstd_payload.dart';

/// The zstd payload decoder's contract — the one of the two service laws
/// this file used to carry that is still its own function. The other, the
/// whole-project cut walk, is `updateCutAnywhere` now and is pinned in
/// `project_tree_editor_test.dart`.
void main() {
  group('readZstdPayload', () {
    // ↩️Until the connection round (connection-round-checklist H) this was
    // the bench with no engine, whose answer had to say "no engine" and not
    // "corrupt": the engine's compressor ships with the app now.
    test('🚨bytes that are no frame it can read are a FormatException NAMING '
        'what could not be read', () {
      expect(
        () => readZstdPayload(
          Uint8List.fromList([1, 2, 3]),
          'drawing',
          (_) => 0,
        ),
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
        () => readZstdPayload(Uint8List(0), 'sound', (_) => 0),
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
