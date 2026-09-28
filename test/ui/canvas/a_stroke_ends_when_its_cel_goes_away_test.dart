import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

/// 🗣️F-232 (유저 2026-09-29): 「어느 순간 언두가 안먹히는상황이있음 … 키보드로
/// 언두가 안되길래 … 왼쪽띠 버튼눌러봤는데도 안되서」.
///
/// A stroke that began on a cel and lost it before the pen lifted never
/// ENDED: the lift and the cancel both stood behind `editable`, and a view
/// taken away mid-stroke reset itself without a word. The host went on
/// believing the pen was down and refused every seek — so an undo whose
/// edit lay on another frame, which walks there first (I-41), walked
/// nowhere, press after press. The host hears the end now, whichever way
/// the stroke ends, and nothing of a stroke with no cel under it lands.
void main() {
  final strokeLive = <bool>[];
  var commits = 0;

  setUp(() {
    strokeLive.clear();
    commits = 0;
  });

  Widget view({bool editable = true}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InteractiveBrushEditCanvasView(
          sessionState: BrushEditSessionState(
            canvasState: CanvasSurfaceState(
              currentSurface: BitmapSurface(
                canvasSize: const CanvasSize(width: 64, height: 64),
                tileSize: 16,
              ),
            ),
            materializationHistoryState:
                BrushBitmapMaterializationHistoryState(),
          ),
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          editable: editable,
          inputSettings: () => BrushEditCanvasInputSettings.defaults,
          onActiveStrokeChanged: strokeLive.add,
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
    expect(strokeLive, [true], reason: 'premise: the stroke is in flight');
    return gesture;
  }

  Future<void> stroke(WidgetTester tester) async {
    final gesture = await beginStroke(tester);
    await gesture.up();
    await tester.pump();
  }

  testWidgets('🎯a pen lifted after its cel went away still ends the stroke, '
      'lands nothing, and the next press draws', (tester) async {
    await tester.pumpWidget(view());
    final gesture = await beginStroke(tester);

    await tester.pumpWidget(view(editable: false));
    await gesture.up();
    await tester.pump();

    expect(strokeLive, [true, false], reason: 'the host hears the pen go up');
    expect(commits, 0, reason: 'no cel under the stroke, nothing lands');

    await tester.pumpWidget(view());
    strokeLive.clear();
    await stroke(tester);
    expect(
      strokeLive,
      [true, false],
      reason: 'the view let go of the pointer, so the next press drew',
    );
    expect(commits, 1);
  });

  testWidgets('a cancel after the cel went away ends the stroke too', (
    tester,
  ) async {
    await tester.pumpWidget(view());
    final gesture = await beginStroke(tester);

    await tester.pumpWidget(view(editable: false));
    await gesture.cancel();
    await tester.pump();

    expect(strokeLive, [true, false]);
    expect(commits, 0);
  });

  testWidgets('a view taken away mid-stroke says the stroke is over, after '
      'the frame — once, however the gesture then ends', (tester) async {
    await tester.pumpWidget(view());
    final gesture = await beginStroke(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(strokeLive, [true, false], reason: 'the host hears it is over');

    await gesture.up();
    await tester.pump();
    expect(strokeLive, [true, false]);
    expect(commits, 0, reason: 'what it would land on is gone');
  });
}
