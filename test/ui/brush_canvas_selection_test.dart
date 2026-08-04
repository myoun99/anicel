import 'dart:ui' show ImageByteFormat, PictureRecorder;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

import '../helpers/brush_canvas_fixture.dart';

/// P9 widget routing on the R19 pixel model: the selection layer mounts
/// only for selection tools, regions select PIXELS, move sessions float
/// until ONE confirmed history entry, and all oracles are the raster
/// itself (commands retired — the picture is the record).
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      HistoryManager history,
      CanvasSelectionCommands commands,
      Future<void> Function(CanvasTool tool) setTool,
    })
  >
  pumpSelectionPanel(
    WidgetTester tester, {
    CanvasTool tool = CanvasTool.selectRect,
    // Extra committed ink, mounted with the fixture. `null` replaces the
    // in-canvas stroke entirely (a cel whose only ink is off-canvas).
    List<BrushDab>? sourceDabs,
    // A canvas SMALLER than the 800×600 test viewport, so pasteboard
    // coordinates are reachable by a pointer at all.
    CanvasSize canvasSize = BrushCanvasFixture.canvasSize,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    // One committed stroke around canvas (30..60, 30..60).
    coordinator.commitSourceStroke(
      sourceDabs: sourceDabs ?? [dab(30, 30), dab(45, 45), dab(60, 60)],
    );

    Future<void> pumpWith(CanvasTool tool) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey<String>('panel-capture'),
              child: BrushCanvasPanel(
              coordinator: coordinator,
              // The panel carries its OWN canvas size, independent of the
              // coordinator's session store — passing only the fixture's
              // left the panel at the 2340×1654 default, which silently
              // put every reachable pointer position back on canvas.
              canvasSize: canvasSize,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(tool: tool),
              selectionCommands: commands,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith(tool);
    return (
      coordinator: coordinator,
      history: history,
      commands: commands,
      setTool: pumpWith,
    );
  }

  /// A picture that covers more than the painter's four-tile per-pixel
  /// budget (tiles are 256 px), which is the threshold below which every
  /// float defect is invisible.
  ///
  /// ⚠️ A grid, not a diagonal. The first version of this ran from
  /// (30,30) to (710,506) and touched EXACTLY four tiles, so the budget
  /// covered all of it and the tests it was written for passed without
  /// their fixes. Nine tiles here, comfortably past it.
  final widePicture = <BrushDab>[
    for (var y = 30; y <= 550; y += 40)
      for (var x = 30; x <= 750; x += 40) dab(x.toDouble(), y.toDouble()),
  ];

  /// The cel's CURRENT pixels — 0/null means transparent.
  int inkAt(BrushFrameEditingCoordinator coordinator, int x, int y) {
    return surfacePixelRgba(
          coordinator.currentSurfaceOf(coordinator.activeFrameKey),
          x,
          y,
        ) ??
        0;
  }

  BitmapSurface currentSurface(BrushFrameEditingCoordinator coordinator) =>
      coordinator.currentSurfaceOf(coordinator.activeFrameKey);

  /// How much of the RED fixture ink the COMPOSITED panel is showing —
  /// base, float, held preview and all, exactly what the user's eye gets.
  ///
  /// ⚠️ `toImageSync`, captured before any `runAsync`: the frame under
  /// test is one where nothing has decoded yet, and giving the pipeline an
  /// idle slice first would let the committed tiles land and report the
  /// defect as fixed. The snapshot is read afterwards, which is safe
  /// because it is a snapshot.
  Future<int> screenInk(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('panel-capture')),
    );
    final image = boundary.toImageSync();
    var red = 0;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 128 && bytes[i + 1] < 100 && bytes[i + 2] < 100) {
          red += 1;
        }
      }
    });
    image.dispose();
    return red;
  }

  /// Lets the real decode pipeline run to completion, so the committed
  /// surface can paint and any hold releases.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
  }

  Future<void> dragOnLayer(WidgetTester tester, Offset from, Offset to) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + from);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('P3a: the bytes the PREVIEW showed are the bytes Enter '
      'writes — the contract, tested at last', (tester) async {
    // Before P3a this was untestable because it was false. The affine and
    // quad previews were a Skia widget Transform over tiles drawn at
    // FilterQuality.none, and the mesh preview was drawVertices through an
    // ImageShader at FilterQuality.medium — three screen approximations,
    // none of which agreed with the Catmull-Rom the commit ran. The whole
    // point of a mode that preserves colours exactly is to SEE the result
    // before committing to it, so the preview and the commit now share one
    // buffer rather than two computations that ought to match.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    debugLastResampledFloat = null;
    env.commands.beginTransform();
    await tester.pump();
    // A rotation, so the resampler actually runs (a pure translation
    // short-circuits and never reaches it).
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();

    final previewed = debugLastResampledFloat;
    expect(
      previewed,
      isNotNull,
      reason: 'an open rotation must have produced a resampled float',
    );
    final stamp = previewed!.stamp!;
    final previewBytes = Uint8List.fromList(stamp.rgba);
    final left = (previewed.center.x - stamp.width / 2).round();
    final top = (previewed.center.y - stamp.height / 2).round();

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);

    // Every fully opaque pixel of the preview must be exactly that colour
    // in the landed picture. Opaque only: a partial-alpha pixel composites
    // against whatever was underneath, which is a different question.
    var checked = 0;
    for (var y = 0; y < stamp.height; y += 1) {
      for (var x = 0; x < stamp.width; x += 1) {
        final offset = (y * stamp.width + x) * 4;
        if (previewBytes[offset + 3] != 255) {
          continue;
        }
        final landed = surfacePixelRgba(
          currentSurface(env.coordinator),
          left + x,
          top + y,
        );
        expect(
          landed,
          isNotNull,
          reason: 'the preview showed a pixel at ($x,$y) and nothing landed',
        );
        expect(
          [
            landed! & 0xff,
            (landed >> 8) & 0xff,
            (landed >> 16) & 0xff,
            (landed >> 24) & 0xff,
          ],
          [
            previewBytes[offset],
            previewBytes[offset + 1],
            previewBytes[offset + 2],
            previewBytes[offset + 3],
          ],
          reason: 'preview and commit disagree at ($x,$y)',
        );
        checked += 1;
      }
    }
    expect(
      checked,
      greaterThan(0),
      reason: 'a preview with no opaque pixel proves nothing',
    );
  });

  testWidgets('P3a: an arrow-key nudge with the box open moves the '
      'PICTURE, not just the outline', (tester) async {
    // Caught by adversarial review, not by the suite. Once the preview is
    // a resampled bitmap rather than a matrix evaluated in build, any
    // mutation of the open warp that forgets to schedule a resample moves
    // the ants and the box chrome while the artwork stays put — and Enter
    // then lands the ink where the outline is, not where the picture was.
    // Master could not have this bug: it recomputed the screen matrix on
    // every build.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();
    final before = debugLastResampledFloat!.center;

    await tester.runAsync(() async {
      for (var i = 0; i < 10; i += 1) {
        env.commands.nudge(1, 0);
      }
      // The decode from the rotation above is still in flight, so the
      // nudges only mark the preview dirty; the callback runs the last
      // state. Letting that settle is the realistic path, and asserting
      // after it is what makes this test about the SCHEDULING rather than
      // about how many resamples one drag happens to trigger.
      //
      // Waits for the EVENT, not for the clock. A fixed delay here failed
      // in the full suite and passed on its own, which is the signature of
      // a test that measures the machine: under load the resample had not
      // landed in 100 ms. Polling for "the float moved at all" keeps the
      // assertion honest — it can still be the wrong value, and a
      // resample that never happens still times out and fails.
      for (var waited = 0; waited < 60; waited += 1) {
        if (debugLastResampledFloat!.center != before) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(
      debugLastResampledFloat!.center.x,
      before.x + 10,
      reason: 'the resampled float must follow the nudge',
    );
    expect(debugLastResampledFloat!.center.y, before.y);
  });

  testWidgets('the DEFAULT mode smooths — the guard that keeps the '
      'colour-preservation assertions from being vacuous', (tester) async {
    // Named for what it actually does. It does NOT drive the AA-off
    // switch: this harness builds BrushCanvasPanel without
    // transformResampleMode, so the layer reads the blend default and no
    // test here can change it.
    //
    // What it is for: the colour-preservation tests elsewhere assert that
    // Pick invents no new colours. That assertion is worth nothing unless
    // the default DOES invent them on the same transform — otherwise a
    // resampler that had quietly stopped interpolating would satisfy both.
    // This is the control.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    final before = currentSurface(env.coordinator);
    final sourceColours = <int>{};
    for (var y = 0; y < 90; y += 1) {
      for (var x = 0; x < 90; x += 1) {
        final pixel = surfacePixelRgba(before, x, y);
        if (pixel != null && (pixel >> 24) != 0) sourceColours.add(pixel);
      }
    }
    expect(sourceColours, isNotEmpty);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();

    // Blend is the default, and a rotation through it MUST invent
    // in-between colours — otherwise the assertion below proves nothing.
    final landed = currentSurface(env.coordinator);
    var invented = 0;
    for (var y = 0; y < 90; y += 1) {
      for (var x = 0; x < 90; x += 1) {
        final pixel = surfacePixelRgba(landed, x, y);
        if (pixel != null &&
            (pixel >> 24) != 0 &&
            !sourceColours.contains(pixel)) {
          invented += 1;
        }
      }
    }
    expect(
      invented,
      greaterThan(0),
      reason:
          'AA on must smooth; if it does not, the AA-off assertion in '
          'the sibling test is vacuous',
    );
  });

  testWidgets('the layer mounts for selection tools only', (tester) async {
    await pumpSelectionPanel(tester, tool: CanvasTool.brush);
    expect(find.byKey(layerKey), findsNothing);

    await pumpSelectionPanel(tester);
    expect(find.byKey(layerKey), findsOneWidget);
    expect(find.byType(CanvasSelectionLayer), findsOneWidget);
  });

  testWidgets('marquee selects; the MOVE tool floats a session and the '
      'confirm lands ONE undoable pixel move (R11-⑧/R16-①)', (tester) async {
    final env = await pumpSelectionPanel(tester);

    // Marquee around the whole stroke (viewport is identity: local ==
    // canvas coordinates).
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);

    // A MARQUEE-tool drag inside the region draws a NEW region — content
    // never moves on the selection tools.
    await dragOnLayer(tester, const Offset(25, 25), const Offset(68, 68));
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
    expect(env.commands.hasSelection, isTrue);

    // The MOVE tool opens a TVP-style SESSION: the lift's erase lands raw
    // (origin vanishes), drags move only the floating stamp — nothing is
    // undoable until the CONFIRM.
    await env.setTool(CanvasTool.move);
    final entriesBeforeMove = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));

    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'pending: the base holds only the erase — origin is blank',
    );
    expect(env.commands.movePending, isTrue);
    expect(
      env.history.undoCount,
      entriesBeforeMove,
      reason: 'nothing is undoable before the confirm',
    );

    // CONFIRM: one history entry; the pixels land moved by (+10,+5).
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBeforeMove + 1);
    expect(inkAt(env.coordinator, 40, 35), isNonZero);
    expect(inkAt(env.coordinator, 28, 28), 0);

    env.history.undo(); // the WHOLE session (lift + move) as one step
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );

    env.history.redo();
    await tester.pump();
    expect(inkAt(env.coordinator, 40, 35), isNonZero);

    // Outside the region the move tool does nothing.
    await dragOnLayer(tester, const Offset(150, 150), const Offset(170, 170));
    expect(inkAt(env.coordinator, 40, 35), isNonZero);
  });

  testWidgets('R26 #13: the MOVE tool with NO selection drags the WHOLE '
      'picture — implicit whole-canvas session, ONE confirmed entry, and '
      'the end returns to no selection', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    expect(env.commands.hasSelection, isFalse);

    final entriesBefore = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    expect(env.commands.movePending, isTrue);
    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'the whole picture lifted — the origin is blank while pending',
    );

    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.history.undoCount, entriesBefore + 1);
    expect(inkAt(env.coordinator, 40, 35), isNonZero, reason: '+10,+5 landed');
    expect(
      env.commands.hasSelection,
      isFalse,
      reason: 'the implicit shape ends with the session — no stray ants',
    );

    env.history.undo();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );
  });

  testWidgets('the whole picture means the PASTEBOARD too — no-selection '
      'move carries off-canvas ink with the rest', (tester) async {
    // User report (08-04): "when the drawing runs out into the pasteboard
    // and I transform with nothing selected, only the part inside the
    // canvas becomes the target". The implicit whole-picture shape was
    // reading the cel's true ink bounds and then clamping them to the
    // canvas rect, so off-canvas ink stood still while the picture moved
    // out from under it.
    //
    // The oracle is the RASTER at the off-canvas coordinate, not the
    // region bounds: a fix that lifts the right rect and then clips at
    // the commit would pass a bounds assertion and still be the bug.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      sourceDabs: [dab(-20, -20), dab(30, 30), dab(45, 45), dab(60, 60)],
    );
    expect(
      inkAt(env.coordinator, -20, -20),
      isNonZero,
      reason: 'the fixture really does hold pasteboard ink',
    );

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(inkAt(env.coordinator, 40, 35), isNonZero, reason: '+10,+5 landed');
    expect(
      inkAt(env.coordinator, -10, -15),
      isNonZero,
      reason: 'the pasteboard dab moved by the same +10,+5',
    );
    expect(
      inkAt(env.coordinator, -20, -20),
      0,
      reason: 'and it LEFT its old place — not copied, moved',
    );
  });

  testWidgets('a cel whose only ink is on the pasteboard still has a whole '
      'picture to move', (tester) async {
    // The degenerate branch: with the canvas clamp, pasteboard-only ink
    // collapsed to an empty rect and fell back to the whole canvas —
    // which holds nothing — so the drag lifted emptiness and the drawing
    // could not be moved at all.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      sourceDabs: [dab(-200, -200), dab(-180, -180)],
    );
    expect(inkAt(env.coordinator, -200, -200), isNonZero);

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(
      inkAt(env.coordinator, -190, -195),
      isNonZero,
      reason: 'pasteboard-only ink moves like any other picture',
    );
    expect(inkAt(env.coordinator, -200, -200), 0);
  });

  testWidgets('a press on the PASTEBOARD grabs the whole picture too — the '
      'box frames ink you can also take hold of', (tester) async {
    // The handles were already grabbable off-canvas (_hitTestTransformHandle
    // has no stage gate), so once the box frames pasteboard ink, a
    // canvas-only press gate leaves exactly one thing you can see framed
    // and cannot grab by pressing on it.
    const small = CanvasSize(width: 200, height: 150);
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      canvasSize: small,
      sourceDabs: [dab(30, 30), dab(300, 100)],
    );
    // The viewport is identity here, so widget offsets ARE canvas
    // coordinates. (250,60) is past the 200-wide canvas — pasteboard —
    // and well clear of the implicit box's handles, which sit on the
    // corners and edge midpoints of the ink bounds and are grabbable
    // off-canvas already: pressing the corner at (300,100) scales
    // instead of moving, which is how this test first read as a failure.
    expect(inkAt(env.coordinator, 300, 100), isNonZero);
    expect(
      small.containsPasteboardPoint(x: 250, y: 60),
      isTrue,
      reason: '(250,60) is past the 200×150 canvas but inside its pasteboard',
    );

    await dragOnLayer(tester, const Offset(250, 60), const Offset(260, 65));
    expect(
      env.commands.movePending,
      isTrue,
      reason: 'the press on the pasteboard opened the implicit session',
    );
    env.commands.confirmPendingMove();
    await tester.pump();
    // TRANSLATION, asserted at both ends: a handle grab would scale about
    // the opposite corner and leave the anchor ink standing, so "the old
    // place is empty" is the assertion that tells a move from a scale.
    expect(
      inkAt(env.coordinator, 310, 105),
      isNonZero,
      reason: 'the pasteboard dab moved +10,+5',
    );
    expect(inkAt(env.coordinator, 298, 98), 0, reason: 'and left its old one');
    expect(
      inkAt(env.coordinator, 40, 35),
      isNonZero,
      reason: 'and so did the in-canvas one — one picture, one move',
    );
    expect(inkAt(env.coordinator, 28, 28), 0, reason: 'nothing stayed behind');
  });

  testWidgets('R28 #10: a SECOND transform on the same tool works — the '
      'first one\'s confirm must not leave the layer unable to lift', (
    tester,
  ) async {
    // The user\'s report is about transforming twice in a row WITHOUT
    // switching tools ("변형 한번하고 다시 변형하면"), which is the one path
    // the R27 #18 fix did not cover — it hung the cleanup on a tool
    // change. Both rounds here run on the Move tool.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // Round 1: implicit whole-picture transform, confirmed.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 45));
    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.transformActive, isFalse);
    expect(inkAt(env.coordinator, 40, 30), isNonZero, reason: '+10 landed');
    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'the origin is empty — the lift erased it',
    );

    // Round 2: the SAME thing again.
    env.commands.beginTransform();
    await tester.pump();
    expect(
      env.commands.transformActive,
      isTrue,
      reason: 'R28 #10: the second transform must actually OPEN',
    );
    expect(
      inkAt(env.coordinator, 40, 30),
      0,
      reason:
          'R28 #10: the second lift has to ERASE its origin too — '
          'leaving it is how the user saw "원본그림 존재하고 변형된 그림도 존재"',
    );

    // The picture moved +10, so the box did too — grab it where it now is.
    await dragOnLayer(tester, const Offset(55, 45), const Offset(65, 45));
    env.commands.commitTransform();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 50, 30),
      isNonZero,
      reason: 'the second +10 landed',
    );
    expect(inkAt(env.coordinator, 40, 30), 0);
  });

  testWidgets('R26 #13: REVERTING the implicit whole-picture session '
      'restores the picture, leaves NO selection and records NOTHING', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    expect(env.commands.movePending, isTrue);

    env.commands.revertPendingMove();
    await tester.pump();
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
    expect(env.commands.hasSelection, isFalse);
    expect(env.history.undoCount, entriesBefore);
  });

  testWidgets('Ctrl+corner opens the PERSPECTIVE quad (R20-D2): the '
      'numeric channels blank out and Enter commits ONE resampled entry', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final entriesBefore = env.history.undoCount;

    // Ctrl+grab the top-left corner handle of the always-on box and pinch
    // it inward — the PS perspective gesture.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final gesture = await tester.startGesture(origin + const Offset(20, 20));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(34, 24));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(env.commands.transformActive, isTrue, reason: 'quad session open');
    expect(
      env.commands.transformValues,
      isNull,
      reason: 'a free quad has no affine channels — the fields blank out',
    );

    // Enter: resample through the homography + confirm as ONE entry.
    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBefore + 1);

    // One undo restores the pre-lift picture whole.
    env.history.undo();
    await tester.pump();
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
  });

  testWidgets('Mesh Warp (R20-D3): the control grid opens on the '
      'selection, a dragged point + Enter commits ONE warped entry', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    await tester.runAsync(() async {
      env.commands.beginMeshTransform();
      // Let the float decode land (drawVertices live warp preview, R21).
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
    expect(
      env.commands.transformValues,
      isNull,
      reason: 'a mesh has no affine channels — the fields blank out',
    );
    expect(
      find.byKey(const ValueKey<String>('transform-resample-preview')),
      findsOneWidget,
      reason: 'the live warp preview mounts once the float image decodes',
    );

    // Drag an interior control point (stamp rect (20,20)-(71,71), 3×3
    // cells → pitch 17: the (1,1) point sits at (37,37)).
    await dragOnLayer(tester, const Offset(37, 37), const Offset(31, 42));

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBefore + 1);

    env.history.undo();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );
  });

  testWidgets('the session floats through the WHOLE interaction: the base '
      'holds only the erase until the confirm; a zero-move confirm is a '
      'byte-identical landing (R16-①)', (tester) async {
    final env = await pumpSelectionPanel(tester);
    final beforeLift = currentSurface(env.coordinator);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(45, 45));
    await tester.pump();
    // Mid-drag: the base carries the erase but NOT the stamp — the base
    // never shows the moving pixels (no double image).
    expect(inkAt(env.coordinator, 30, 30), 0);
    expect(inkAt(env.coordinator, 45, 45), 0);

    // Zero-move release: the session STAYS pending (the float keeps
    // showing the pixels); the base still holds only the erase.
    await gesture.up();
    await tester.pump();
    expect(env.commands.movePending, isTrue);
    expect(inkAt(env.coordinator, 45, 45), 0);

    // Confirm: the stamp lands at its origin — byte-identical picture
    // (the R14-④ zero-move lift-and-drop pin, now at the widget level).
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(currentSurface(env.coordinator), equals(beforeLift));
  });

  testWidgets('REVERT puts the pixels back exactly and records nothing '
      '(R17-①: the prompt\'s 되돌리기)', (tester) async {
    final env = await pumpSelectionPanel(tester);
    final beforeLift = currentSurface(env.coordinator);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    await dragOnLayer(tester, const Offset(45, 45), const Offset(60, 60));
    expect(env.commands.movePending, isTrue);

    env.commands.revertPendingMove();
    await tester.pump();

    expect(env.commands.movePending, isFalse);
    expect(
      identical(currentSurface(env.coordinator), beforeLift),
      isTrue,
      reason: 'the pre-lift surface snapshot restores BY REFERENCE',
    );
    expect(env.history.undoCount, entriesBefore, reason: 'nothing recorded');
  });

  testWidgets('selecting and deselecting are undoable steps (R11-⑧)', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);
    expect(env.history.canUndo, isTrue);

    env.history.undo();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);

    env.history.redo();
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);

    // Ctrl+D is undoable too.
    env.commands.deselect();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);
    env.history.undo();
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);
  });

  testWidgets('a marquee missing the stroke selects nothing movable', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(100, 100), const Offset(140, 140));
    expect(env.commands.hasSelection, isTrue);

    // The move tool grabs nothing there (the region covers no pixels).
    await env.setTool(CanvasTool.move);
    await dragOnLayer(tester, const Offset(110, 110), const Offset(120, 120));
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
  });

  testWidgets('click-away and Ctrl+D deselect; nudges move by one pixel', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);

    // Arrow nudges move the SESSION's float only (R16-①); the confirm
    // lands the accumulated result as one entry.
    env.commands.nudge(1, 0);
    env.commands.nudge(0, -1);
    await tester.pump();
    expect(env.commands.movePending, isTrue);
    expect(inkAt(env.coordinator, 30, 30), 0, reason: 'origin erased');
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 31, 29),
      isNonZero,
      reason: 'pixels landed at the nudged position (+1,−1)',
    );

    // Ctrl+D (through the channel) deselects.
    env.commands.deselect();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);

    // Re-select. R26 #16: in the DEFAULT 추가 mode a click is inert —
    // clicking away must not throw a composite selection away.
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(layerKey)) + const Offset(150, 150),
    );
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);

    // In 갱신 (replace) mode the click-away deselect is back — Photoshop's.
    env.commands.combineMode = SelectionCombineMode.replace;
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(layerKey)) + const Offset(150, 150),
    );
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);
  });

  group('Ctrl+T free transform (R19 pixel model: lift + stamp resample)', () {
    testWidgets('inside-drag translates; Enter confirms the session as one '
        'undo entry — pure translation lands byte-preserved pixels', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));

      env.commands.beginTransform();
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
      expect(
        inkAt(env.coordinator, 30, 30),
        0,
        reason: 'Ctrl+T opened a lift session — the base holds the erase',
      );

      // Drag inside the box: rides the session (nothing committed yet —
      // the history holds only the marquee's Select entry).
      final undoDepthBefore = env.history.undoCount;
      await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 48));
      expect(env.history.undoCount, undoDepthBefore);

      env.commands.commitTransform();
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      // The (+10,+3) translation landed: (30,30) → (40,33).
      expect(inkAt(env.coordinator, 40, 33), isNonZero);
      expect(inkAt(env.coordinator, 30, 30), 0);
      expect(env.history.canUndo, isTrue);
      env.history.undo();
      expect(
        inkAt(env.coordinator, 30, 30),
        isNonZero,
        reason: 'one Ctrl+Z retires the whole lift session',
      );
    });

    testWidgets('a freshly lifted float never paints pixels its own surface '
        'does not have', (tester) async {
      // The user-visible bug: opening a transform made the artwork
      // "teleport somewhere else, apparently enlarged" for a frame and
      // come back.
      //
      // The float surface is materialised fresh from the lift, so every
      // tile object is new and the identity-keyed image cache misses on
      // all of them. The painter's answer to a missing image is to borrow
      // whatever decoded last at that COORDINATE within its stale scope —
      // and the float was the one painter in lib/ built without a scope,
      // which put it in a bucket shared by every float ever lifted. The
      // second Ctrl+T of a session therefore drew the FIRST one's artwork,
      // at the first one's place and size, into this float's tile grid.
      //
      // Stated as the invariant rather than the symptom: a painter may not
      // put ink where its own surface is empty. That holds whatever the
      // borrowing policy is, and it is what fails if the opt-out is
      // removed.
      final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));

      Future<void> settle() async {
        for (var i = 0; i < 8; i += 1) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      BitmapSurfacePainter floatPainter() {
        final committed = env.coordinator.currentSurfaceOf(
          env.coordinator.activeFrameKey,
        );
        final floats = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .where((painter) => !identical(painter.surface, committed))
            .toList();
        expect(
          floats,
          hasLength(1),
          reason: 'expected exactly one float painter over the committed one',
        );
        return floats.single;
      }

      // Generation one, decoded, so the shared bucket is populated with a
      // float's tiles at these coordinates.
      env.commands.beginTransform();
      await tester.pump();
      final generationOne = floatPainter().surface;
      await settle();
      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 0.4,
      );
      await tester.pump();
      await settle();
      env.commands.commitTransform();
      await tester.pump();
      await settle();

      // Generation two — the reported gesture. Its tiles are new and
      // undecoded, and the bucket from generation one is waiting.
      env.commands.beginTransform();
      await tester.pump();
      final painter = floatPainter();
      expect(
        identical(painter.surface, generationOne),
        isFalse,
        reason:
            'the second lift reused the first float — no borrowing '
            'could happen and this test would prove nothing',
      );
      await tester.runAsync(() async {
        final recorder = PictureRecorder();
        const size = Size(256, 256);
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(256, 256);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final painted = data!.buffer.asUint8List();
        var ghost = 0;
        var missing = 0;
        for (var y = 0; y < 256; y += 1) {
          for (var x = 0; x < 256; x += 1) {
            final alpha = painted[(y * 256 + x) * 4 + 3];
            final own = surfacePixelRgba(painter.surface, x, y) ?? 0;
            if (alpha > 0 && ((own >> 24) & 0xff) == 0) {
              ghost += 1;
            } else if (alpha == 0 && ((own >> 24) & 0xff) > 0) {
              missing += 1;
            }
          }
        }
        expect(
          ghost,
          0,
          reason:
              'the float painted $ghost pixels of artwork its own '
              'surface does not contain',
        );
        // The other half of the same frame, and the half a first attempt
        // at this fix got wrong. Not borrowing trades a wrong picture for
        // an ABSENT one, and absent is only acceptable while it does not
        // happen: an undecoded tile falls to the painter's per-pixel path,
        // whose budget is FOUR TILES a frame.
        expect(
          missing,
          0,
          reason:
              'the float left $missing pixels of its own artwork '
              'unpainted — the per-pixel budget no longer covers it',
        );
      });

      // Secondary, and deliberately AFTER the render: the scope is how the
      // invariant is currently kept, but the invariant is the contract. A
      // test that asserted only the scope would pass a painter that had one
      // and borrowed across a lift anyway.
      expect(
        painter.staleScope,
        isNotNull,
        reason: 'a scopeless painter shares the bucket every float writes to',
      );
    });

    testWidgets('a float that only MOVED keeps borrowing its own previous '
        'generation', (tester) async {
      // The regression the first version of this fix shipped, and the test
      // that would have caught it.
      //
      // `_floatSurface` is rebuilt from an empty surface at five sites, and
      // three of them regenerate a float that ALREADY EXISTS: a drag
      // release, every arrow-key nudge, and Ctrl+T over a pending move.
      // There the previous generation is a legitimate predecessor. Refusing
      // to borrow across it left a float wider than the painter's four-tile
      // per-pixel budget three-quarters blank for a frame — and under a
      // held arrow key, which regenerates about thirty times a second, it
      // strobed.
      //
      // So the scope is emptied when the float's CONTENT changes and not
      // when it merely moves. This is the "merely moves" half, and the
      // fixture must be WIDER than four tiles or the per-pixel path covers
      // the mistake and the test proves nothing.
      final env = await pumpSelectionPanel(tester);
      // The float only holds tiles where the lift found pixels, so the
      // fixture's small stroke yields two however wide the marquee is. A
      // diagonal across the cel is what puts more than four tiles in it —
      // and more than four is the whole point, because at four or fewer
      // the painter's per-pixel path hides the defect.
      env.coordinator.commitSourceStroke(
        sourceDabs: <BrushDab>[
          for (var step = 0; step <= 24; step += 1)
            dab(80 + step * 36.0, 80 + step * 26.0),
        ],
      );
      await tester.pump();
      await dragOnLayer(tester, const Offset(6, 6), const Offset(720, 540));
      await env.setTool(CanvasTool.move);

      BitmapSurfacePainter floatPainter() {
        final committed = env.coordinator.currentSurfaceOf(
          env.coordinator.activeFrameKey,
        );
        return tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .firstWhere((painter) => !identical(painter.surface, committed));
      }

      // A move drag: the lift happens on the way, and the release runs
      // `_commitMove`, which is the first of the three rebuilds that have
      // a legitimate predecessor.
      await dragOnLayer(tester, const Offset(300, 250), const Offset(310, 258));
      for (var i = 0; i < 10; i += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      final lifted = floatPainter().surface;
      expect(
        lifted.tiles.length,
        greaterThan(4),
        reason:
            'a float inside the four-tile per-pixel budget cannot show '
            'this defect — widen the marquee',
      );

      // A NUDGE: the same picture, one pixel over. The float is rebuilt, so
      // every tile object is new and undecoded, and the only thing that can
      // paint them this frame is its own previous generation.
      env.commands.nudge(1, 0);
      await tester.pump();
      final nudged = floatPainter();
      expect(
        identical(nudged.surface, lifted),
        isFalse,
        reason: 'the nudge did not rebuild the float, so this proves nothing',
      );
      var undecoded = 0;
      var borrowable = 0;
      for (final tile in nudged.surface.tiles.values) {
        if (BitmapTileImageCache.instance.imageFor(tile) != null) continue;
        undecoded += 1;
        final stale = BitmapTileImageCache.instance.latestImageForCoord(
          tile.coord,
          scope: nudged.staleScope,
        );
        if (stale != null) borrowable += 1;
      }
      expect(
        undecoded,
        greaterThan(4),
        reason: 'nothing was undecoded, so no borrow was ever needed',
      );
      expect(
        borrowable,
        undecoded,
        reason:
            'the float could not borrow its own previous generation for '
            '${undecoded - borrowable} of $undecoded tiles — past the '
            'four-tile per-pixel budget, those frames are blank',
      );
    });

    testWidgets('the green confirm button commits the WARPED stamp, the '
        'same as Enter', (tester) async {
      // The button's visibility test is `_movePending`, which says nothing
      // about whether a transform box is open — so it IS offered mid-Ctrl+T.
      // Wired straight to `_confirmMoveSession` it landed the UNWARPED
      // lift: the artwork committed at its pre-transform position and size,
      // the warped preview kept painting on top of the wrong landing until
      // something closed the box, and the wrong landing went into history.
      // Enter has branched on `_transform != null` since R16-①; the button
      // never did, and a user reaching for the check mark instead of the
      // key silently lost their transform.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      // BR (70,70) → (95,95): 1.5× about the anchored TL (20,20).
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.pump();

      final button = find.byKey(
        const ValueKey<String>('selection-move-confirm'),
      );
      expect(
        button,
        findsOneWidget,
        reason:
            'the button is offered with the box open — that is the '
            'premise of this test, not an accident of it',
      );
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();

      // The same landing the corner-scale test asserts for Enter.
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
      expect(
        inkAt(env.coordinator, 30, 30),
        0,
        reason: 'the unwarped lift landed at its pre-transform position',
      );
      expect(
        env.commands.transformActive,
        isFalse,
        reason: 'confirm left the box open over an already-committed stamp',
      );
    });

    testWidgets('the confirm button still confirms an untouched box in one '
        'tap', (tester) async {
      // The guard on the fix. `_commitTransform` on an identity affine only
      // closes the box and leaves the session pending, so branching the way
      // Enter does would turn one tap of a button labelled "confirm" into
      // two.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      final undoBefore = env.history.undoCount;

      await tester.tap(
        find.byKey(const ValueKey<String>('selection-move-confirm')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      expect(env.commands.movePending, isFalse);
      // Two cleared booleans say the session ENDED, not that it was
      // confirmed — a revert clears them too, and on an IDENTITY box the
      // pixels cannot tell them apart either, because both leave the
      // artwork where it started. What distinguishes them is that a
      // confirm lands an entry and a revert does not.
      expect(
        env.history.undoCount,
        greaterThan(undoBefore),
        reason: 'the button reverted the session instead of confirming it',
      );
    });

    testWidgets('the frame a move CONFIRMS on still has the artwork on it', (
      tester,
    ) async {
      // The user's third symptom: "확정짓는 버튼 누르면 100%로 그림이
      // 아예 사라졌다가 다시생겨."
      //
      // `_confirmMoveSession` used to null the float in the same setState
      // that landed the stamp. The stamp's destination tiles are brand-new
      // objects with no decoded image, so the base painter's stale
      // fallback answered for them with the tiles the LIFT ERASED —
      // emptiness — and the float that had been covering them was already
      // gone. Measured, the selection vanished for two frames.
      //
      // The float is what should cover that, because it is not a stand-in:
      // by P3a's preview/commit byte-identity contract it holds exactly
      // these bytes at exactly this place.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(45, 45), const Offset(58, 49));
      await tester.pump();

      // Something on screen must be able to paint the moved artwork: the
      // float, or a committed surface whose tiles have decoded. Stated as
      // the OR because which one it is depends on decode timing, and the
      // defect is that on the confirm frame it was NEITHER.
      // ⚠️ "The float is UP" is NOT "the float PAINTS", and an earlier
      // version of this oracle only asked the first. Its tiles are new
      // objects, so they miss the identity-keyed image cache, and the
      // painter's per-pixel fallback covers four tiles a frame — so a
      // mutant that pinned an EMPTY surface, which is the user's symptom
      // verbatim, passed all 29 tests in this file. It asks the raster now.
      Future<bool> somethingCanPaintIt() async {
        final committed = env.coordinator.currentSurfaceOf(
          env.coordinator.activeFrameKey,
        );
        final floats = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .where((painter) => !identical(painter.surface, committed))
            .toList();
        // Sampled BEFORE any render: the render below runs through
        // runAsync, which lets the pending decodes land and would make
        // this frame read as ready when it was not.
        final committedReady = committed.tiles.values.every(
          (tile) => BitmapTileImageCache.instance.imageFor(tile) != null,
        );
        for (final painter in floats) {
          var own = 0;
          var missing = 0;
          await tester.runAsync(() async {
            final recorder = PictureRecorder();
            const size = Size(128, 128);
            painter.paint(Canvas(recorder, Offset.zero & size), size);
            final image = await recorder.endRecording().toImage(128, 128);
            final data = await image.toByteData(
              format: ImageByteFormat.rawRgba,
            );
            final painted = data!.buffer.asUint8List();
            for (var y = 0; y < 128; y += 1) {
              for (var x = 0; x < 128; x += 1) {
                final own32 = surfacePixelRgba(painter.surface, x, y) ?? 0;
                if (((own32 >> 24) & 0xff) == 0) continue;
                own += 1;
                if (painted[(y * 128 + x) * 4 + 3] == 0) missing += 1;
              }
            }
          });
          // `own > 0` rejects an empty pinned surface; `missing == 0`
          // rejects a float the four-tile budget cannot cover.
          if (own > 0 && missing == 0) return true;
        }
        return committedReady;
      }

      expect(
        await somethingCanPaintIt(),
        isTrue,
        reason: 'the float is not up during the session — bad premise',
      );

      env.commands.confirmPendingMove();
      await tester.pump();

      // THE frame the symptom is about.
      expect(
        await somethingCanPaintIt(),
        isTrue,
        reason:
            'the confirm frame has nothing that can paint the artwork — '
            'the float went before the committed tiles could take over',
      );
    });

    testWidgets('a freshly lifted float paints on its FIRST frame, not '
        'four tiles of it', (tester) async {
      // User report (08-04): "from the second transform on, when the
      // transform STARTS, the target intermittently disappears for about
      // a frame."
      //
      // What kept it on screen was never the float: it was the BASE
      // painter's stale borrow, still holding the pre-erase tiles. That
      // borrow dies the moment the erased tiles decode, and the float's
      // own tiles decode on their own schedule — so whether anything is
      // on screen in between is a race nothing in the code orders. The
      // float now borrows the tiles the lift took WHOLE, which are its
      // own pixels by construction, and paints immediately.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      // The cel has to be ON SCREEN before it is lifted — that is the
      // premise of the whole mechanism, and it is not free in a widget
      // test: `decodeImageFromPixels` never completes inside `pump`'s
      // fake-async zone, so without this the base has no decoded tiles to
      // hand over and the seeding has nothing to seed.
      await settle(tester);

      env.commands.beginTransform();
      await tester.pump();

      final committed = env.coordinator.currentSurfaceOf(
        env.coordinator.activeFrameKey,
      );
      final floats = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .where((painter) => !identical(painter.surface, committed))
          .toList();
      expect(floats, isNotEmpty, reason: 'no float is up — bad premise');

      var own = 0;
      var missing = 0;
      await tester.runAsync(() async {
        final recorder = PictureRecorder();
        const size = Size(800, 600);
        floats.first.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(800, 600);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final painted = data!.buffer.asUint8List();
        // Every second pixel on each axis: a tile the float cannot draw is
        // a 256 px square, and `surfacePixelRgba` is a tile lookup per
        // call — the exhaustive walk took minutes for no more evidence.
        for (var y = 0; y < 600; y += 2) {
          for (var x = 0; x < 800; x += 2) {
            final own32 = surfacePixelRgba(floats.first.surface, x, y) ?? 0;
            if (((own32 >> 24) & 0xff) == 0) continue;
            own += 1;
            if (painted[(y * 800 + x) * 4 + 3] == 0) missing += 1;
          }
        }
        image.dispose();
      });

      expect(own, greaterThan(0), reason: 'the float has no pixels at all');
      expect(
        missing,
        0,
        reason:
            'the float cannot draw $missing of its own $own pixels on the '
            'frame the lift opened',
      );
    });

    testWidgets('the frame a WARPED transform confirms on still has the '
        'artwork on it', (tester) async {
      // User report (08-04): "on confirming the transform the target
      // disappears for about a frame, almost 100% of the time."
      //
      // The move path above was covered; this one was not, and this is the
      // one the user hits. `_clearTransform` discarded the decoded
      // resample — the single image of exactly the bytes about to land —
      // and rebuilt the float from the warped stamp instead, which is
      // all-new tiles with no cache entries, so what replaced it could not
      // paint. Measured on the real panel: 0 of 107 sampled ink pixels on
      // the confirm frame.
      //
      // The oracle is the COMPOSITED panel, because the question is what
      // the user sees, not which object is mounted.
      //
      // ⚠️ The picture has to be BIGGER THAN FOUR TILES or the defect
      // cannot show: the painter's per-pixel fallback covers four tiles a
      // frame, so a landing that fits inside them is painted whatever
      // else is broken. Written first with the file's 30..60 fixture,
      // this test passed without the fix — that is the whole reason the
      // user sees this on big transforms and not on small ones.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );

      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 20,
        ty: 12,
        rotationDegrees: 0,
        scale: 1.5,
      );
      // The resample decodes asynchronously; the preview being up is what
      // says the image the confirm will keep actually exists yet.
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsOneWidget,
        reason: 'the warped preview never came up — bad premise',
      );

      env.commands.commitTransform();
      await tester.pump();
      final atConfirm = await screenInk(tester);

      await settle(tester);
      final settled = await screenInk(tester);

      expect(settled, greaterThan(0), reason: 'the landing has ink at all');
      expect(
        atConfirm,
        greaterThan((settled * 0.9).round()),
        reason:
            'the confirm frame is missing the artwork: on screen $atConfirm '
            'of the $settled it settles to',
      );
    });

    testWidgets('the held preview lets go once the base can paint, and does '
        'not keep painting over it', (tester) async {
      // Keeping a decoded image alive past the session is only safe if it
      // is also let go. A hold that outlived its release would paint one
      // transform state over every later edit for the rest of the session.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 20,
        ty: 12,
        rotationDegrees: 0,
        scale: 1.5,
      );
      await settle(tester);
      env.commands.commitTransform();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsOneWidget,
        reason: 'the confirm did not hold the picture it just landed',
      );

      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsNothing,
        reason: 'the hold released but the preview is still mounted',
      );
    });

    testWidgets('a WIDE move confirms with the picture on screen too — the '
        'other branch of the hold', (tester) async {
      // The move path holds a float SURFACE rather than a resample image,
      // and it is the path the 208,234-pixel double-composite was measured
      // on. Both branches are clipped to the tiles the base cannot paint
      // yet, so both need a landing wider than one decode round.
      //
      // This one is GREEN without the fix, deliberately: the move path
      // already worked, and what it guards is that clipping the hold to
      // the pending tiles does not take away pixels the base still cannot
      // paint. A clip that is too eager fails here and nowhere else.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      await dragOnLayer(tester, const Offset(300, 200), const Offset(340, 225));
      expect(env.commands.movePending, isTrue);

      env.commands.confirmPendingMove();
      await tester.pump();
      final atConfirm = await screenInk(tester);
      await settle(tester);
      final settled = await screenInk(tester);

      expect(settled, greaterThan(0));
      expect(
        atConfirm,
        greaterThan((settled * 0.9).round()),
        reason: 'on screen $atConfirm of the $settled it settles to',
      );
    });

    testWidgets('a resample the confirm overtook is NOT held — an absent '
        'picture beats a wrong one', (tester) async {
      // `_resampledFloatImage` is deliberately the last COMPLETED
      // resample, while the confirm recomputes synchronously when the warp
      // changed since. Holding it unconditionally would paint the earlier
      // transform state over the landing for the whole hold. The keep is
      // gated on the image being `identical`ly the dab that landed.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      env.commands.beginTransform();
      await tester.pump();

      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 1.4,
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsOneWidget,
        reason: 'the 1.4 preview decoded — bad premise otherwise',
      );

      // Change the warp and confirm WITHOUT letting the new decode land:
      // the image on hand is now the 1.4 picture, the landing is 2.4.
      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 2.4,
      );
      await tester.pump();
      env.commands.commitTransform();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsNothing,
        reason: 'a stale resample was held over the landing',
      );
    });

    testWidgets('Ctrl+Z over an open transform box folds it in rather than '
        'wedging the box', (tester) async {
      // The third caller with the button's old wiring, and the one that
      // hurt most: `home_page.dart` binds `confirmPendingMove` to
      // `HistoryManager.onBeforeUndoRedo`, which every undo runs
      // unconditionally. Bare, it landed the UNWARPED lift as a fresh
      // entry that the same Ctrl+Z then popped — the keypress consumed
      // itself — and left the box open with `_transform` still set and no
      // float, which wedges the next Ctrl+T against its own guard. Escape
      // was the only way out.
      final env = await pumpSelectionPanel(tester);
      env.history.onBeforeUndoRedo = env.commands.confirmPendingMove;
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.pump();

      env.history.undo();
      await tester.pump();

      expect(
        env.commands.transformActive,
        isFalse,
        reason: 'the box was left open with no float — Ctrl+T is now wedged',
      );
      // And the session can be reopened, which is what "wedged" cost.
      env.commands.beginTransform();
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
    });

    testWidgets('a corner drag scales anchored on the opposite corner: the '
        'pixels RESAMPLE into the scaled footprint', (tester) async {
      final env = await pumpSelectionPanel(tester);
      // Selection box (20,20)..(70,70): pivot (45,45), BR handle at (70,70).
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();

      // Drag BR to (95,95): 1.5× about the anchored TL corner (20,20).
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      env.commands.commitTransform();
      await tester.pump();

      // Dab centers map through q = 20 + 1.5·(p − 20):
      // (30,30)→(35,35), (45,45)→(57.5,57.5), (60,60)→(80,80).
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 57, 57), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
    });

    testWidgets('Alt scales about the center; Escape reverts a fresh '
        'Ctrl+T lift byte-exactly', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();

      // Alt+drag BR (70,70)→(95,95): 2× about the center (45,45).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      env.commands.commitTransform();
      await tester.pump();

      // q = 45 + 2·(p − 45): (30,30)→(15,15), (45,45) fixed, (60,60)→(75,75).
      expect(inkAt(env.coordinator, 15, 15), isNonZero);
      expect(inkAt(env.coordinator, 45, 45), isNonZero);
      expect(inkAt(env.coordinator, 75, 75), isNonZero);
      final afterFirst = currentSurface(env.coordinator);

      // A second session cancelled with Escape leaves no trace: the
      // fresh lift it opened reverts whole.
      env.commands.beginTransform();
      await tester.pump();
      await dragOnLayer(tester, const Offset(46, 46), const Offset(60, 60));
      env.commands.cancelTransform();
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      expect(
        identical(currentSurface(env.coordinator), afterFirst),
        isTrue,
        reason: 'Escape restores the pre-Ctrl+T surface by reference',
      );
    });

    testWidgets('R17-U 핸들 상시: with the MOVE tool a corner drag scales '
        'WITHOUT Ctrl+T — the grab itself opens the session', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      expect(env.commands.transformActive, isFalse);

      // Grab the BR corner handle of the ALWAYS-ON box and drag to
      // (95,95): 1.5× about the anchored TL corner.
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      expect(
        env.commands.transformActive,
        isTrue,
        reason: 'the handle grab promoted the implicit box into a session',
      );

      env.commands.commitTransform();
      await tester.pump();
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
    });

    testWidgets('numeric transform input (tool settings) applies through '
        'the selection channel', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);

      env.commands.setTransformValues(
        tx: 10,
        ty: 5,
        rotationDegrees: 0,
        scale: 1,
      );
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
      expect(env.commands.transformValues?.tx, 10);

      env.commands.commitTransform();
      await tester.pump();
      expect(inkAt(env.coordinator, 40, 35), isNonZero);
      expect(inkAt(env.coordinator, 28, 28), 0);
    });

    testWidgets('the rotate knob turns the selection about its center: '
        'only the shape\'s PIXELS rotate, unlifted content stays', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      // Lower box (20,40)..(70,90): dabs (45,45) and (60,60) lift; the
      // (30,30) dab's pixels sit above the region and stay in the base.
      await dragOnLayer(tester, const Offset(20, 40), const Offset(70, 90));
      expect(env.commands.hasSelection, isTrue);
      env.commands.beginTransform();
      await tester.pump();

      // Knob sits 28px above the top edge midpoint (45,40) → (45,12).
      // Sweep to angle 0° about the center (45,65): +90° rotation.
      await dragOnLayer(tester, const Offset(45, 12), const Offset(90, 65));
      env.commands.commitTransform();
      await tester.pump();

      // R90 about (45,65): (45,45)→(65,65), (60,60)→(50,80).
      expect(inkAt(env.coordinator, 65, 65), isNonZero);
      expect(inkAt(env.coordinator, 50, 80), isNonZero);
      expect(
        inkAt(env.coordinator, 30, 30),
        isNonZero,
        reason: 'the unlifted pixels never move',
      );
      expect(inkAt(env.coordinator, 45, 45), 0, reason: 'origin rotated away');
    });
  });

  testWidgets('the lasso tool selects with a freehand region', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.lasso);

    // A rough triangle around the stroke.
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(10, 10));
    await tester.pump();
    for (final point in const [
      Offset(90, 10),
      Offset(90, 90),
      Offset(10, 90),
    ]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(env.commands.hasSelection, isTrue);
    // The nudge lifts the lasso region's pixels into a pending session;
    // the confirm lands them moved (+2,0) — the raster is the record.
    env.commands.nudge(2, 0);
    await tester.pump();
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(inkAt(env.coordinator, 32, 30), isNonZero);
    expect(inkAt(env.coordinator, 28, 30), 0);
  });

  testWidgets('R26 #15: NO frame under the playhead still selects — the '
      'region is view state; only pixel ops need a cel', (tester) async {
    final commands = CanvasSelectionCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: HistoryManager(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.selectRect,
            ),
            selectionCommands: commands,
            // The production no-frame configuration: the blank-canvas
            // placeholder carries the viewport.
            contentOverride: (context, viewport) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(layerKey),
      findsOneWidget,
      reason: 'the layer used to refuse to mount without a coordinator',
    );

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(
      commands.hasSelection,
      isTrue,
      reason: '"어느 상황에서든 무조건" — the marquee works on empty ground',
    );
  });
}
