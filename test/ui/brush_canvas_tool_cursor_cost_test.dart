import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// 유저, R4 #3: 커서가 살짝 늦게 따라오는 수준이 아니라 진짜 렉이 있다. 60fps로
/// 보여야 하는데 20fps로 보이는 느낌이고, 0.2초 늦게 온다.
///
/// It was not latency. `PaintingContext.paintChild` branches on
/// `child.isRepaintBoundary` AND NOTHING ELSE — a `CustomPainter`'s
/// `shouldRepaint` is consulted only when the painter INSTANCE is swapped,
/// never during the walk. The tool cursor was a `Positioned` sibling of the
/// artwork in one Stack, so moving it dirtied that Stack and every
/// unboundaried sibling re-ran its painter: the whole layer stack, paper,
/// onion ghosts and group-buffer `saveLayer`s included, once per pointer
/// event.
///
/// This file is the cost contract, and it is written to be HARD TO SATISFY
/// BY ACCIDENT: it proves the counters can move (liveness), that they are
/// quiet when nothing happens (control), that they do not move when the
/// cursor does (the claim), and that the cursor really did move (so a
/// cursor that simply stopped following cannot pass).
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.counter);

  /// A list, not an int: the painter is rebuilt with the widget tree and
  /// the count has to outlive that.
  final List<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter[0] += 1;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x11223344),
    );
  }

  /// FALSE: nothing about this painter ever changes, so any repaint it
  /// records came from an ancestor's paint walk — which is exactly the
  /// thing under test.
  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

void main() {
  /// Mounts the panel with two counting painters:
  ///
  ///  * `canvasPaints` through `viewportUnderlayBuilder` — the SAME seam
  ///    `editor_canvas_area` hangs `CanvasLayerStackView` on, and left BARE
  ///    on purpose. ⚠️Giving the underlay a `RepaintBoundary` would make
  ///    this counter stop responding to the very regression it exists to
  ///    catch, and the test would go green through it.
  ///  * `chromePaints` ABOVE the panel, under the nearest boundary in that
  ///    direction — standing in for the shell, whose floor, panbars and
  ///    floating controls used to be re-recorded too.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required CanvasTool tool,
    required List<int> canvasPaints,
    required List<int> chromePaints,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            child: CustomPaint(
              painter: _CountingPainter(chromePaints),
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
                brushToolState: BrushToolState.defaults.copyWith(
                  tool: tool,
                  size: 40,
                ),
                sampleColorAt: (_) => 0x336699,
                onEyedropperPick: (_) {},
                viewportUnderlayBuilder: (context, viewport, painter) =>
                    CustomPaint(
                      painter: _CountingPainter(canvasPaints),
                      child: const SizedBox.expand(),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (tool, cursorKey) in const <(CanvasTool, String)>[
    (CanvasTool.brush, 'brush-cursor-overlay'),
    (CanvasTool.eraser, 'brush-cursor-overlay'),
    (CanvasTool.fill, 'fill-cursor-icon'),
    (CanvasTool.eyedropper, 'eyedropper-cursor-icon'),
  ]) {
    testWidgets('moving the ${tool.name} cursor does not re-record the '
        'artwork', (tester) async {
      final canvasPaints = <int>[0];
      final chromePaints = <int>[0];
      await pumpPanel(
        tester,
        tool: tool,
        canvasPaints: canvasPaints,
        chromePaints: chromePaints,
      );

      // ARM — the cursor only exists once the census has seen the pointer.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
      await tester.pump();
      final cursor = find.byKey(ValueKey<String>(cursorKey));
      expect(cursor, findsOneWidget, reason: 'the $cursorKey must be up');

      // LIVENESS — a fixture whose underlay never painted would pass every
      // assertion below without proving anything.
      expect(
        canvasPaints[0],
        greaterThan(0),
        reason: 'the underlay seam has to have actually run',
      );

      // CONTROL — the fixture must be quiet, or the treatment says nothing.
      var canvasBefore = canvasPaints[0];
      var chromeBefore = chromePaints[0];
      await tester.pump();
      await tester.pump();
      expect(canvasPaints[0], canvasBefore);
      expect(chromePaints[0], chromeBefore);

      // TREATMENT — eight moves, 4px apart.
      final start = tester.getTopLeft(cursor);
      canvasBefore = canvasPaints[0];
      chromeBefore = chromePaints[0];
      for (var i = 1; i <= 8; i += 1) {
        await mouse.moveTo(canvasGlobalOffset(tester, Offset(4.0 + i * 4, 4)));
        await tester.pump();
      }

      // DEAD — the whole point.
      expect(
        canvasPaints[0],
        canvasBefore,
        reason: 'a cursor move must not re-record the artwork',
      );

      // AND THE SHELL ABOVE IT. This used to climb once per move and the
      // first attempt to stop it — a boundary around the viewport, between
      // the ClipRect and the deck — changed the count NOT AT ALL, so it was
      // removed and the remainder written down as unexplained.
      //
      // 🚨The measurement was the thing at fault, not the boundary. This
      // counter rises AT MOST ONCE PER FRAME however many descendants
      // dirtied, so with two independent sources above the artwork, muting
      // one is invisible: 8 either way. Bisecting with a SECOND boundary
      // outside the panel found where it actually stops — the shell's
      // content slot, one level above everything the viewport owns.
      //
      // ⚠️The lesson is the counter's, not the tree's: a saturating metric
      // cannot measure a partial fix. It can only ever say "still nonzero".
      expect(
        chromePaints[0],
        chromeBefore,
        reason: 'nor may it escalate into the shell — the floor, the '
            'panbar capsules and the pill all live above this',
      );

      // ALIVE — and the cursor still followed, so "it stopped moving" is
      // not a way to pass this test.
      expect(cursor, findsOneWidget);
      expect(
        tester.getTopLeft(cursor).dx - start.dx,
        closeTo(32, 0.5),
        reason: 'the cursor tracked all eight moves',
      );
    });
  }

  testWidgets('the fill bucket and its cursor-hiding region mount together', (
    tester,
  ) async {
    // 🐛The canvas Stack's short-circuit listed every cursor predicate but
    // this one, and with fill armed every other conjunct holds: the tap
    // handler is null (R22-A puts the dab through the stroke pipeline) and
    // `canvasToolPaints(fill)` is false. So the Stack was skipped whole,
    // taking the bucket AND the `SystemMouseCursors.none` region with it —
    // in the conte, the cut envelope and the timesheet, which pass no
    // underlay or overlay and therefore sit in that branch permanently.
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(8, 8)));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('fill-cursor-tracker')),
      findsOneWidget,
      reason: 'the region that hides the system cursor',
    );
    expect(
      find.byKey(const ValueKey<String>('fill-cursor-icon')),
      findsOneWidget,
      reason: 'and the bucket that replaces it',
    );
  });
}
