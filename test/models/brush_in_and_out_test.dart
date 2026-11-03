import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_in_and_out.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_in_and_out_along.dart';

/// 🗣️brush-in-and-out (유저 2026-11-01): Q1 「크기 · 농도, 길이 지정
/// 하나」 — 入り from the minimum to 100%, 抜き from 100% back to it, the
/// lower where they meet; Q2 「뗄 때 고쳐 깐다」 — the 抜き only once the
/// line's length is known.
void main() {
  const both = BrushInAndOut(inLength: 40, outLength: 20);

  test('the 入り runs from its start to its length, the 抜き from its '
      'length before the end to the end', () {
    expect(both.reachAt(0, length: 200), 0);
    expect(both.reachAt(10, length: 200), closeTo(0.25, 1e-12));
    expect(both.reachAt(40, length: 200), 1);
    expect(both.reachAt(100, length: 200), 1);
    expect(both.reachAt(185, length: 200), closeTo(0.75, 1e-12));
    expect(both.reachAt(200, length: 200), 0);
  });

  test('where they meet on a short line, the lower of the two', () {
    // 30 along a line of 40: in at 30/40, out at 10/20.
    expect(both.reachAt(30, length: 40), closeTo(0.5, 1e-12));
    // 10 along it: in at 10/40, out with 30 left of 20 — not yet.
    expect(both.reachAt(10, length: 40), closeTo(0.25, 1e-12));
  });

  test('⛔no 抜き while the line is still being drawn: its end is not known',
      () {
    expect(both.reachAt(200), 1);
    expect(both.reachAt(10), closeTo(0.25, 1e-12));
  });

  test('a dab keeps its minimum of the size and of the flow, and the rest by '
      'how far in or out it is', () {
    final dab = BrushDab(
      center: CanvasPoint(x: 0, y: 0),
      color: 0xFF000000,
      size: 10,
      opacity: 1,
      flow: 0.8,
      hardness: 1,
      pressure: 1,
      sequence: 0,
    );
    const thins = BrushInAndOut(
      inLength: 10,
      sizeMinimum: 0.2,
      flowMinimum: 0.5,
    );
    final halfway = thins.taper(dab, 0.5);
    expect(halfway.size, closeTo(10 * (0.2 + 0.8 * 0.5), 1e-12));
    expect(halfway.flow, closeTo(0.8 * (0.5 + 0.5 * 0.5), 1e-12));
    expect(halfway.opacity, 1, reason: 'the size and the flow only');
    expect(thins.taper(dab, 0).size, closeTo(2, 1e-12));
    expect(identical(thins.taper(dab, 1), dab), isTrue);
  });

  test('a length of 0 or a minimum of 100% takes nothing away', () {
    expect(BrushInAndOut.none.comesIn, isFalse);
    expect(BrushInAndOut.none.goesOut, isFalse);
    expect(
      const BrushInAndOut(inLength: 30, outLength: 30, sizeMinimum: 1)
          .comesIn,
      isFalse,
    );
    expect(const BrushInAndOut(outLength: 30).goesOut, isTrue);
    expect(const BrushInAndOut(outLength: 30).comesIn, isFalse);
    expect(
      const BrushInAndOut(inLength: 30, sizeMinimum: 1, flowMinimum: 0.5)
          .comesIn,
      isTrue,
    );
  });

  test('a dab is as far along as the line has come less how far it lies '
      'behind', () {
    final along = BrushInAndOutAlong(
      const BrushInAndOut(inLength: 100),
      from: CanvasPoint(x: 0, y: 0),
    );
    BrushDab at(double x, double y) => BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: 10,
      opacity: 1,
      flow: 1,
      hardness: 1,
      pressure: 1,
      sequence: 0,
    );
    along
      ..goTo(CanvasPoint(x: 30, y: 0))
      ..goTo(CanvasPoint(x: 30, y: 40));
    // 30 across and 40 down: 70 come. A dab 10 back up the line is at 60.
    final laid = along.taper([at(30, 30)]);
    expect(laid.single.size, closeTo(10 * 0.6, 1e-9));
    expect(
      lengthThrough([
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 30, y: 0),
        CanvasPoint(x: 30, y: 40),
      ]),
      70,
    );
  });

  test('a brush keeps it in its preset — written only off the default', () {
    final plain = BrushSettings();
    expect(plain.toJson().containsKey('inAndOut'), isFalse);
    expect(BrushSettings.fromJson(plain.toJson()).inAndOut, BrushInAndOut.none);

    const tapered = BrushInAndOut(
      inLength: 12,
      outLength: 34,
      sizeMinimum: 0.25,
      flowMinimum: 0.75,
    );
    final kept = BrushSettings(inAndOut: tapered);
    expect(BrushSettings.fromJson(kept.toJson()).inAndOut, tapered);
    expect(BrushSettings.fromJson(kept.toJson()), kept);
  });

  test('⛔a length past the longest or a minimum past 100% is refused', () {
    expect(
      () => BrushSettings(
        inAndOut: const BrushInAndOut(inLength: BrushInAndOut.maxLength + 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => BrushSettings(inAndOut: const BrushInAndOut(outLength: -1)),
      throwsArgumentError,
    );
    expect(
      () => BrushSettings(inAndOut: const BrushInAndOut(sizeMinimum: 1.5)),
      throwsArgumentError,
    );
    expect(
      () => BrushSettings(inAndOut: const BrushInAndOut(flowMinimum: -0.1)),
      throwsArgumentError,
    );
  });
}
