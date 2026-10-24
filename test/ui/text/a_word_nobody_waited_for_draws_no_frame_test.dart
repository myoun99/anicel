import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';

import '../../helpers/look_test_binding.dart';
import '../../helpers/settle_async.dart';

/// A word's landing asks for its frame only to LOOK: the frame wakes the
/// painters that waited for the word, and is drawn for what they paint
/// again — a word nobody waited for draws nothing (card
/// playback-draws-frames-the-film-did-not-change-in, 10-24: asked for to
/// draw, every landing drew a frame between a playing cut's film frames).
///
/// Counted under the production law ([LookTestBinding]): `flutter_test`'s
/// own binding draws every frame it begins, where this could be deleted with
/// every test green.
void main() {
  final binding = LookTestBinding.ensureInitialized();

  TextPainter word(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 12, color: Color(0xFFD00000)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Pumps until a word's bake lands, and answers whether the frame its
  /// waiters were woken in was drawn.
  Future<bool> landingFrameIsDrawn(WidgetTester tester) async {
    var landings = BakedWords.instance.debugLandingFrames;
    var drawn = binding.drawnFrames;
    bool? landingDrew;
    final landed = await settleAsync(
      tester,
      () => landingDrew != null,
      everyFrame: () {
        if (BakedWords.instance.debugLandingFrames != landings) {
          landingDrew = binding.drawnFrames != drawn;
        }
        landings = BakedWords.instance.debugLandingFrames;
        drawn = binding.drawnFrames;
      },
    );
    if (!landed) {
      fail('fixture: no bake landed');
    }
    return landingDrew!;
  }

  testWidgets('🚨a landing nobody waited for begins its frame — and draws '
      'nothing', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Center(
        child: CustomPaint(
          size: const Size(40, 20),
          painter: _Unwaited(word('ひとりで')),
        ),
      ),
    );

    expect(
      await landingFrameIsDrawn(tester),
      isFalse,
      reason: 'no painter waits for the word, so no pixel moves for it',
    );
  });

  testWidgets('a landing a painter waited for draws its frame — the painter '
      'paints the word again from its bake', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final painted = ValueNotifier(0);
    addTearDown(painted.dispose);
    await tester.pumpWidget(
      Center(
        child: CustomPaint(
          size: const Size(40, 20),
          painter: _Waits(word('まってる'), painted),
        ),
      ),
    );
    final before = painted.value;

    expect(await landingFrameIsDrawn(tester), isTrue);
    expect(painted.value, before + 1, reason: 'fixture: it was the waiter');
  });
}

/// Draws a narrowed word outside [BakedWords.paintAs]: nobody waits for it.
class _Unwaited extends CustomPainter {
  _Unwaited(this.word);

  final TextPainter word;

  @override
  void paint(Canvas canvas, Size size) =>
      paintFittedText(canvas, word, Offset.zero, (x: 0.25, y: 1.0));

  @override
  bool shouldRepaint(_Unwaited oldDelegate) => false;
}

/// Draws a narrowed word as a waiter: woken when its bake lands.
class _Waits extends CustomPainter with RepaintOnWordBakes {
  _Waits(this.word, this.painted);

  final TextPainter word;
  final ValueNotifier<int> painted;

  @override
  void paintWords(Canvas canvas, Size size) {
    painted.value += 1;
    paintFittedText(canvas, word, Offset.zero, (x: 0.25, y: 1.0));
  }

  @override
  bool shouldRepaint(_Waits oldDelegate) => false;
}
