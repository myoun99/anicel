import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_ui_scale.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';

import '../../helpers/scaled_test_binding.dart';
import '../../helpers/word_bakes.dart';

/// F-224 — a narrowed word's bake is cut for the ROOT TRANSFORM's pixels.
///
/// The app's UI scale multiplies into the root device matrix and not into
/// the view's own ratio, so a bake cut for the view's ratio would land on
/// the screen scaled by the GPU — and a narrowed glyph the GPU shrinks
/// speckles, which is the thing the bake exists to stop. The binding here
/// wears the production override, so the root matrix is the real one.
void main() {
  ScaledTestBinding.ensureInitialized();
  tearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);

  testWidgets('at 125% on a 1.0 monitor the bake is cut at 1.25', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);
    AppUiScale.value.value = 1.25;
    await tester.pumpWidget(const SizedBox());

    final word = TextPainter(
      text: const TextSpan(
        text: 'ことば',
        style: TextStyle(fontSize: 12, color: Color(0xFF000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const fit = (x: 0.25, y: 1.0);
    void paintIt(Canvas canvas) =>
        paintFittedText(canvas, word, Offset.zero, fit);
    expect(paintIt, paints..paragraph());
    await pumpUntilAWordBakeLands(tester);
    expect(
      paintIt,
      paints..drawImageRect(
        source: Rect.fromLTWH(
          0,
          0,
          (word.width * fit.x * 1.25).ceil() + 2.0,
          (word.height * 1.25).ceil() + 2.0,
        ),
      ),
    );
  });
}
