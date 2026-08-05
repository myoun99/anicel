import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import 'brush_canvas_test_helpers.dart';

void main() {
  _settlingTileGroup();
  group('InteractiveBrushEditCanvasView', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    testWidgets(
      'builds Listener and BrushEditCanvasView without GestureDetector',
      (tester) async {
        final sessionState = _sessionState();
        await tester.pumpWidget(
          _app(
            InteractiveBrushEditCanvasView(
              sessionState: sessionState,
              layerId: layerId,
              frameId: frameId,
              inputSettings: BrushEditCanvasInputSettings(),
              onSourceStrokeCommitted: (_) {},
              showTransparentBackground: false,
            ),
          ),
        );

        final viewFinder = find.byType(InteractiveBrushEditCanvasView);
        expect(viewFinder, findsOneWidget);
        expect(
          find.descendant(
            of: viewFinder,
            matching: find.byKey(
              const ValueKey<String>(
                'interactive-brush-edit-canvas-view-listener',
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: viewFinder,
            matching: find.byType(BrushEditCanvasView),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: viewFinder,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );

        final canvasView = tester.widget<BrushEditCanvasView>(
          find.descendant(
            of: viewFinder,
            matching: find.byType(BrushEditCanvasView),
          ),
        );
        expect(identical(canvasView.sessionState, sessionState), isTrue);
        expect(canvasView.showTransparentBackground, isFalse);
      },
    );

    testWidgets('the next pen-down does not take away what is covering for '
        'the last stroke', (tester) async {
      // The pen-up handoff misses by construction — the tile revision is
      // written inside the decode callback and the final flush runs in
      // the same synchronous handler — so after a commit the overlay is
      // holding images that stand in for COMMITTED tiles which cannot
      // paint themselves yet. Resetting it at the next pen-down put those
      // coordinates back on the painter's stale fallback, the PRE-stroke
      // tile, and the stroke the user had just finished vanished in
      // tile-shaped patches. Measured: 2 of 5 promoted coordinates went
      // overlay → stale at a 0 ms inter-stroke gap.
      //
      // The oracle is the model's own state rather than the raster,
      // because this harness reports commits instead of applying them, so
      // there is no committed surface to composite against. What it pins
      // is the mechanism: an image kept here is one the painter draws
      // (the overlay-replaces-coordinate path is pinned in
      // active_stroke_overlay_parity_test), and one dropped here is one
      // nothing can draw.
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      ActiveStrokeOverlayModel overlay() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .map((painter) => painter.overlayModel)
          .whereType<ActiveStrokeOverlayModel>()
          .first;

      await _pressureStroke(
        tester,
        canvasPoints: const [Offset(1.5, 1.5), Offset(6.5, 4.5)],
        pressure: 1,
      );
      expect(
        overlay().hasStandIns,
        isTrue,
        reason:
            'the handoff did not miss, so there is nothing to lose — this '
            'test proves nothing without it',
      );

      // One frame, then the next stroke begins: the whole window.
      await tester.pump();
      tester.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: 2,
          kind: PointerDeviceKind.stylus,
          position: canvasGlobalOffset(tester, const Offset(12.5, 12.5)),
          pressure: 1,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
      await tester.pump();

      expect(
        overlay().hasStandIns,
        isTrue,
        reason:
            'starting a stroke took away the cover for the previous one, so '
            'those coordinates fall back to their pre-stroke pixels',
      );
    });

    testWidgets('pointer down does not throw', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1.5, 1.5)),
        pointer: 1,
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('pointer move does not throw', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1.5, 1.5)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(3.5, 1.5)));
      await gesture.up();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(results, hasLength(1));
    });

    testWidgets('tap stroke commits source dabs', (tester) async {
      final sessionState = _sessionState();
      final results = <List<BrushDab>>[];

      await tester.pumpWidget(_app(_view(sessionState, results.add)));
      await tapCanvas(tester, const Offset(1.5, 1.5));

      expect(results, hasLength(1));
      expect(results.single, hasLength(1));
      expect(identical(sessionState, sessionState), isTrue);
    });

    testWidgets('drag commit creates exactly one operation result', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      await dragCanvas(tester, const [
        Offset(1.5, 1.5),
        Offset(2.5, 1.5),
        Offset(3.5, 2.5),
      ]);

      expect(results, hasLength(1));
      final sequences = results.single.map((dab) => dab.sequence).toList();
      expect(results.single, isNotEmpty);
      expect(sequences, everyElement(greaterThanOrEqualTo(0)));
      expect(_isStrictlyIncreasing(sequences), isTrue);
    });

    testWidgets(
      'a REAL pointer stroke runs the pre-blend pipeline on the surface '
      'grid (the R27 #4 ordering regression: reset() after setup nulled '
      'preBlendBase, silently reverting every live stroke to the classic '
      'GPU path)',
      (tester) async {
        final sessionState = _sessionState();
        await tester.pumpWidget(_app(_view(sessionState, (_) {})));

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(1.5, 1.5)),
          pointer: 1,
        );
        await tester.pump();

        final overlay = tester
            .widget<BrushEditCanvasView>(find.byType(BrushEditCanvasView))
            .overlayModel!;
        expect(
          overlay.preBlended,
          isTrue,
          reason: 'mid-stroke the overlay must be in pre-blend mode',
        );
        expect(
          identical(
            overlay.preBlendBase,
            sessionState.canvasState.currentSurface,
          ),
          isTrue,
          reason: 'the pre-blend base is the cel surface at stroke start',
        );
        expect(
          overlay.tileSize,
          sessionState.canvasState.currentSurface.tileSize,
          reason:
              'the overlay grid aligns with the committed grid '
              '(coordinate replacement in the painter requires it)',
        );

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('fast drag commits sampled source dabs beyond raw endpoints', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(),
            results.add,
            inputSettings: BrushEditCanvasInputSettings(size: 8),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1, 1)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
      final sequences = results.single.map((dab) => dab.sequence).toList();
      expect(results.single.length, greaterThan(2));
      expect(sequences, everyElement(greaterThanOrEqualTo(0)));
      expect(_isStrictlyIncreasing(sequences), isTrue);
    });

    testWidgets('a mixing brush deposits the colour it lifted', (tester) async {
      // A black brush releasing half its paint over a white cel lands
      // halfway between the two. Driven through a real pointer stroke so
      // the whole placement chain is exercised, not just the mixer.
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _paintedSessionState(const [255, 255, 255, 255]),
            results.add,
            inputSettings: BrushEditCanvasInputSettings.fromShape(
              BrushShape(
                size: 4,
                color: 0xFF000000,
                mixesGroundColor: true,
                paintAmount: 0.5,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(3, 3)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(5, 3)));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single, isNotEmpty);
      for (final dab in results.single) {
        expect(dab.color, 0xFF808080);
      }
    });

    testWidgets('a brush that does not mix keeps its own colour', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _paintedSessionState(const [255, 255, 255, 255]),
            results.add,
            inputSettings: BrushEditCanvasInputSettings.fromShape(
              BrushShape(size: 4, color: 0xFF000000),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(3, 3)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(5, 3)));
      await gesture.up();
      await tester.pump();

      expect(results.single, isNotEmpty);
      for (final dab in results.single) {
        expect(dab.color, 0xFF000000);
      }
    });

    testWidgets('tiny movement does not create duplicate sampled source dabs', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(),
            results.add,
            inputSettings: BrushEditCanvasInputSettings(size: 8),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1, 1)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(1.5, 1)));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single, hasLength(1));
      expect(results.single.single.sequence, 0);
    });

    testWidgets('pointer down shows active overlay before movement', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1, 1)),
        pointer: 1,
      );
      await tester.pump();

      final canvasView = tester.widget<BrushEditCanvasView>(
        find.byType(BrushEditCanvasView),
      );
      expect(canvasView.overlayModel!.dabs, isNotEmpty);
      expect(results, isEmpty);

      await gesture.cancel();
    });

    testWidgets(
      'pen-up never leaves a promoted tile with no picture anywhere',
      (tester) async {
        // The user's long-standing report: finishing a stroke leaves a
        // RECTANGULAR patch of the line missing for a frame.
        //
        // Promotion hands each committed tile the image the overlay was
        // already showing, and where that works the handoff is invisible.
        // But it is revision-gated, and the revision is written inside the
        // decode CALLBACK, while `_flushPendingOverlayDabs()` and
        // `_commitStroke()` run in ONE synchronous handler — so a tile the
        // final flush touched cannot have recorded its new revision by the
        // time the handoff compares. Those tiles reach the committed
        // surface with no picture, and dropping the overlay in the same
        // turn left the painter's stale fallback to answer for them with
        // the PRE-STROKE tile. Tile-shaped, one frame, and worst on short
        // strokes because then the whole line lives in the tiles that
        // final flush touched.
        //
        // ⚠️ WHAT THIS DOES AND DOES NOT SAY. It says the overlay is
        // RETAINED — that the miss took the settle branch instead of
        // dropping the overlay. It does NOT say every promoted coordinate
        // is covered, and that stronger claim is FALSE on this branch.
        //
        // `takeTileImageAt` removes the images it hands over, so what the
        // overlay still holds is exactly the missed-with-an-older-image
        // set. A coordinate the final flush touched for the FIRST time was
        // never decoded by the overlay, so the overlay has nothing for it
        // either — and if the cel already had artwork there, the painter's
        // stale fallback still answers with the pre-stroke tile. Measured
        // on a wide in-canvas fixture: 62 promoted, 50 of them still
        // painting pre-stroke pixels.
        //
        // So this fix closes one class of the hole and not the other. The
        // remaining class needs the painter to stop borrowing for the
        // settling coordinates, which is a change to a painter three
        // surfaces share and is not a rider on this one.
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 4),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(1, 1)),
          pointer: 1,
        );
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(5, 1)));
        await tester.pump();
        // Let the overlay's decode LAND. Without this the tile has no
        // image at any revision, the overlay has nothing to show either,
        // and the test would be measuring a harness that never yields
        // rather than the handoff. In the app this always happens — the
        // user has been looking at those pixels.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final overlay = tester
            .widget<BrushEditCanvasView>(find.byType(BrushEditCanvasView))
            .overlayModel!;
        expect(
          overlay.tileImages,
          isNotEmpty,
          reason: 'the mid-stroke decode never landed — bad premise',
        );

        // One more segment, so the flush at pen-up bumps the revision
        // past the one the landed image recorded. That is the miss, and it
        // is guaranteed rather than racy: the new revision is written
        // inside a decode callback that cannot run before the handoff
        // compares against it, in this same synchronous handler.
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(9, 1)));
        await gesture.up();

        final canvasView = tester.widget<BrushEditCanvasView>(
          find.byType(BrushEditCanvasView),
        );
        expect(results, hasLength(1), reason: 'the stroke did not commit');
        expect(
          canvasView.overlayModel!.tileImages,
          isNotEmpty,
          reason:
              'the overlay was dropped while a promoted tile had no '
              'picture — that coordinate now paints its PRE-STROKE tile, '
              'which is the hole the user reported',
        );
      },
    );

    testWidgets(
      'a handoff that fully succeeds retires the overlay in the SAME turn',
      (tester) async {
        // The other half, and the one that says this is not simply a
        // revert of the promotion round: when every promoted tile DOES get
        // its image, the overlay must go inside the pointer event, with no
        // settle window and no periodic timer.
        //
        // Nothing pinned that. `missedHandoff = true` unconditionally —
        // which makes every stroke settle and `_resetOverlay()` dead code
        // on this path — passed all 51 tests in this file, because the
        // default harness surface has no tiles, so every settle releases
        // vacuously on the next frame and no assertion is made between
        // `up()` and the next `pump()`.
        //
        // The difference from the miss test above is one line: no final
        // segment, so nothing is pending at pen-up, the flush bumps no
        // revision, and every promoted tile matches the image the overlay
        // already holds.
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 4),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(1, 1)),
          pointer: 1,
        );
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(5, 1)));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(
          tester
              .widget<BrushEditCanvasView>(find.byType(BrushEditCanvasView))
              .overlayModel!
              .tileImages,
          isNotEmpty,
          reason: 'the mid-stroke decode never landed — bad premise',
        );

        await gesture.up();

        // No pump: the question is whether the overlay went in the pointer
        // event itself.
        //
        // On `dabs`, not `tileImages`. A successful handoff TAKES the
        // images, so `tileImages` is empty either way and cannot tell the
        // two branches apart — I wrote that assertion first and the
        // `missedHandoff = true` mutant sailed through it. `dabs` is
        // cleared only by `reset()`, so it says which branch ran.
        expect(
          tester
              .widget<BrushEditCanvasView>(find.byType(BrushEditCanvasView))
              .overlayModel!
              .dabs,
          isEmpty,
          reason:
              'a fully successful handoff entered the settle window — every '
              'stroke now pays the periodic timer and the decode re-requests '
              'that promotion exists to avoid',
        );
        expect(results, hasLength(1));
      },
    );

    testWidgets(
      'drag stroke keeps continuous active path before commit and clears after commit',
      (tester) async {
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 4),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(1, 1)),
          pointer: 1,
        );
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(5, 1)));
        await tester.pump();

        var canvasView = tester.widget<BrushEditCanvasView>(
          find.byType(BrushEditCanvasView),
        );
        expect(canvasView.overlayModel!.dabs, isNotEmpty);
        expect(results, isEmpty);

        await gesture.up();
        // The COMMIT is atomic — it happens inside the pointer event, and
        // the promotion round's point stands: no deferred flush, no
        // re-derived pixels.
        canvasView = tester.widget<BrushEditCanvasView>(
          find.byType(BrushEditCanvasView),
        );
        expect(results, hasLength(1));

        // The OVERLAY is not always. This test used to assert it cleared
        // in the same turn, on the promotion round's claim that every
        // promoted tile gets handed the image it was already showing. That
        // claim is false for the tiles the final flush touched: the
        // handoff is revision-gated and the revision is written inside the
        // decode callback, so a tile flushed in this same synchronous
        // handler cannot have recorded it yet. Dropping the overlay for
        // those left the stroke missing in a tile-shaped patch, so a
        // missed handoff now keeps it up until the committed tiles decode.
        //
        // What the test can still say without asserting which case it got:
        // the overlay ALWAYS ends up clear.
        for (
          var i = 0;
          i < 40 && canvasView.overlayModel!.dabs.isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          canvasView = tester.widget<BrushEditCanvasView>(
            find.byType(BrushEditCanvasView),
          );
        }
        expect(
          canvasView.overlayModel!.dabs,
          isEmpty,
          reason: 'the overlay never released after the commit',
        );
        expect(canvasView.overlayModel!.tileImages, isEmpty);
        expect(canvasView.overlayModel!.settleHoldTiles, isNull);
        expect(canvasView.overlayModel!.preBlended, isFalse);

        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'fast drag keeps active display bounded while committing full source stroke',
      (tester) async {
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 1),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(1, 1)),
          pointer: 1,
        );
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));
        await tester.pump();

        var canvasView = tester.widget<BrushEditCanvasView>(
          find.byType(BrushEditCanvasView),
        );
        expect(canvasView.overlayModel!.dabs, isNotEmpty);
        expect(canvasView.overlayModel!.dabs.length, greaterThan(2));
        expect(canvasView.overlayModel!.dabs.last.center.x, 7);
        expect(results, isEmpty);

        await gesture.up();
        // R25-④: the deferred commit lands one frame after pen-up,
        // settling releases on the following frame; then let the
        // settling window elapse before checking the cleared state.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        canvasView = tester.widget<BrushEditCanvasView>(
          find.byType(BrushEditCanvasView),
        );
        expect(canvasView.overlayModel!.dabs, isEmpty);
        expect(results, hasLength(1));
        expect(results.single.length, greaterThan(2));
      },
    );

    testWidgets('repeated tap strokes produce repeated operation results', (
      tester,
    ) async {
      var sessionState = _sessionState();
      final results = <List<BrushDab>>[];

      await tester.pumpWidget(
        _app(
          _view(sessionState, (result) {
            results.add(result);
          }),
        ),
      );
      await tapCanvas(tester, const Offset(1.5, 1.5));
      await tester.pumpWidget(
        _app(
          _view(sessionState, (result) {
            results.add(result);
          }),
        ),
      );
      await tapCanvas(tester, const Offset(2.5, 1.5));

      expect(results, hasLength(2));
      expect(results.map((result) => result.length), [1, 1]);
    });

    testWidgets('coordinates are interpreted relative to the canvas view', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 48, left: 24),
              child: _view(_sessionState(), results.add),
            ),
          ),
        ),
      );

      await tapCanvas(tester, const Offset(1.5, 1.5));

      expect(results, hasLength(1));
      expect(results.single, hasLength(1));
    });

    testWidgets(
      'viewport transform keeps committed dabs in canvas coordinates',
      (tester) async {
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              viewport: CanvasViewport(zoom: 2),
            ),
          ),
        );

        await tapCanvas(tester, const Offset(3, 3));

        expect(results, hasLength(1));
        expect(results.single.single.center.x, 1.5);
        expect(results.single.single.center.y, 1.5);
      },
    );

    testWidgets(
      'viewport pan and zoom keep committed dabs in canvas coordinates',
      (tester) async {
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(),
              results.add,
              viewport: CanvasViewport(zoom: 2, panX: 4, panY: 6),
            ),
          ),
        );

        await tapCanvas(tester, const Offset(7, 9));

        expect(results, hasLength(1));
        expect(results.single.single.center.x, 1.5);
        expect(results.single.single.center.y, 1.5);
      },
    );

    testWidgets('second touch finger cancels the stroke without committing', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(canvasGlobalOffset(tester, const Offset(1, 1)));
      await firstFinger.moveTo(canvasGlobalOffset(tester, const Offset(3, 3)));

      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await secondFinger.down(canvasGlobalOffset(tester, const Offset(6, 6)));

      // Finger 1 keeps moving as part of the pinch — it must not draw.
      await firstFinger.moveTo(canvasGlobalOffset(tester, const Offset(5, 5)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      expect(results, isEmpty);

      // With every finger lifted, a single-finger stroke works again.
      final thirdFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await thirdFinger.down(canvasGlobalOffset(tester, const Offset(2, 2)));
      await thirdFinger.up();
      await tester.pump();

      expect(results, hasLength(1));
    });

    testWidgets('a COMMITTED touch stroke SURVIVES a late second finger '
        '(PEN-12 #4: the mid-line vanish fix)', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(_view(_sessionState(width: 200, height: 16), results.add)),
      );

      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(canvasGlobalOffset(tester, const Offset(2, 4)));
      // Past the 18px commit slop: the stroke owns the screen now.
      await firstFinger.moveTo(canvasGlobalOffset(tester, const Offset(40, 4)));
      await tester.pump();

      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await secondFinger.down(canvasGlobalOffset(tester, const Offset(90, 10)));
      await tester.pump();

      // The stroke keeps drawing through the extra contact.
      await firstFinger.moveTo(canvasGlobalOffset(tester, const Offset(70, 4)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      expect(
        results,
        hasLength(1),
        reason: 'the committed stroke commits whole — never vanishes',
      );
      expect(results.single, isNotEmpty);
    });

    testWidgets('single-finger touch stroke still commits', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
      await finger.down(canvasGlobalOffset(tester, const Offset(1, 1)));
      await finger.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
      await finger.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single, isNotEmpty);
    });

    testWidgets('middle mouse drag never commits dabs', (tester) async {
      // Viewport panning itself moved to the panel's
      // CanvasViewportGestureLayer; the view must simply not draw from a
      // middle-button drag.
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.down(canvasGlobalOffset(tester, const Offset(1, 1)));
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(4, 6)));
      await gesture.up();
      await tester.pump();

      expect(results, isEmpty);
    });

    testWidgets('an off-canvas tap on the PASTEBOARD commits — the stage '
        'rectangle is not an input boundary (user feedback)', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      // (9,9) is outside the 8×8 stage but inside its pasteboard
      // (x,y ∈ [-8,16)).
      await tapCanvas(tester, const Offset(9, 9));

      expect(results, hasLength(1));
      expect(results.single, isNotEmpty);
      expect(results.single.first.center.x, 9);
      expect(results.single.first.center.y, 9);
    });

    testWidgets('clips the drawing canvas display to the viewport', (
      tester,
    ) async {
      // The Cut-canvas-rect clipping now happens inside the composite
      // painter (canvas.clipRect in canvas space); the widget tree clips
      // the whole editor display to the viewport bounds.
      await tester.pumpWidget(_app(_view(_sessionState(), (_) {})));

      final clipFinder = find.byKey(
        const ValueKey<String>('interactive-brush-edit-canvas-clip'),
      );

      expect(clipFinder, findsOneWidget);
      expect(
        find.descendant(
          of: clipFinder,
          matching: find.byType(BrushEditCanvasView),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pointer down outside then entering draws the WHOLE path '
        '(the pasteboard is drawable from the first dab)', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 32,
            height: 32,
            child: _view(_sessionState(), results.add),
          ),
        ),
      );

      final origin = tester.getTopLeft(
        find.byType(InteractiveBrushEditCanvasView),
      );
      final gesture = await tester.startGesture(
        origin + const Offset(12, 1),
        pointer: 1,
      );
      await tester.pump();
      await gesture.moveTo(origin + const Offset(2, 1));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));

      final dabs = results.single;
      expect(
        dabs.map((dab) => dab.center.x).toList(),
        [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2],
        reason: 'the off-canvas leg (12..9) draws too now',
      );
      expect(dabs.map((dab) => dab.center.y).toSet(), {1});
    });

    testWidgets('a stroke entirely OFF-canvas commits on the pasteboard; '
        'beyond the pasteboard wall commits nothing', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 32,
            height: 32,
            child: _view(_sessionState(), results.add),
          ),
        ),
      );

      final origin = tester.getTopLeft(
        find.byType(InteractiveBrushEditCanvasView),
      );
      final gesture = await tester.startGesture(
        origin + const Offset(12, 1),
        pointer: 1,
      );
      await gesture.moveTo(origin + const Offset(14, 1));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single.map((dab) => dab.center.x).toList(), [12, 13, 14]);

      // Beyond the wall (x ≥ 24 for the 8×8 stage, 5x5 pasteboard):
      // nothing.
      results.clear();
      final beyond = await tester.startGesture(
        origin + const Offset(25, 1),
        pointer: 2,
      );
      await beyond.moveTo(origin + const Offset(27, 1));
      await beyond.up();
      await tester.pump();

      expect(results, isEmpty);
    });

    testWidgets('leaving the stage and returning draws THROUGH the gap — '
        'the stage edge no longer breaks strokes', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 32,
            height: 32,
            child: _view(_sessionState(), results.add),
          ),
        ),
      );

      final origin = tester.getTopLeft(
        find.byType(InteractiveBrushEditCanvasView),
      );
      final gesture = await tester.startGesture(
        origin + const Offset(1, 1),
        pointer: 1,
      );
      await gesture.moveTo(origin + const Offset(3, 1));
      await gesture.moveTo(origin + const Offset(12, 1));
      await tester.pump();

      await gesture.moveTo(origin + const Offset(6, 1));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));

      final xs = results.single.map((dab) => dab.center.x).toList();

      expect(
        xs,
        containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
        reason: 'the off-canvas leg is real drawing on the pasteboard',
      );
      expect(xs.last, 6);
    });

    testWidgets('active stroke snapshots input settings until pointer up', (
      tester,
    ) async {
      final sessionState = _sessionState(width: 200, height: 32);
      final results = <List<BrushDab>>[];
      final initialSettings = BrushEditCanvasInputSettings(
        color: 0xFFE53935,
        size: 20,
        spacing: 0.25,
      );
      final rebuiltSettings = BrushEditCanvasInputSettings(
        color: 0xFF1E88E5,
        size: 20,
        spacing: 4.0,
      );

      await tester.pumpWidget(
        _app(_view(sessionState, results.add, inputSettings: initialSettings)),
      );

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1, 1)),
        pointer: 1,
      );
      await tester.pump();

      await tester.pumpWidget(
        _app(_view(sessionState, results.add, inputSettings: rebuiltSettings)),
      );
      await tester.pump();

      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(101, 1)));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single, hasLength(greaterThan(10)));
      expect(results.single.map((dab) => dab.color).toSet(), {0xFFE53935});
      expect(results.single.map((dab) => dab.size).toSet(), {20});
    });

    testWidgets('pen pressure scales committed dab size when enabled', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(width: 200, height: 16),
            results.add,
            inputSettings: BrushEditCanvasInputSettings(
              size: 8,
              sizePressureCurve: BrushPressureCurve.identity(),
            ),
          ),
        ),
      );

      await _pressureStroke(
        tester,
        canvasPoints: const [Offset(2, 1), Offset(40, 1)],
        pressure: 0.5,
      );

      expect(results, hasLength(1));
      // Constant 0.5 pressure with the size curve on halves every dab's size.
      for (final dab in results.single) {
        expect(dab.size, closeTo(4.0, 1e-6));
      }
    });

    testWidgets(
      'mouse strokes paint at full pressure even with the size curve on',
      (tester) async {
        // Regression: a mouse claims a 0..1 pressure range on some platforms
        // while always reporting pressure 0.0, which scaled every dab to
        // size zero — enabling pen pressure made the mouse stop drawing.
        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(
                size: 8,
                sizePressureCurve: BrushPressureCurve.identity(),
                opacityPressureCurve: BrushPressureCurve.identity(),
              ),
            ),
          ),
        );

        await _pressureStroke(
          tester,
          canvasPoints: const [Offset(2, 1), Offset(40, 1)],
          pressure: 0.0,
          kind: PointerDeviceKind.mouse,
        );

        expect(results, hasLength(1));
        expect(results.single.map((dab) => dab.size).toSet(), {8.0});
        expect(results.single.map((dab) => dab.opacity).toSet(), {1.0});
      },
    );

    testWidgets(
      'a LIVE Wintab stream overrides pressure for every kind (PEN-2: the '
      'misreported-pen escape hatch)',
      (tester) async {
        final service = WintabPenService.instance;
        addTearDown(service.debugReset);
        // Freeze the freshness clock: the injected packet must read as
        // "fresh" however long the busy test binding takes between the
        // inject and the stroke's pressure polls (the real 150ms window
        // lapsing mid-stroke was the flake — some dabs kept the driver's
        // 0.5, others reverted to the pointer's 1.0, interpolating a
        // stray 0.53 → dab size 4.25).
        WintabPenService.debugClockOverride = () => DateTime(2024);
        service.debugPollOverride = () => const [];
        service.start();

        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(
                size: 8,
                sizePressureCurve: BrushPressureCurve.identity(),
              ),
            ),
          ),
        );

        // The driver reports half pressure; the pointer stream arrives as
        // TOUCH with none (the classic misreport) — the driver wins.
        service.debugInjectPacket(
          const QaTabletPacket(
            pressure: 0.5,
            tiltAzimuthDegrees: 0,
            altitude: 1,
            timeMs: 1,
            buttons: 1,
          ),
        );
        await _pressureStroke(
          tester,
          canvasPoints: const [Offset(2, 1), Offset(40, 1)],
          pressure: 1.0,
          kind: PointerDeviceKind.touch,
        );

        expect(results, hasLength(1));
        for (final dab in results.single) {
          expect(dab.size, closeTo(4.0, 1e-6));
        }

        // The poll timer must die BEFORE the binding's pending-timer
        // invariant check (which runs ahead of tearDown callbacks).
        service.debugReset();
      },
    );

    testWidgets(
      'the pressure response curve shapes stylus pressure (PEN-3: gamma 2 '
      'squares the input)',
      (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchTimelineScroll: false,
          pressureCurveGamma: 2.0,
        );
        addTearDown(() {
          AppInput.settings.value = AppInputSettings.testCorpusBaseline;
        });

        final results = <List<BrushDab>>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(
                size: 8,
                sizePressureCurve: BrushPressureCurve.identity(),
              ),
            ),
          ),
        );

        await _pressureStroke(
          tester,
          canvasPoints: const [Offset(2, 1), Offset(40, 1)],
          pressure: 0.5,
        );

        expect(results, hasLength(1));
        // 0.5^2 = 0.25 → size 8 becomes 2.
        for (final dab in results.single) {
          expect(dab.size, closeTo(2.0, 1e-6));
        }
      },
    );

    // PEN-7a: the CANVAS mapping owns what secondary buttons do — the pen
    // barrel / S-Pen button / mouse right button all route as
    // 'right-click', defaulting to a held EYEDROPPER (live picks, tool
    // springs back on release).
    group('canvas pointer mappings (PEN-7a)', () {
      tearDown(() {
        AppInput.settings.value = AppInputSettings.testCorpusBaseline;
      });

      Future<void> barrelStroke(WidgetTester tester) async {
        tester.binding.handlePointerEvent(
          PointerDownEvent(
            pointer: 7,
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, const Offset(2, 1)),
            buttons: kPrimaryButton | kPrimaryStylusButton,
            pressure: 1,
            pressureMin: 0,
            pressureMax: 1,
          ),
        );
        await tester.pump();
        tester.binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: 7,
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, const Offset(40, 1)),
            buttons: kPrimaryButton | kPrimaryStylusButton,
            pressure: 1,
            pressureMin: 0,
            pressureMax: 1,
          ),
        );
        await tester.pump();
        tester.binding.handlePointerEvent(
          PointerUpEvent(
            pointer: 7,
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, const Offset(40, 1)),
          ),
        );
        await tester.pump();
      }

      testWidgets('the default right-click mapping is a HELD eyedropper: '
          'live picks, no stroke, tool springs back', (tester) async {
        final results = <List<BrushDab>>[];
        final picks = <CanvasPoint>[];
        final holds = <CanvasTool>[];
        final releases = <bool>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 8),
              onAltPick: picks.add,
              onTemporaryToolHold: holds.add,
              onTemporaryToolRelease: ({required keep}) => releases.add(keep),
            ),
          ),
        );

        await barrelStroke(tester);

        expect(results, isEmpty, reason: 'a mapped hold never strokes');
        expect(picks, isNotEmpty, reason: 'picks at down AND along the drag');
        expect(picks.length, greaterThanOrEqualTo(2));
        expect(holds, [CanvasTool.eyedropper]);
        expect(releases, [false], reason: 'returnToTool = spring back');
      });

      testWidgets(
        'a barrel press Ink disguises as a phantom pen tap still reaches '
        'its mapping — and never strokes',
        (tester) async {
          final service = WintabPenService.instance;
          addTearDown(service.debugReset);
          WintabPenService.debugClockOverride = () => DateTime(2024);
          service.debugPollOverride = () => const [];
          service.start();

          final results = <List<BrushDab>>[];
          final picks = <CanvasPoint>[];
          final holds = <CanvasTool>[];
          await tester.pumpWidget(
            _app(
              _view(
                _sessionState(width: 200, height: 16),
                results.add,
                inputSettings: BrushEditCanvasInputSettings(size: 8),
                onAltPick: picks.add,
                onTemporaryToolHold: holds.add,
              ),
            ),
          );

          // The DRIVER's truth: the lower barrel switch is down (Wintab
          // bit 1) and the tip is not touching anything.
          service.debugInjectPacket(
            const QaTabletPacket(
              pressure: 0,
              tiltAzimuthDegrees: 0,
              altitude: 1,
              timeMs: 1,
              buttons: 0x02,
            ),
          );

          // What Windows Ink actually hands a legacy window for that same
          // press: a phantom pen TAP carrying the PRIMARY button, with
          // pressure 0, while the pen is still hovering.
          tester.binding.handlePointerEvent(
            PointerDownEvent(
              pointer: 21,
              kind: PointerDeviceKind.stylus,
              buttons: kPrimaryButton,
              pressure: 0,
              position: canvasGlobalOffset(tester, const Offset(2, 1)),
            ),
          );
          await tester.pump();

          expect(results, isEmpty, reason: 'the phantom must not draw');
          expect(holds, [CanvasTool.eyedropper], reason: 'the mapping fires');
          expect(picks, isNotEmpty);

          // The poll timer must die before the binding's pending-timer
          // invariant check.
          service.debugReset();
        },
      );

      testWidgets('a mouse RIGHT drag routes the same mapping', (tester) async {
        final results = <List<BrushDab>>[];
        final picks = <CanvasPoint>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              onAltPick: picks.add,
            ),
          ),
        );

        final gesture = await tester.startGesture(
          canvasGlobalOffset(tester, const Offset(2, 1)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.moveTo(canvasGlobalOffset(tester, const Offset(30, 1)));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(results, isEmpty);
        expect(picks, isNotEmpty);
      });

      testWidgets('mapped ERASER erases the whole stroke and "keep" holds '
          'the switched tool', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchTimelineScroll: false,
          // The follow-up stroke below drags with TOUCH — keep the
          // corpus draw contract for it.
          touchDragOneFinger: CanvasTouchDragAction.draw,
          canvasRightClick: CanvasPointerMapping(
            action: CanvasPointerAction.eraser,
            release: CanvasPointerRelease.keep,
          ),
        );
        final results = <List<BrushDab>>[];
        final holds = <CanvasTool>[];
        final releases = <bool>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              inputSettings: BrushEditCanvasInputSettings(size: 8),
              onTemporaryToolHold: holds.add,
              onTemporaryToolRelease: ({required keep}) => releases.add(keep),
            ),
          ),
        );

        await barrelStroke(tester);

        expect(results, hasLength(1));
        expect(
          results.single.map((dab) => dab.erase).toSet(),
          {true},
          reason: 'the whole mapped stroke erases',
        );
        expect(holds, [CanvasTool.eraser]);
        expect(releases, [true], reason: 'keep = stay on the eraser');

        // A plain follow-up stroke paints again (the substitution lives
        // on the per-stroke snapshot only).
        await dragCanvas(tester, const [Offset(2, 8), Offset(30, 8)]);
        expect(results, hasLength(2));
        expect(results.last.map((dab) => dab.erase).toSet(), {false});
      });

      testWidgets(
        'the pen TAIL engages on the flip, erases the stroke, and springs '
        'back when the pen is turned upright',
        (tester) async {
          final raw = RawPenInputService.instance;
          addTearDown(raw.debugReset);
          RawPenInputService.debugClockOverride = () => DateTime(2024);
          raw.debugPollOverride = () => null; // reports are injected below
          raw.start();

          final results = <List<BrushDab>>[];
          final holds = <CanvasTool>[];
          final releases = <bool>[];
          await tester.pumpWidget(
            _app(
              _view(
                _sessionState(width: 200, height: 16),
                results.add,
                inputSettings: BrushEditCanvasInputSettings(size: 8),
                onTemporaryToolHold: holds.add,
                onTemporaryToolRelease: ({required keep}) => releases.add(keep),
              ),
            ),
          );

          Future<void> hover(Offset at) async {
            tester.binding.handlePointerEvent(
              PointerHoverEvent(
                kind: PointerDeviceKind.stylus,
                position: canvasGlobalOffset(tester, at),
              ),
            );
            await tester.pump();
          }

          // HID Invert with nothing touching: the pen has been turned
          // over in the air. That is the moment the eraser arrives —
          // before anything reaches the surface — which is the whole
          // reason the mapping is flip-scoped rather than contact-scoped.
          raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 1));
          await hover(const Offset(2, 1));
          expect(holds, [CanvasTool.eraser]);
          expect(results, isEmpty, reason: 'hovering never draws');

          // The tail's stroke erases without waiting for the async tool
          // switch to come back around.
          raw.debugInjectState(
            const QaPenRawState(flags: 0x04 | 0x08, sequence: 2),
          );
          await _pressureStroke(
            tester,
            canvasPoints: const [Offset(2, 1), Offset(40, 1)],
            pressure: 1.0,
            kind: PointerDeviceKind.stylus,
          );
          expect(results, hasLength(1));
          expect(
            results.single.map((dab) => dab.erase).toSet(),
            {true},
            reason: 'the whole tail stroke erases',
          );

          // Turned upright again: spring back to the original tool.
          raw.debugInjectState(const QaPenRawState(flags: 0, sequence: 3));
          await hover(const Offset(60, 1));
          expect(releases, [false], reason: 'returnToTool = spring back');

          raw.debugReset();
        },
      );

      testWidgets('mapped NONE swallows the press entirely', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchTimelineScroll: false,
          canvasRightClick: CanvasPointerMapping(
            action: CanvasPointerAction.none,
          ),
        );
        final results = <List<BrushDab>>[];
        final picks = <CanvasPoint>[];
        final holds = <CanvasTool>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              onAltPick: picks.add,
              onTemporaryToolHold: holds.add,
            ),
          ),
        );

        await barrelStroke(tester);

        expect(results, isEmpty);
        expect(picks, isEmpty);
        expect(holds, isEmpty);
      });

      testWidgets('mapped UNDO fires once at the press — no stroke, no '
          'hold (PEN-11)', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchTimelineScroll: false,
          canvasRightClick: CanvasPointerMapping(
            action: CanvasPointerAction.undo,
          ),
        );
        final results = <List<BrushDab>>[];
        final holds = <CanvasTool>[];
        final invoked = <String>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              onTemporaryToolHold: holds.add,
              onInvokeAction: invoked.add,
            ),
          ),
        );

        await barrelStroke(tester);

        expect(invoked, ['edit-undo']);
        expect(results, isEmpty, reason: 'a one-shot action never strokes');
        expect(holds, isEmpty);
      });

      testWidgets('a HOVER barrel press fires UNDO without contact, and a '
          'buttoned contact right after does not double-fire (PEN-11)', (
        tester,
      ) async {
        AppInput.settings.value = const AppInputSettings(
          touchTimelineScroll: false,
          canvasRightClick: CanvasPointerMapping(
            action: CanvasPointerAction.undo,
          ),
        );
        final results = <List<BrushDab>>[];
        final invoked = <String>[];
        await tester.pumpWidget(
          _app(
            _view(
              _sessionState(width: 200, height: 16),
              results.add,
              onInvokeAction: invoked.add,
            ),
          ),
        );

        final at = canvasGlobalOffset(tester, const Offset(10, 4));
        void hover(int buttons) {
          tester.binding.handlePointerEvent(
            PointerHoverEvent(
              kind: PointerDeviceKind.stylus,
              position: at,
              buttons: buttons,
            ),
          );
        }

        // Approach → button press mid-hover: fires without any contact
        // (the S-Pen hover window blocks touch, not the pen itself).
        hover(0);
        await tester.pump();
        hover(kPrimaryStylusButton);
        await tester.pump();
        expect(invoked, ['edit-undo']);

        // The tip then touches with the button STILL held: no double.
        await barrelStroke(tester);
        expect(invoked, ['edit-undo']);
        expect(results, isEmpty);

        // Released and pressed again on a later hover: fires again.
        hover(0);
        await tester.pump();
        hover(kPrimaryStylusButton);
        await tester.pump();
        expect(invoked, ['edit-undo', 'edit-undo']);
      });
    });

    testWidgets('pen pressure is ignored when no size curve is set', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(width: 200, height: 16),
            results.add,
            // No size curve: pressure must not change the size.
            inputSettings: BrushEditCanvasInputSettings(size: 8),
          ),
        ),
      );

      await _pressureStroke(
        tester,
        canvasPoints: const [Offset(2, 1), Offset(40, 1)],
        pressure: 0.5,
      );

      expect(results, hasLength(1));
      expect(results.single.map((dab) => dab.size).toSet(), {8.0});
    });

    testWidgets('pen pressure ramps dab size across a stroke', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(width: 200, height: 16),
            results.add,
            inputSettings: BrushEditCanvasInputSettings(
              size: 8,
              sizePressureCurve: BrushPressureCurve.identity(),
            ),
          ),
        ),
      );

      // Pen-down at full pressure, drag to a light-pressure sample: size
      // should decrease monotonically along the interpolated stroke.
      await _pressureStroke(
        tester,
        canvasPoints: const [Offset(2, 1), Offset(120, 1)],
        pressure: 0.25,
        downPressure: 1.0,
      );

      expect(results, hasLength(1));
      final sizes = results.single.map((dab) => dab.size).toList();
      expect(sizes.length, greaterThan(3));
      expect(sizes.first, greaterThan(sizes.last));
      expect(sizes.first, closeTo(8.0, 1e-6));
      // Every dab stays within the base size envelope.
      expect(sizes, everyElement(lessThanOrEqualTo(8.0 + 1e-6)));
      expect(sizes, everyElement(greaterThanOrEqualTo(0.0)));
    });

    testWidgets('pointer cancel does not emit a result', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1.5, 1.5)),
        pointer: 1,
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(results, isEmpty);
    });

    testWidgets('pointer move without pointer down does not emit a result', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      tester.binding.handlePointerEvent(
        const PointerMoveEvent(position: Offset(1.5, 1.5)),
      );
      tester.binding.handlePointerEvent(
        const PointerUpEvent(position: Offset(1.5, 1.5)),
      );
      await tester.pump();

      expect(results, isEmpty);
    });

    testWidgets('eraser input settings stamp erase dabs', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(
        _app(
          _view(
            _sessionState(),
            results.add,
            inputSettings: BrushEditCanvasInputSettings(erase: true),
          ),
        ),
      );

      await tapCanvas(tester, const Offset(3, 3));

      expect(results, hasLength(1));
      expect(results.single.every((dab) => dab.erase), isTrue);
    });

    testWidgets('stray touches never cancel a stylus stroke (palm rest)', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await stylus.down(canvasGlobalOffset(tester, const Offset(1.5, 1.5)));

      // Two palm contacts land while the stylus draws — only a TOUCH
      // stroke turns into a pinch; the stylus stroke must survive.
      final palmA = await tester.createGesture(kind: PointerDeviceKind.touch);
      final palmB = await tester.createGesture(kind: PointerDeviceKind.touch);
      await palmA.down(canvasGlobalOffset(tester, const Offset(6, 6)));
      await palmB.down(canvasGlobalOffset(tester, const Offset(7, 7)));

      await stylus.moveTo(canvasGlobalOffset(tester, const Offset(3, 3)));
      await stylus.up();
      await palmA.up();
      await palmB.up();
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single, isNotEmpty);
    });

    testWidgets('callback is called at most once per stroke', (tester) async {
      final results = <List<BrushDab>>[];
      await tester.pumpWidget(_app(_view(_sessionState(), results.add)));

      final gesture = await tester.startGesture(
        canvasGlobalOffset(tester, const Offset(1.5, 1.5)),
        pointer: 1,
      );
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(2.5, 1.5)));
      await gesture.moveTo(canvasGlobalOffset(tester, const Offset(20, 20)));
      await gesture.up();
      await tester.pump();

      expect(results, hasLength(1));
    });

    testWidgets('does not mutate input states', (tester) async {
      final sessionState = _sessionState();
      final originalCanvasState = sessionState.canvasState;
      final originalHistoryState = sessionState.materializationHistoryState;
      final originalSessionSnapshot = sessionState.toString();
      final originalCanvasSnapshot = originalCanvasState.toString();
      final originalHistorySnapshot = originalHistoryState.toString();
      final results = <List<BrushDab>>[];

      await tester.pumpWidget(_app(_view(sessionState, results.add)));
      await tapCanvas(tester, const Offset(1.5, 1.5));

      expect(identical(sessionState.canvasState, originalCanvasState), isTrue);
      expect(
        identical(
          sessionState.materializationHistoryState,
          originalHistoryState,
        ),
        isTrue,
      );
      expect(sessionState.toString(), originalSessionSnapshot);
      expect(originalCanvasState.toString(), originalCanvasSnapshot);
      expect(originalHistoryState.toString(), originalHistorySnapshot);
    });

    test(
      'does not execute undo or redo and does not add forbidden state management',
      () {
        final source = _readInteractiveSource();

        expect(source, isNot(contains('undoLatestBrushBitmapMaterialization')));
        expect(source, isNot(contains('redoLatestBrushBitmapMaterialization')));
        expect(source, isNot(contains('Provider')));
        expect(source, isNot(contains('Riverpod')));
        expect(source, isNot(contains('Bloc')));
        expect(source, isNot(contains('ChangeNotifier')));
      },
    );

    testWidgets('does not affect StoryboardPanel or TimelinePanel', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_view(_sessionState(), (_) {})));

      expect(find.byType(StoryboardPanel), findsNothing);
      expect(find.byType(TimelinePanel), findsNothing);
    });
  });
}

