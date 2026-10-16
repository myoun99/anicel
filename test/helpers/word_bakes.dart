import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_bake.dart';

import 'settle_async.dart';

/// Pumps until a narrowed word's bake lands (F-224). The bake reads its
/// pixels back off the engine, which answers in real time — so real time is
/// let pass between the frames ([settleAsync]), and the frame after a
/// landing is pumped so the painters that waited for it have painted again.
Future<void> pumpUntilAWordBakeLands(WidgetTester tester) async {
  final before = BakedWords.instance.debugLandingFrames;
  final landed = await settleAsync(
    tester,
    () => BakedWords.instance.debugLandingFrames != before,
  );
  if (!landed) {
    fail('fixture: no bake landed');
  }
}
