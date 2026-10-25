import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ContainerLayer, Layer, PictureLayer, RendererBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_cursor_geometry.dart';
import 'package:anicel/src/ui/brush/brush_cursor_painter.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/drawing_cursor.dart';
import 'package:anicel/src/ui/brush/tool_cursor_look.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/frame_census.dart';
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
  ///    `editor_canvas_area` hangs the frame's picture on, and left BARE
  ///    on purpose. ⚠️Giving the underlay a `RepaintBoundary` would make
  ///    this counter stop responding to the very regression it exists to
  ///    catch, and the test would go green through it.
  ///  * `chromePaints` ABOVE the panel, under the nearest boundary in that
  ///    direction — standing in for the shell, whose floor, panbars and
  ///    floating controls used to be re-recorded too.
  ///
  /// Returns the brush the panel hears, so a test can change it in hand.
  Future<ValueNotifier<BrushToolState>> pumpPanel(
    WidgetTester tester, {
    required CanvasTool tool,
    required List<int> canvasPaints,
    required List<int> chromePaints,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(tool: tool, size: 40),
    );
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
                brushToolState: brush,
                sampleColorAt: (_) => 0x336699,
                onEyedropperPick: (_) {},
                viewportUnderlayBuilder: (context, viewport, painter, _) =>
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
    return brush;
  }

  // The bucket and the dropper are the app's for a pen hovering — a mouse
  // is shown the system's (`appDrawsLook`).
  for (final (tool, cursorKey, kind)
      in const <(CanvasTool, String, PointerDeviceKind)>[
        (CanvasTool.brush, 'brush-cursor-overlay', PointerDeviceKind.mouse),
        (CanvasTool.eraser, 'brush-cursor-overlay', PointerDeviceKind.mouse),
        (CanvasTool.fill, 'fill-cursor-icon', PointerDeviceKind.stylus),
        (
          CanvasTool.eyedropper,
          'eyedropper-cursor-icon',
          PointerDeviceKind.stylus,
        ),
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
      final mouse = await tester.createGesture(kind: kind);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
      await tester.pump();
      final cursor = find.byKey(ValueKey<String>(cursorKey));
      expect(
        toolCursorShownAt(tester, cursor),
        isNotNull,
        reason: 'the $cursorKey must be up',
      );

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
      final start = toolCursorShownAt(tester, cursor)!;
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
      final end = toolCursorShownAt(tester, cursor);
      expect(end, isNotNull);
      expect(
        end!.dx - start.dx,
        closeTo(32, 0.5),
        reason: 'the cursor tracked all eight moves',
      );
    });
  }

  // 🚨H40 ② (2026-09-24): the brush changes by the frame — a preset pick,
  // every frame of a settings slider drag, each colour notch. The panel was
  // handed it as a VALUE, so each change rebuilt the panel and relaid out
  // its shell, and the pill, both panbars and the edges repainted for
  // numbers they do not show. The panel HEARS the brush now: its tree
  // follows the tool alone, and the one thing that shows a size — the tip
  // cursor — answers a size by itself.
  testWidgets('a brush change repaints the tip cursor and the way to it, '
      'nothing beside', (
    tester,
  ) async {
    final canvasPaints = <int>[0];
    final chromePaints = <int>[0];
    final brush = await pumpPanel(
      tester,
      tool: CanvasTool.brush,
      canvasPaints: canvasPaints,
      chromePaints: chromePaints,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
    await tester.pump();
    final cursor = find.byKey(const ValueKey<String>('brush-cursor-overlay'));
    final extentBefore = tester.widget<ToolCursorSprite>(cursor).look.extent;
    // The tip's picture, inside the sprite's moving layer.
    Layer? tipPicture() =>
        (tester.renderObject(cursor).debugLayer?.firstChild as ContainerLayer?)
            ?.firstChild;
    final tipBefore = tipPicture();
    expect(tipBefore, isA<PictureLayer>(), reason: '⛔전제: the tip is drawn');

    final canvasBefore = canvasPaints[0];
    final chromeBefore = chromePaints[0];

    // What the cursor does not show reaches nothing at all.
    final unseen = await frameCensus(
      tester,
      () => brush.value = brush.value.copyWith(flow: 0.5, color: 0xFF336699),
    );
    expect(unseen.rebuilt, isEmpty);
    expect(unseen.painted, isEmpty);

    final (:rebuilt, :painted) = await frameCensus(
      tester,
      () => brush.value = brush.value.copyWith(size: 80),
    );

    // ALIVE — the cursor wears the new tip.
    expect(
      tester.widget<ToolCursorSprite>(cursor).look.extent.width,
      greaterThan(extentBefore.width),
    );
    // THE CLAIM — the panel did not rebuild, and what repainted is the
    // cursor and the path down to it, nothing beside it: the cursor's
    // builder sits under the canvas's `LayoutBuilder`, whose own build
    // scope relays it out for a dirty descendant — the few boxes between
    // it and the cursor. Measured 2026-09-24: ten objects, the gesture
    // layer's listeners, its clip and the deck.
    expect(rebuilt, isNot(contains(BrushCanvasPanel)));
    final sprite = tester.renderObject(cursor);
    bool leadsToTheCursor(RenderObject object) {
      for (RenderObject? at = sprite; at != null; at = at.parent) {
        if (identical(at, object)) {
          return true;
        }
      }
      return false;
    }

    // A boundary beside the path is handed on with its layer as it was —
    // the artwork's is — and is reported all the same; only what it paints
    // inside would mean it painted again.
    bool handedOn(RenderObject object) =>
        object.isRepaintBoundary && !paintedInside(painted, object);

    // The tip drew again. ↩️Read off [painted] until F-428 made each cursor
    // a tick of its dock's still region: the sprite is a boundary of its own
    // under its tick now, and repaints by itself — the census hears a paint
    // only from the parent that paints a child, so its picture says it.
    expect(tipPicture(), isNot(same(tipBefore)), reason: 'the tip drew again');
    expect(
      [
        for (final object in painted)
          if (!leadsToTheCursor(object) && !handedOn(object))
            object.runtimeType,
      ],
      isEmpty,
      reason: 'nothing beside the path to the cursor — the pill, the '
          'panbars and the edges repainted when the panel rebuilt',
    );
    expect(canvasPaints[0], canvasBefore);
    expect(chromePaints[0], chromeBefore);

    // CONTROL — the census can see a panel rebuild: a TOOL change is one.
    final toolChange = await frameCensus(
      tester,
      () => brush.value = brush.value.copyWith(tool: CanvasTool.eraser),
    );
    expect(toolChange.rebuilt, contains(BrushCanvasPanel));
  });

  // 🚨F-176-Q7 (유저 2026-10-21 「펜을 따라 바뀐다」): the outline of a
  // tilted pencil is the tip the pen lays down — turned by its lean and
  // flattened as it lies down. A hovering pen's lean changes by the event,
  // so it is held to what a brush change is held to: the cursor and the way
  // to it, nothing beside — the law the F-130 cursor lives by.
  testWidgets('🚨a leaning pen turns and flattens the outline — the tip it '
      'lays down — and repaints the cursor alone (F-176-Q7)', (tester) async {
    final canvasPaints = <int>[0];
    final chromePaints = <int>[0];
    final brush = await pumpPanel(
      tester,
      tool: CanvasTool.brush,
      canvasPaints: canvasPaints,
      chromePaints: chromePaints,
    );
    // The tilted pencil: the tip turns with the pen's lean and is as round
    // as the pen leans.
    brush.value = brush.value.copyWith(
      shape: brush.value.shape
          .withCurve(
            BrushPressureTarget.roundness,
            BrushInputSource.tilt,
            BrushPressureCurve.linearFrom(0.0),
          )
          .copyWith(rotationMode: BrushTipRotationMode.penTilt),
    );
    final cursor = find.byKey(const ValueKey<String>('brush-cursor-overlay'));
    BrushCursorShape shape() =>
        (tester.widget<ToolCursorSprite>(cursor).look.painter
                as BrushCursorPainter)
            .shape!;
    // The pointer carries the lean on the test's platform (Android): [tilt]
    // from vertical, and the top leaning to the bottom of the screen.
    void hover(Offset at, {required double tilt}) =>
        tester.binding.handlePointerEvent(
          PointerHoverEvent(
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, at),
            tilt: tilt,
          ),
        );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
    await tester.pump();
    expect(
      shape().minorRadius,
      closeTo(shape().majorRadius, 1e-6),
      reason: 'a mouse has no pose: the tip as it is set, round',
    );

    hover(const Offset(8, 4), tilt: math.pi / 4);
    await tester.pump();
    expect(
      shape().minorRadius / shape().majorRadius,
      closeTo(0.5, 1e-6),
      reason: 'half way down is half the lean: half as round',
    );
    expect(
      shape().majorAxis.dx.abs(),
      lessThan(1e-6),
      reason: 'a pen leaning toward the bottom of the screen turns the tip '
          'to stand up and down',
    );

    // The tip's picture, inside the sprite's moving layer.
    Layer? tipPicture() =>
        (tester.renderObject(cursor).debugLayer?.firstChild as ContainerLayer?)
            ?.firstChild;
    final tipBefore = tipPicture();
    expect(tipBefore, isA<PictureLayer>(), reason: '⛔전제: the tip is drawn');
    final canvasBefore = canvasPaints[0];
    final chromeBefore = chromePaints[0];
    final (:rebuilt, :painted) = await frameCensus(
      tester,
      () => hover(const Offset(12, 4), tilt: math.pi / 3),
    );
    // ALIVE — the outline followed the lean.
    expect(shape().minorRadius / shape().majorRadius, closeTo(2 / 3, 1e-6));
    // THE CLAIM — as for a brush change: the panel did not rebuild, and
    // nothing beside the way to the cursor painted.
    expect(rebuilt, isNot(contains(BrushCanvasPanel)));
    final sprite = tester.renderObject(cursor);
    bool leadsToTheCursor(RenderObject object) {
      for (RenderObject? at = sprite; at != null; at = at.parent) {
        if (identical(at, object)) {
          return true;
        }
      }
      return false;
    }

    // The tip drew again — by its picture, as for a brush change: the
    // sprite is a boundary of its own under its tick (F-428), and the
    // census hears a paint only from the parent that paints a child.
    expect(tipPicture(), isNot(same(tipBefore)), reason: 'the tip drew again');
    expect([
      for (final object in painted)
        if (!leadsToTheCursor(object) &&
            !(object.isRepaintBoundary && !paintedInside(painted, object)))
          object.runtimeType,
    ], isEmpty);
    expect(canvasPaints[0], canvasBefore);
    expect(chromePaints[0], chromeBefore);

    // And the mouse again has no pose — the tip as it is set.
    await mouse.moveTo(canvasGlobalOffset(tester, const Offset(16, 4)));
    await tester.pump();
    expect(shape().minorRadius, closeTo(shape().majorRadius, 1e-6));
  });

  testWidgets('the fill bucket and its cursor region mount together', (
    tester,
  ) async {
    // 🐛The canvas Stack's short-circuit listed every cursor predicate but
    // this one, and with fill armed every other conjunct holds: the tap
    // handler is null (R22-A puts the dab through the stroke pipeline) and
    // `canvasToolPaints(fill)` is false. So the Stack was skipped whole,
    // taking the bucket AND the region that says the cursor with it —
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
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.fill,
            )),
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
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      LookMouseCursor(fillCursorLook(), devicePixelRatio: 3),
      reason: 'the region asks the system for the bucket under a mouse',
    );

    // A pen hovering, which the system shows none of it (`appDrawsLook`).
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: Offset.zero);
    addTearDown(pen.removePointer);
    await pen.moveTo(canvasGlobalOffset(tester, const Offset(8, 8)));
    await tester.pump();
    expect(
      toolCursorShownAt(
        tester,
        find.byKey(const ValueKey<String>('fill-cursor-icon')),
      ),
      isNotNull,
      reason: 'and the bucket the app draws for a pointer the system '
          'shows none',
    );
  });
}