void _settlingTileGroup() {
  group('settlingTilesForBounds', () {
    BitmapTile tile(int x, int y) => BitmapTile.blank(
      coord: TileCoord(x: x, y: y),
      size: 2,
    );

    test('narrows the gate to the tiles the stroke touched', () {
      final surface = BitmapSurface(
        canvasSize: const CanvasSize(width: 8, height: 8),
        tileSize: 2,
        tiles: {
          TileCoord(x: 0, y: 0): tile(0, 0),
          TileCoord(x: 3, y: 3): tile(3, 3),
        },
      );

      final touched = settlingTilesForBounds(
        surface: surface,
        bounds: DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 3,
          bottomExclusive: 3,
        ),
      );
      expect(
        touched.map((tile) => tile.coord),
        [TileCoord(x: 0, y: 0)],
        reason: 'the far tile must not gate the overlay handoff',
      );

      final all = settlingTilesForBounds(surface: surface, bounds: null);
      expect(all, hasLength(2), reason: 'unknown bounds fall back to all');
    });
  });

  group('preStrokeHoldTiles', () {
    test('covers every touched coordinate, empty ones as explicit nulls', () {
      final existing = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
      final surface = BitmapSurface(
        canvasSize: const CanvasSize(width: 8, height: 8),
        tileSize: 2,
        tiles: {existing.coord: existing},
      );

      final hold = preStrokeHoldTiles(
        surface: surface,
        bounds: DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 4,
          bottomExclusive: 4,
        ),
      );

      expect(hold, hasLength(4));
      expect(hold[TileCoord(x: 0, y: 0)], same(existing));
      expect(hold.containsKey(TileCoord(x: 1, y: 0)), isTrue);
      expect(hold[TileCoord(x: 1, y: 0)], isNull);
      expect(hold[TileCoord(x: 0, y: 1)], isNull);
      expect(hold[TileCoord(x: 1, y: 1)], isNull);
    });

    test('unknown bounds pin every existing tile', () {
      final existing = BitmapTile.blank(coord: TileCoord(x: 1, y: 1), size: 2);
      final surface = BitmapSurface(
        canvasSize: const CanvasSize(width: 8, height: 8),
        tileSize: 2,
        tiles: {existing.coord: existing},
      );

      final hold = preStrokeHoldTiles(surface: surface, bounds: null);

      expect(hold, {existing.coord: same(existing)});
    });
  });
}

