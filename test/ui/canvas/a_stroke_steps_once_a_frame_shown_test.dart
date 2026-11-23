import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/picture_up_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🚨★★★ONE STEP OF A STROKE A FRAME SHOWN, NOT ONE A FRAME BUILT
/// (`_BrushEditOverlay.stepPendingOverlayDabs`; card
/// the-galaxy-tab-canvas-went-slow-on-build-1095, 2026-11-23): while a frame
/// of the canvas's pictures is being drawn, the pen's samples wait, and go
/// on the stroke as ONE step once it is up — the same dabs, in the same
/// order. 🗣️유저 (build 1101, Galaxy Tab) 「그을수록 같은선안에서 점점 느려지고
/// … 선떼고 5초뒤에 그은게 한번에 나오는정도」: a step went to the engine at
/// every frame the app built, the screen drawing one at a time, and the
/// steps piled up behind it without end.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// A pen pressed on a canvas whose pictures go up [together] — on none
  /// where null — drawn on [overlay], its line [steadied] or not; and how
  /// it moves, a sample a call, 8 ms apart.
  Future<({void Function(Offset at) move, void Function(Offset at) lift})>
  aPenOn(
    WidgetTester tester, {
    required ActiveStrokeOverlayModel overlay,
    required PicturesUpTogether? together,
    bool steadied = false,
  }) async {
    final cel = BitmapSurface(
      canvasSize: const CanvasSize(width: 400, height: 40),
      tileSize: 128,
    );
    final brush = InteractiveBrushEditCanvasView(
      celNow: () => cel,
      layerId: const LayerId('layer-a'),
      frameId: const FrameId('frame-a'),
      viewport: CanvasViewport(),
      inputSettings: () => BrushEditCanvasInputSettings(
        size: 4,
        correction: BrushCorrection(steadies: steadied),
      ),
      overlayModel: overlay,
      onSourceStrokeCommitted: (_) {},
    );
    final view = PictureUpView();
    addTearDown(view.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: together == null
                ? brush
                : PictureUpViewScope(
                    view: view,
                    together: together,
                    child: brush,
                  ),
          ),
        ),
      ),
    );
    var time = Duration.zero;
    const kind = PointerDeviceKind.stylus;
    tester.binding.handlePointerEvent(
      PointerAddedEvent(
        kind: kind,
        position: canvasGlobalOffset(tester, const Offset(10, 20)),
      ),
    );
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 1,
        kind: kind,
        buttons: kPrimaryButton,
        position: canvasGlobalOffset(tester, const Offset(10, 20)),
        timeStamp: time,
        pressure: 1,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
    return (
      move: (Offset at) {
        time += const Duration(milliseconds: 8);
        tester.binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: 1,
            kind: kind,
            buttons: kPrimaryButton,
            position: canvasGlobalOffset(tester, at),
            timeStamp: time,
            pressure: 1,
            pressureMin: 0,
            pressureMax: 1,
          ),
        );
      },
      lift: (Offset at) {
        time += const Duration(milliseconds: 8);
        tester.binding.handlePointerEvent(
          PointerUpEvent(
            pointer: 1,
            kind: kind,
            position: canvasGlobalOffset(tester, at),
            timeStamp: time,
          ),
        );
      },
    );
  }

  for (final steadied in const [false, true]) {
    final line = steadied ? 'a steadied line' : 'a line as the pen went';

    testWidgets('🚨the samples of the frames built while one is drawn go on '
        'the stroke as one step once it is up ($line)', (tester) async {
      final overlay = ActiveStrokeOverlayModel(tileSize: 128);
      addTearDown(overlay.dispose);
      final together = PicturesUpTogether();
      final pen = await aPenOn(
        tester,
        overlay: overlay,
        together: together,
        steadied: steadied,
      );
      pen.move(const Offset(40, 20));
      await tester.pump();
      final before = overlay.dabs.length;
      expect(before, greaterThan(0), reason: 'no frame drawn: a step');

      final drawn = Completer<void>();
      unawaited(together.joined(drawn.future));
      final stepsBefore = overlay.moveMark.count;
      for (final x in const [80.0, 120.0, 160.0, 200.0]) {
        pen.move(Offset(x, 20));
        await tester.pump();
      }
      expect(
        overlay.dabs.length,
        before,
        reason: 'nothing goes on the stroke while a frame is drawn',
      );
      expect(overlay.moveMark.count, stepsBefore);

      // Up, and no frame built since: what a steadied line lays at the next
      // frame is that frame's own step.
      drawn.complete();
      await tester.idle();
      expect(
        overlay.dabs.length,
        greaterThan(before),
        reason: 'on the stroke once the frame is up',
      );
      expect(
        overlay.moveMark.count,
        stepsBefore + 1,
        reason: 'the four frames\' samples, one step',
      );

      await tester.pump();
      pen.lift(const Offset(200, 20));
      await tester.pump();
      await tester.pump();
    });

    testWidgets('🚨a pen lifted while a frame is drawn lays every sample it '
        'held before the stroke lands ($line)', (tester) async {
      final overlay = ActiveStrokeOverlayModel(tileSize: 128);
      addTearDown(overlay.dispose);
      final together = PicturesUpTogether();
      final pen = await aPenOn(
        tester,
        overlay: overlay,
        together: together,
        steadied: steadied,
      );
      pen.move(const Offset(40, 20));
      await tester.pump();

      final drawn = Completer<void>();
      unawaited(together.joined(drawn.future));
      pen.move(const Offset(120, 20));
      await tester.pump();
      pen.move(const Offset(200, 20));
      await tester.pump();
      final held = overlay.dabs.length;
      // The stroke lands at the lift and the overlay is let go of there:
      // what it took before that is read as it takes it.
      var most = held;
      void took() => most = overlay.dabs.length > most
          ? overlay.dabs.length
          : most;
      overlay.addListener(took);
      addTearDown(() => overlay.removeListener(took));
      pen.lift(const Offset(200, 20));
      await tester.pump();

      expect(
        most,
        greaterThan(held),
        reason: 'the samples held went on the stroke at the lift, the frame '
            'still being drawn',
      );
      drawn.complete();
      await tester.pump();
      await tester.pump();
    });
  }

  testWidgets('a stroke under no canvas\'s pictures steps at every frame', (
    tester,
  ) async {
    // A host of the view alone: no canvas's pictures to wait for.
    final overlay = ActiveStrokeOverlayModel(tileSize: 128);
    addTearDown(overlay.dispose);
    final pen = await aPenOn(tester, overlay: overlay, together: null);
    var steps = overlay.moveMark.count;
    for (final x in const [60.0, 110.0, 160.0]) {
      pen.move(Offset(x, 20));
      await tester.pump();
      expect(overlay.moveMark.count, steps + 1);
      steps = overlay.moveMark.count;
    }
    pen.lift(const Offset(160, 20));
    await tester.pump();
    await tester.pump();
  });
}
