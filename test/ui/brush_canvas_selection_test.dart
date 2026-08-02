import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
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
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    // One committed stroke around canvas (30..60, 30..60).
    coordinator.commitSourceStroke(
      sourceDabs: [dab(30, 30), dab(45, 45), dab(60, 60)],
    );

    Future<void> pumpWith(CanvasTool tool) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(tool: tool),
              selectionCommands: commands,
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
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