/// A session whose cel is already painted a solid straight-RGBA [rgba], so
/// a mixing brush has something to lift.
BrushEditSessionState _paintedSessionState(List<int> rgba) {
  const size = 8;
  const tileSize = 2;
  final tiles = <TileCoord, BitmapTile>{};
  for (var tileY = 0; tileY < size ~/ tileSize; tileY += 1) {
    for (var tileX = 0; tileX < size ~/ tileSize; tileX += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var index = 0; index < tileSize * tileSize; index += 1) {
        pixels.setRange(index * 4, index * 4 + 4, rgba);
      }
      final coord = TileCoord(x: tileX, y: tileY);
      tiles[coord] = BitmapTile(coord: coord, size: tileSize, pixels: pixels);
    }
  }
  return BrushEditSessionState(
    canvasState: CanvasSurfaceState(
      currentSurface: BitmapSurface(
        canvasSize: const CanvasSize(width: size, height: size),
        tileSize: tileSize,
        tiles: tiles,
      ),
    ),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );
}

BrushEditSessionState _sessionState({int width = 8, int height = 8}) {
  return BrushEditSessionState(
    canvasState: CanvasSurfaceState(
      currentSurface: BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: 2,
      ),
    ),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );
}

InteractiveBrushEditCanvasView _view(
  BrushEditSessionState sessionState,
  ValueChanged<List<BrushDab>> onResult, {
  BrushEditCanvasInputSettings inputSettings =
      BrushEditCanvasInputSettings.defaults,
  CanvasViewport? viewport,
  ValueChanged<CanvasPoint>? onAltPick,
  void Function(CanvasTool tool)? onTemporaryToolHold,
  void Function({required bool keep})? onTemporaryToolRelease,
  void Function(String actionId)? onInvokeAction,
}) {
  return InteractiveBrushEditCanvasView(
    sessionState: sessionState,
    layerId: const LayerId('layer-a'),
    frameId: const FrameId('frame-a'),
    inputSettings: inputSettings,
    viewport: viewport,
    onAltPick: onAltPick,
    onTemporaryToolHold: onTemporaryToolHold,
    onTemporaryToolRelease: onTemporaryToolRelease,
    onInvokeAction: onInvokeAction,
    // Tests observe the committed source dabs; the exact pre-rasterized
    // stroke pixels travel alongside them in the commit data.
    onSourceStrokeCommitted: (strokeData) => onResult(strokeData.sourceDabs),
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

/// Drives a stroke through raw pointer events carrying a specific pressure
/// (test gestures cannot set pressure). [downPressure] defaults to
/// [pressure] so a flat-pressure stroke needs only one value. Defaults to a
/// stylus: only stylus devices are trusted for pressure — a mouse claims a
/// 0..1 pressure range on some platforms while always reporting 0.0.
Future<void> _pressureStroke(
  WidgetTester tester, {
  required List<Offset> canvasPoints,
  required double pressure,
  double? downPressure,
  int pointer = 1,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) async {
  final globals = [
    for (final point in canvasPoints) canvasGlobalOffset(tester, point),
  ];
  tester.binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: globals.first,
      pressure: downPressure ?? pressure,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  await tester.pump();
  for (final global in globals.skip(1)) {
    tester.binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        kind: kind,
        position: global,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
  }
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: globals.last,
      pressure: 0,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  await tester.pump();
}

String _readInteractiveSource() {
  return File(
    'lib/src/ui/canvas/interactive_brush_edit_canvas_view.dart',
  ).readAsStringSync();
}

bool _isStrictlyIncreasing(Iterable<int> values) {
  int? previous;
  for (final value in values) {
    if (previous != null && value <= previous) {
      return false;
    }
    previous = value;
  }
  return true;
}
