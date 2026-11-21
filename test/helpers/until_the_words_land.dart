import 'package:anicel/src/ui/text/word_bake.dart' show BakedWords;
import 'package:flutter_test/flutter_test.dart';

import 'settle_async.dart';

/// Whether no word is waited for — every bake a painter asked for has
/// landed or come to nothing ([BakedWords]).
bool noWordWaits() => BakedWords.instance.debugWaitingWords == 0;

/// Lends both clocks until no word waits for its bake ([noWordWaits]), and
/// pumps the frame that draws the landed ones — so what is read next is
/// drawn from the same bakes, whichever side of a comparison it is.
///
/// 🚨RED WHERE ONE NEVER LANDS (board
/// a-vertical-column-test-compares-letters-that-never-settled, 11-20): the
/// two copies this replaces let the answer go, and a word that never
/// landed was compared as a stand-in on both sides — green, after the
/// whole wait.
Future<void> untilTheWordsLand(WidgetTester tester) async {
  expect(
    await settleAsync(tester, noWordWaits),
    isTrue,
    reason: 'every word a painter waited for landed',
  );
  await tester.pump();
}
