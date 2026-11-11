/// A stroke is drawn on two engines here, and each compiles a stroke's
/// kernels where it is first drawn on: the bound is this file's own
/// (`timeline_grid_tile_generation_test.dart` says why).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/stroke_in_flight.dart';

import '../../helpers/blank_cel.dart';
import '../../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다. 잃는 것은 그리던 획 정도다」 — a
/// stroke in flight is drawn on the engine's stroke, which goes with its
/// device: it is over as the app lets that engine go, as one is whose cel
/// went from under the pen (F-232), and lands nothing however the gesture
/// then ends. The next press draws, on the next engine.
///
/// On the app's own engine, which the test loses.
void main() {
  final strokeLive = <bool>[];
  var commits = 0;

  Widget view() => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InteractiveBrushEditCanvasView(
          celNow: blankCel(
            const CanvasSize(width: 64, height: 64),
            tileSize: 16,
          ),
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          editable: true,
          inputSettings: () => BrushEditCanvasInputSettings.defaults,
          onActiveStrokeChanged: (stroke) =>
              strokeLive.add(stroke != StrokeInFlight.none),
          onSourceStrokeCommitted: (_) => commits += 1,
        ),
      ),
    ),
  );

  /// A stylus pressed on the canvas and drawn a little — still down.
  Future<TestGesture> beginStroke(WidgetTester tester) async {
    final origin = tester.getTopLeft(
      find.byType(InteractiveBrushEditCanvasView),
    );
    final gesture = await tester.startGesture(
      origin + const Offset(8, 8),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    expect(strokeLive, [true], reason: '⛔premise: the stroke is in flight');
    return gesture;
  }

  testWidgets('🚨a stroke in flight as its engine is let go is over — said '
      'after a frame, which comes — and lands nothing however its gesture '
      'ends; the next press draws, and lands', (tester) async {
    await tester.pumpWidget(view());
    final gesture = await beginStroke(tester);

    theAppsEngineLostAndLetGo();

    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(strokeLive, [true, false], reason: 'the host hears it is over');

    await gesture.up();
    await tester.pump();
    expect(strokeLive, [true, false]);
    expect(commits, 0, reason: 'what it was drawn on is gone');

    strokeLive.clear();
    final next = await beginStroke(tester);
    await next.up();
    await tester.pump();
    expect(strokeLive, [true, false]);
    expect(commits, 1);
  });

  testWidgets('a view that went hears no more of the app\'s engine: the '
      'letting go asks nothing of it, nor a frame of the screen it is '
      'not on', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '⛔premise');

    theAppsEngineLostAndLetGo();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
