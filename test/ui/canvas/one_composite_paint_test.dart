import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

/// 🚨★★★ONE COMPOSITE PAINT — the half #1304 left hand-written.
///
/// #1304 ("Every route composites a group the same way") unified the WALK.
/// It did NOT unify the PAINT that walk composites with, and three
/// hand-written copies promptly disagreed — the editing stack clamped the
/// opacity, the camera and the playback cache did not.
/// ↩️The one paint (`layerCompositePaint`) went with the Flutter walk
/// (the-flutter-fx-chain-is-a-second-chain): every row and folder of a
/// frame is laid by the engine's plan. What is left of an alpha-only paint
/// the app draws itself is built by `alphaOnly`.
///
/// ⛔`Color.fromRGBO` DOES NOT CLAMP. Its constructor is `a = opacity`,
/// stored raw: 1.5 stays 1.5 and −0.2 stays −0.2, and what a backend does
/// with an alpha outside the unit range is its own business.
///
/// ⛔A BEHAVIOUR TEST CANNOT CLOSE THIS. Copies that agree today pass every
/// pixel comparison; what fails is the next route someone adds. So the
/// ratchet is a source scan (사본 금지: 전임자 삭제 + 스캔).
void main() {
  test('nothing in lib/ spells the alpha-only colour by hand', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/services/composite_effect_paint.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Prose may NAME the idiom; only code may not spell it.
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('Color.fromRGBO(0, 0, 0,')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'an alpha-only paint is built by `alphaOnly` — a hand-spelled '
          'one is a copy, and the copies already disagreed about the clamp',
    );
  });
}
