import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_bake.dart';

/// Pumps until a narrowed word's bake lands (F-224). The bake reads its
/// pixels back off the engine, which answers in real time — so real time is
/// let pass between the frames, and the frame after a landing is pumped so
/// the painters that listen for it have painted again.
Future<void> pumpUntilAWordBakeLands(WidgetTester tester) async {
  final before = BakedWords.instance.landed.value;
  for (var i = 0; i < 400; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (BakedWords.instance.landed.value != before) {
      return;
    }
  }
  fail('fixture: no bake landed');
}
