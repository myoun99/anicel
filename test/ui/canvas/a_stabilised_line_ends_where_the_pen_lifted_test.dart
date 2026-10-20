import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🗣️F-418 (유저 2026-10-20): Clip Studio's 손떨림 보정. Q2 「과거 결정
/// 무시해도됨. 클튜는 100으로 하면 선을 떼면 바로 뗀 자리까지 선이 감」 · Q4
/// 「곧장 커서로 간다 — 꺾임을 가로지른다」.
///
/// The lift is where the 後補正 lays the line again too (Q7 「뗄 때 다듬은
/// 선으로 바뀐다」).
///
/// ↩️This file pinned the opposite under H45 (2026-09-28): 「따라잡지
/// 않는다 — 선은 붓이 있던 자리에서 끝난다」, while the brush hung a rope
/// behind a pen held still.
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

  // Quick and straight right: a sample every 8 ms.
  const straight = [
    Offset(10, 20),
    Offset(40, 20),
    Offset(70, 20),
    Offset(100, 20),
    Offset(130, 20),
    Offset(160, 20),
  ];

  testWidgets('the line runs behind a quick pen; 0 steadies nothing', (
    tester,
  ) async {
    final steadied = await _draw(tester, straight, stabilization: 100);
    expect(_reach(steadied.beforeLift), lessThan(100));

    final plain = await _draw(tester, straight, stabilization: 0);
    expect(_reach(plain.beforeLift), closeTo(160, 1));
  });

  testWidgets('the pen lifts and the line goes to where it lifted '
      '(F-418-Q2)', (tester) async {
    final steadied = await _draw(tester, straight, stabilization: 100);
    expect(_reach(steadied.committed), closeTo(160, 1));
    expect(steadied.committed.last.center.y, closeTo(20, 1e-6));
  });

  testWidgets('it goes there straight, across the corner the pen turned '
      '(F-418-Q4)', (tester) async {
    const corner = [
      Offset(10, 8),
      Offset(50, 8),
      Offset(90, 8),
      Offset(90, 20),
      Offset(90, 32),
    ];
    bool insideTheCorner(BrushDab dab) =>
        dab.center.x < 85 && dab.center.y > 12;

    final steadied = await _draw(tester, corner, stabilization: 100);
    final end = steadied.committed.last.center;
    expect(end.x, closeTo(90, 1e-6));
    expect(end.y, closeTo(32, 1e-6));
    expect(steadied.committed.where(insideTheCorner), isNotEmpty);

    final plain = await _draw(tester, corner, stabilization: 0);
    expect(
      plain.committed.where(insideTheCorner),
      isEmpty,
      reason: 'the pen itself went round the corner',
    );
  });

  testWidgets("the line's clock starts at the press", (tester) async {
    // The move comes 8 ms after the press: the line closes that much of
    // the way, not the share of the 16 ms since the clocks' zero.
    final lag = const BrushCorrection(stabilization: 30).lagAt(0);
    final share = 1 - math.exp(-8000 / lag.inMicroseconds);
    final steadied = await _draw(tester, const [
      Offset(10, 20),
      Offset(40, 20),
    ], stabilization: 30);
    expect(
      _reach(steadied.beforeLift),
      closeTo(10 + 30 * share, 1.01),
      reason: 'within a dab spacing of where the line got to',
    );
  });

  testWidgets('the line carries what the pen read where the line is — a '
      'harder press reaches it as the line does — and lifts with what the '
      'pen read last', (tester) async {
    const pressures = [0.2, 0.2, 0.2, 1.0, 1.0, 1.0];
    final steadied = await _draw(
      tester,
      straight,
      stabilization: 100,
      pressures: pressures,
    );
    final pressed = steadied.beforeLift.map((dab) => dab.pressure);
    expect(pressed.reduce(math.max), lessThan(0.5));
    expect(pressed.reduce(math.max), greaterThan(0.2));
    expect(steadied.committed.last.pressure, closeTo(1.0, 1e-9));

    final plain = await _draw(
      tester,
      straight,
      stabilization: 0,
      pressures: pressures,
    );
    expect(
      plain.beforeLift.map((dab) => dab.pressure).reduce(math.max),
      closeTo(1.0, 1e-9),
      reason: 'the pen itself pressed harder',
    );
  });

  testWidgets('a resting pen\'s line goes on reading what the pen read '
      'where the line is, frame by frame', (tester) async {
    late List<double> resting;
    await _draw(
      tester,
      straight,
      stabilization: 100,
      pressures: const [0.2, 0.2, 0.2, 1.0, 1.0, 1.0],
      rest: (laid) async {
        final before = laid.length;
        for (var frame = 0; frame < 4; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        resting = [for (final dab in laid.skip(before)) dab.pressure];
      },
    );
    expect(resting, isNotEmpty, reason: 'the frames moved the line');
    expect(resting.reduce(math.max), lessThan(0.7));
  });

  testWidgets('a resting pen is reached before it lifts — the line keeps '
      'going, on screen the frame it moves, and then asks for no more '
      'frames', (tester) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 16);
    addTearDown(overlay.dispose);
    final steadied = await _draw(
      tester,
      straight,
      stabilization: 30,
      overlay: overlay,
      rest: (laid) async {
        final reaches = <double>[];
        for (var frame = 0; frame < 60; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
          reaches.add(_reach(laid));
          expect(
            _reach(overlay.dabs),
            reaches.last,
            reason: 'frame $frame: shown the frame it was laid',
          );
        }
        expect(reaches.first, lessThan(150), reason: 'it was behind');
        expect(reaches.last, closeTo(160, 1), reason: 'it got there');
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
    expect(_reach(steadied.committed), closeTo(160, 1));
  });

  // A wobble of 2 px either side of y = 20, a sample every 8 ms.
  const wobbly = [
    Offset(10, 20),
    Offset(30, 22),
    Offset(50, 18),
    Offset(70, 22),
    Offset(90, 18),
    Offset(110, 22),
    Offset(130, 18),
    Offset(150, 20),
  ];

  testWidgets('the pen lifts and the line is laid again with its wobble '
      'taken out (後補正, F-418-Q7)', (tester) async {
    final smoothed = await _draw(
      tester,
      wobbly,
      stabilization: 0,
      postStrength: 40,
    );
    expect(
      _wobble(smoothed.beforeLift),
      greaterThan(1),
      reason: 'drawn as the pen went',
    );
    expect(_wobble(smoothed.committed), lessThan(1e-6), reason: 'landed even');
    expect(smoothed.committed.first.center.x, closeTo(10, 1e-6));
    expect(_reach(smoothed.committed), closeTo(150, 1));
  });

  testWidgets('a brush that takes nothing out lands what it laid', (
    tester,
  ) async {
    final plain = await _draw(tester, wobbly, stabilization: 0);
    expect(
      plain.committed.map((dab) => dab.center),
      plain.beforeLift.map((dab) => dab.center),
    );
  });

  testWidgets('the line laid again carries what the pen read along it', (
    tester,
  ) async {
    const pressures = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
    final smoothed = await _draw(
      tester,
      wobbly,
      stabilization: 0,
      postStrength: 40,
      pressures: pressures,
    );
    final pressed = smoothed.committed.map((dab) => dab.pressure).toList();
    expect(pressed.first, closeTo(0.1, 1e-9));
    expect(pressed.last, closeTo(0.8, 1e-9));
    // The pen pressed 0.1 more every 20 px along x.
    for (final dab in smoothed.committed) {
      expect(
        dab.pressure,
        closeTo(0.1 + (dab.center.x - 10) / 200, 0.05),
        reason: 'at x ${dab.center.x}: as hard as the pen pressed there — '
            'not as it pressed last',
      );
    }
  });

  testWidgets('by the speed, a line drawn slowly keeps the wobble a quick '
      'one loses (速度による調整)', (tester) async {
    Future<double> wobbleAt(Duration step) async => _wobble(
      (await _draw(
        tester,
        wobbly,
        stabilization: 0,
        postStrength: 40,
        postBySpeed: true,
        step: step,
      )).committed,
    );
    expect(await wobbleAt(const Duration(milliseconds: 8)), lessThan(1e-6));
    expect(await wobbleAt(const Duration(milliseconds: 400)), greaterThan(1));
  });

  testWidgets('a brush that keeps its corners draws a V to its point; one '
      'that does not cuts across it (角をとがらせる, F-418-Q11)', (
    tester,
  ) async {
    const v = [
      Offset(20, 4),
      Offset(30, 14),
      Offset(40, 24),
      Offset(50, 34),
      Offset(60, 24),
      Offset(70, 14),
      Offset(80, 4),
    ];
    final point = CanvasPoint(x: 50, y: 34);
    double nearest(List<BrushDab> dabs) =>
        dabs.map((dab) => dab.center.distanceTo(point)).reduce(math.min);

    final kept = await _draw(
      tester,
      v,
      stabilization: 100,
      sharpenCorners: true,
    );
    expect(nearest(kept.committed), lessThan(1.5));

    final cut = await _draw(tester, v, stabilization: 100);
    expect(nearest(cut.committed), greaterThan(5));
  });

  testWidgets('the 後補正 keeps them too: a V shallower than it straightens '
      'is laid again to its point, each side smoothed on its own — and '
      'flattened by a brush that does not keep them (角をとがらせる)', (
    tester,
  ) async {
    // 20 deep, under the 25 that 後補正 100 straightens.
    const v = [
      Offset(30, 4),
      Offset(40, 14),
      Offset(50, 24),
      Offset(60, 14),
      Offset(70, 4),
    ];
    final point = CanvasPoint(x: 50, y: 24);
    double nearest(List<BrushDab> dabs) =>
        dabs.map((dab) => dab.center.distanceTo(point)).reduce(math.min);

    final kept = await _draw(
      tester,
      v,
      stabilization: 0,
      postStrength: 100,
      sharpenCorners: true,
    );
    expect(nearest(kept.committed), lessThan(1.5));

    final cut = await _draw(tester, v, stabilization: 0, postStrength: 100);
    expect(nearest(cut.committed), greaterThan(15));
  });

  testWidgets('by the view, a wobble is measured on the screen: zoomed in, '
      'the same wobble on the canvas is a bigger one and stays '
      '(表示倍率による調整)', (tester) async {
    Future<double> wobbleAt(double zoom, {bool byView = true}) async =>
        _wobble(
          (await _draw(
            tester,
            wobbly,
            stabilization: 0,
            postStrength: 10,
            postByViewScale: byView,
            zoom: zoom,
          )).committed,
        );
    expect(await wobbleAt(1), lessThan(1e-6));
    expect(await wobbleAt(4), greaterThan(1));
    expect(
      await wobbleAt(4, byView: false),
      lessThan(1e-6),
      reason: 'measured on the canvas, it is the wobble it was at 100%',
    );
  });

  testWidgets('laid again, a stroke keeps its own roll of the dice: two '
      'strokes along one line scatter apart, as any two strokes do', (
    tester,
  ) async {
    Future<List<(double, double)>> laid(Duration start) async => [
      for (final dab in (await _draw(
        tester,
        wobbly,
        stabilization: 0,
        postStrength: 40,
        scatter: 2,
        start: start,
      )).committed)
        (dab.center.x, dab.center.y),
    ];
    final first = await laid(Duration.zero);
    expect(
      await laid(Duration.zero),
      first,
      reason: 'fixture: one roll, one scatter',
    );
    expect(await laid(const Duration(seconds: 1)), isNot(first));
  });
}

