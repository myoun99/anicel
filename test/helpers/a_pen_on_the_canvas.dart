import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_in_and_out.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../ui/brush_canvas_test_helpers.dart';

/// Draws [hand], points on the canvas, with a stylus — a sample every
/// [step] from [start] — on a fresh canvas at [zoom]: the dabs laid before
/// the lift and those the stroke committed. [rest] runs between the last
/// move and the lift with the dabs laid so far; [pressures], one per point
/// of [hand], are what the pen reads there; [inAndOut] is the brush's
/// 入り抜き.
Future<({List<BrushDab> beforeLift, List<BrushDab> committed})>
drawWithPen(
  WidgetTester tester,
  List<Offset> hand, {
  required double? stabilization,
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
  BrushInAndOut inAndOut = BrushInAndOut.none,
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
                steadies: stabilization != null,
                stabilization: stabilization ?? 0,
                postStrength: postStrength,
                postBySpeed: postBySpeed,
                postByViewScale: postByViewScale,
                sharpenCorners: sharpenCorners,
              ),
              inAndOut: inAndOut,
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
