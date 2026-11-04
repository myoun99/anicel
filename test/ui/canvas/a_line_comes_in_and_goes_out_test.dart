import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_in_and_out.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../../helpers/a_pen_on_the_canvas.dart';

/// 🗣️brush-in-and-out (유저 2026-11-01): Clip Studio's 入り抜き. Q1 「크기
/// · 농도, 길이 지정 하나」 — the line comes in from its minimum over a
/// length, and goes out to it over another, the lower where they meet; Q2
/// 「뗄 때 고쳐 깐다」 — where the line ends is known when the pen lifts, so
/// it is drawn to its end at full and laid again there going out.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    debugStrokeDabsLaid = null;
  });

  // Straight right, 160 px from x 10 to x 170 — the line's own length.
  final straight = [for (var x = 10.0; x <= 170; x += 10) Offset(x, 20)];
  const size = 4.0;

  testWidgets('it comes in as it is drawn: thin at the press, full once it '
      'is its length in — and lands as it was shown', (tester) async {
    final drawn = await drawWithPen(
      tester,
      straight,
      stabilization: null,
      inAndOut: const BrushInAndOut(inLength: 40),
    );
    for (final dab in drawn.beforeLift) {
      expect(
        _across(dab),
        closeTo(size * math.min(1, (dab.center.x - 10) / 40), _quarter),
        reason: 'at x ${dab.center.x}',
      );
    }
    expect(
      _across(drawn.beforeLift.first),
      lessThanOrEqualTo(0.25),
      reason: 'from next to nothing: the finest dab laid',
    );
    expect(
      _looks(drawn.committed),
      _looks(drawn.beforeLift),
      reason: 'nothing to lay again',
    );
  });

  testWidgets('it goes out when the pen lifts: full to its end while drawn, '
      'thin at its end once laid again', (tester) async {
    final drawn = await drawWithPen(
      tester,
      straight,
      stabilization: null,
      inAndOut: const BrushInAndOut(outLength: 40),
    );
    expect(
      drawn.beforeLift.map(_across),
      everyElement(closeTo(size, 1e-9)),
      reason: 'its end is not known yet',
    );
    expect(drawn.committed.last.center.x, closeTo(170, 1e-6));
    for (final dab in drawn.committed) {
      expect(
        _across(dab),
        closeTo(size * math.min(1, (170 - dab.center.x) / 40), _quarter),
        reason: 'at x ${dab.center.x}',
      );
    }
    expect(
      drawn.committed.map((dab) => dab.center.x),
      drawn.beforeLift.map((dab) => dab.center.x),
      reason: 'laid again where it was laid',
    );
  });

  testWidgets('on a line shorter than the two, the lower of them', (
    tester,
  ) async {
    final drawn = await drawWithPen(
      tester,
      straight,
      stabilization: null,
      inAndOut: const BrushInAndOut(inLength: 100, outLength: 100),
    );
    for (final dab in drawn.committed) {
      final travelled = dab.center.x - 10;
      final reach = math.min(travelled / 100, (160 - travelled) / 100);
      expect(
        _across(dab),
        closeTo(size * reach, _quarter),
        reason: 'at x ${dab.center.x}',
      );
    }
  });

  testWidgets('the flow keeps its own minimum, and the size its own', (
    tester,
  ) async {
    final drawn = await drawWithPen(
      tester,
      straight,
      stabilization: null,
      inAndOut: const BrushInAndOut(
        inLength: 40,
        sizeMinimum: 1,
        flowMinimum: 0.25,
      ),
    );
    final full = drawn.committed.last.flow;
    for (final dab in drawn.committed) {
      final reach = math.min(1.0, (dab.center.x - 10) / 40);
      expect(dab.size, closeTo(size, 1e-9), reason: 'at x ${dab.center.x}');
      expect(
        dab.flow,
        closeTo(full * (0.25 + 0.75 * reach), 1e-9),
        reason: 'at x ${dab.center.x}',
      );
    }
  });

  testWidgets('with a 後補正 too it is laid again once — smoothed, and going '
      'out along the smoothed line', (tester) async {
    const wobbly = [
      Offset(10, 20),
      Offset(30, 23),
      Offset(50, 17),
      Offset(70, 23),
      Offset(90, 17),
      Offset(110, 23),
      Offset(130, 17),
      Offset(150, 20),
    ];
    final drawn = await drawWithPen(
      tester,
      wobbly,
      stabilization: null,
      postStrength: 40,
      inAndOut: const BrushInAndOut(outLength: 30),
    );
    final wobble = drawn.committed
        .map((dab) => (dab.center.y - 20).abs())
        .reduce(math.max);
    expect(wobble, lessThan(1e-6), reason: 'smoothed');
    expect(_across(drawn.committed.last), lessThan(0.5), reason: 'gone out');
    expect(_across(drawn.committed.first), closeTo(size, 1e-9));
  });
}

/// How far [_across] may be from the width asked for: a size is laid in
/// quarter-pixel steps, from a quarter up
/// (`BrushTipStampCache.quantizeSizeStep`).
const _quarter = 0.25 + 1e-9;

/// How wide [dab] lands: a dab under a pixel lands one pixel across at its
/// width's share of its opacity (`liftedToOnePixel`).
double _across(BrushDab dab) => dab.size * dab.opacity;

List<(double, double, double, double)> _looks(List<BrushDab> dabs) => [
  for (final dab in dabs) (dab.center.x, dab.center.y, dab.size, dab.flow),
];