/// How far [dabs] stray from y = 20.
double _wobble(List<BrushDab> dabs) => dabs
    .map((dab) => (dab.center.y - 20).abs())
    .reduce((a, b) => a > b ? a : b);

double _reach(List<BrushDab> dabs) =>
    dabs.map((dab) => dab.center.x).reduce((a, b) => a > b ? a : b);

/// Draws [hand], points on the canvas, with a stylus — a sample every
/// [step] from [start] — on a fresh canvas at [zoom]: the dabs laid before
/// the lift and those the stroke committed. [rest] runs between the last
/// move and the lift with the dabs laid so far; [pressures], one per point
/// of [hand], are what the pen reads there.
Future<({List<BrushDab> beforeLift, List<BrushDab> committed})> _draw(
  WidgetTester tester,
  List<Offset> hand, {
  required double stabilization,
  double postStrength = 0,
  bool postBySpeed = false,
  bool postByViewScale = true,
  bool sharpenCorners = false,
  double scatter = 0,
  double zoom = 1,
  Duration step = const Duration(milliseconds: 8),
  Duration start = Duration.zero,
  ActiveStrokeOverlayModel? overlay,
  Future<void> Function(List<BrushDab> laid)? rest,
  List<double>? pressures,
}) async {
  final committed = <List<BrushDab>>[];
  final laid = debugStrokeDabsLaid = <BrushDab>[];
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: 200, height: 40),
    tileSize: 16,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveBrushEditCanvasView(
            key: UniqueKey(),
            celNow: () => cel,
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            viewport: CanvasViewport(zoom: zoom),
            inputSettings: () => BrushEditCanvasInputSettings(
              size: 4,
              scatterRadiusRatio: scatter,
              correction: BrushCorrection(
                stabilization: stabilization,
                postStrength: postStrength,
                postBySpeed: postBySpeed,
                postByViewScale: postByViewScale,
                sharpenCorners: sharpenCorners,
              ),
            ),
            overlayModel: overlay,
            onSourceStrokeCommitted: (data) => committed.add(data.sourceDabs),
          ),
        ),
      ),
    ),
  );

  var time = start;
  var sample = 0;
  PointerEvent at(Offset local, {required bool down}) {
    final pressure = pressures?[sample] ?? 1.0;
    sample += 1;
    time += step;
    final position = canvasGlobalOffset(tester, local * zoom);
    return down
        ? PointerDownEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: position,
            timeStamp: time,
            pressure: pressure,
            pressureMin: 0,
            pressureMax: 1,
          )
        : PointerMoveEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: position,
            timeStamp: time,
            pressure: pressure,
            pressureMin: 0,
            pressureMax: 1,
          );
  }

  tester.binding.handlePointerEvent(at(hand.first, down: true));
  await tester.pump();
  for (final point in hand.skip(1)) {
    tester.binding.handlePointerEvent(at(point, down: false));
    await tester.pump();
  }
  await rest?.call(laid);
  final beforeLift = List<BrushDab>.of(laid);
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: canvasGlobalOffset(tester, hand.last * zoom),
      timeStamp: time + step,
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(committed, hasLength(1), reason: 'one stroke landed');
  return (beforeLift: beforeLift, committed: committed.single);
}
