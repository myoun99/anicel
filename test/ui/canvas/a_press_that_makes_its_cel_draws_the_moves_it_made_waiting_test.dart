// 🗣️F-611 (유저 2026-11-18, 아이폰 1093): 「처음구간이 직선으로 이어짐.
// 곡선으로 동그라미 그렸는데 첫 구간이 동그란선이 아니고 직선임」.
//
// A press that makes its cel waits for it ([InteractiveBrushEditCanvasView
// .onPressNeedsCel]): the view stands down until the rebuild hands it the
// cel, and the finger goes on moving meanwhile. Every point the OS saw goes
// into the line (H56) — those moves too. They were dropped, and the stroke
// joined its DOWN to the first move after the wait with one straight step.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

const _center = Offset(200, 200);
const _radius = 80.0;

/// The moves the press makes before its cel is there: a tenth of a
/// second at 120 Hz — the stretch the user saw drawn straight.
const _waited = 12;

void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    testWidgets('a $kind circle that waited for its cel is the circle drawn '
        'where one stood', (tester) async {
      final stood = await _circle(tester, kind, waited: 0);
      final waited = await _circle(tester, kind, waited: _waited);

      // The symptom first: the first fifth of the circle stays on it. A
      // straight step over those 72 degrees comes in to cos(36°) = 0.81
      // of the radius at its middle.
      final opening = [
        for (final dab in waited)
          if (_degreesOf(dab) case final a when a > 2 && a < 72) dab,
      ];
      expect(opening, isNotEmpty);
      for (final dab in opening) {
        expect(
          _offsetOf(dab).distance / _radius,
          closeTo(1, 0.01),
          reason: 'the moves made while the cel was made are in the line',
        );
      }
      // And the whole of it: the same events, the same line.
      expect(
        waited.map(_offsetOf).toList(),
        stood.map(_offsetOf).toList(),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

Offset _offsetOf(BrushDab dab) =>
    Offset(dab.center.x, dab.center.y) - _center;

double _degreesOf(BrushDab dab) {
  final d = _offsetOf(dab);
  return (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
}

/// A circle in half a second at 120 Hz, the view standing down — no cel
/// under it — for its first [waited] moves; the dabs it lands.
Future<List<BrushDab>> _circle(
  WidgetTester tester,
  PointerDeviceKind kind, {
  required int waited,
}) async {
  CanvasTouchContacts.reset();
  await tester.binding.setSurfaceSize(const Size(600, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final landed = <List<BrushDab>>[];
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: 400, height: 400),
    tileSize: 128,
  );
  Future<void> pump({required bool editable}) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveBrushEditCanvasView(
            celNow: () => cel,
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: () => BrushEditCanvasInputSettings(
              correction: BrushCorrection.none,
              size: 6,
            ),
            onSourceStrokeCommitted: (data) => landed.add(data.sourceDabs),
            editable: editable,
            onPressNeedsCel: () => true,
          ),
        ),
      ),
    ),
  );
  await pump(editable: waited == 0);
  const steps = 60;
  for (var i = 0; i <= steps; i += 1) {
    if (waited > 0 && i == waited + 1) {
      await pump(editable: true);
    }
    final angle = 2 * math.pi * i / steps;
    final at = _center + Offset(math.cos(angle), math.sin(angle)) * _radius;
    final time = Duration(microseconds: i * 8333);
    final position = canvasGlobalOffset(tester, at);
    tester.binding.handlePointerEvent(
      i == 0
          ? PointerDownEvent(
              pointer: 1,
              kind: kind,
              position: position,
              timeStamp: time,
              pressure: 1,
              pressureMax: 1,
            )
          : PointerMoveEvent(
              pointer: 1,
              kind: kind,
              position: position,
              timeStamp: time,
              pressure: 1,
              pressureMax: 1,
            ),
    );
    await tester.pump(const Duration(microseconds: 8333));
  }
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: 1,
      kind: kind,
      position: canvasGlobalOffset(
        tester,
        _center + const Offset(_radius, 0),
      ),
      timeStamp: const Duration(milliseconds: 510),
    ),
  );
  await tester.pump();
  // A fresh view for the next circle.
  await tester.pumpWidget(const SizedBox());
  return landed.single;
}
