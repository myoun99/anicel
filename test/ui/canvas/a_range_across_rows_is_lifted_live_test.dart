import 'dart:async' show unawaited;
import 'dart:io' show Directory;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/playback/playback_scope.dart';
import 'package:anicel/src/services/selection_lift.dart'
    show debugSelectionLiftsBuilt;
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_press.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart'
    show playOrStop;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import '../../helpers/wait_window.dart' show watchTheBar, windowBehind;
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/surface_rgba_in_place.dart';
import '../../helpers/until_the_brushes_land.dart';

/// F-329 — A FRAME RANGE ACROSS ROWS IS LIFTED, EVERY ROW, WHILE THE BOX IS
/// OPEN.
///
/// 유저 2026-10-10: 「세로로 선택범위 작동해서 여러 행의 프레임 변형도구
/// 사용시, 확정하면 같이 적용되는거 잘 되있는데, 다른 레이어는 확정해야
/// 바껴서, 변형중에도 라이브로 선택된 다른행의 프레임도 변형중인거 보이도록」.
/// The confirm already carried the move to every cel of the range
/// (F-116-b); the rows past the one you stand on showed it only then. Each
/// row's cel at the playhead is lifted now as a folder's rows are (I-37):
/// its hole and its float in its own row while the box is open, inside the
/// one box around them all.
void main() {
  const a = LayerId('row-a');
  const b = LayerId('row-b');

  /// Two drawing rows, each with two cels.
  Project twoRows() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer drawn(LayerId id) => row.copyWith(
      id: id,
      frames: [
        for (var i = 0; i < 2; i += 1)
          Frame(id: FrameId('${id.value}-$i'), duration: 1, strokes: const []),
      ],
      timeline: {
        for (var i = 0; i < 2; i += 1)
          i: TimelineExposure.drawing(FrameId('${id.value}-$i'), length: 1),
      },
    );
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                drawn(a),
                drawn(b),
                for (final layer in cut.layers)
                  if (layer.id != row.id) layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// An opaque block over [left]..[right] × [top]..[bottom], in the first
  /// tile of a cel of [session]'s cut.
  BitmapSurface blockOn(
    EditorSessionManager session, {
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final cut = session.requireActiveCut;
    const size = defaultCelTileSize;
    final pixels = Uint8List(size * size * 4);
    for (var y = top; y < bottom; y += 1) {
      for (var x = left; x < right; x += 1) {
        final o = (y * size + x) * 4;
        pixels[o + 2] = 0x80;
        pixels[o + 3] = 0xFF;
      }
    }
    return BitmapSurface(
      canvasSize: cut.canvasSize,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: size, pixels: pixels)},
    );
  }

  /// Stood on A at frame 0, with a range over both rows' two frames — and
  /// the brushes as they ship in the library, with [brushes].
  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    bool brushes = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Real file IO only inside runAsync: a library on a missing file yields
    // the brushes as they ship.
    final directory = brushes
        ? (await tester.runAsync(
            () => Directory.systemTemp.createTemp('brushes'),
          ))!
        : null;
    if (directory != null) {
      deleteAfterSessionEnds(directory);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: twoRows(),
          presetFileService: directory == null
              ? null
              : BrushPresetFileService(
                  filePath: '${directory.path}/brush_presets.json',
                ),
          tipLibraryService: directory == null
              ? null
              : BrushTipLibraryService(
                  directoryPath: '${directory.path}/tips',
                ),
        ),
      ),
    );
    if (brushes) {
      await untilTheBrushesLand(tester);
    }
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final cut = session.requireActiveCut;
    final store = session.renderCaches.brushFrameStore;
    // A's ink at (20..60, 20..40), B's at (70..110, 70..90) — on both cels.
    for (final frame in ['0', '1']) {
      store.storeBakedSurface(
        session.brushFrameKeyForCut(cut, a, FrameId('${a.value}-$frame')),
        blockOn(session, left: 20, top: 20, right: 60, bottom: 40),
      );
      store.storeBakedSurface(
        session.brushFrameKeyForCut(cut, b, FrameId('${b.value}-$frame')),
        blockOn(session, left: 70, top: 70, right: 110, bottom: 90),
      );
    }
    session.selectLayer(a);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    session.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: a,
      layerIds: [a, b],
      startIndex: 0,
      endIndexExclusive: 2,
    );
    await tester.pumpAndSettle();
    return session;
  }

  bool inked(
    EditorSessionManager session,
    LayerId row,
    String cel,
    int x,
    int y,
  ) {
    final surface = session.pixelEditing.coordinator!.currentSurfaceOf(
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row,
        FrameId('${row.value}-$cel'),
      ),
    );
    return (surfaceRgbaInPlace(surface, x, y) ?? 0) != 0;
  }

  /// Ctrl+T, and the box opens on the picture.
  Future<CanvasSelectionCommands> openTheBox(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    return commands;
  }

  testWidgets('the other row shows lifted while the box is open, and the '
      'confirm moves every cel of the range — as one step of undo', (
    tester,
  ) async {
    final session = await pump(tester);
    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: '⛔fixture premise: both rows draw where the test reads',
    );

    final commands = await openTheBox(tester);
    expect(commands.transformActive, isTrue);
    final stack = tester.widget<FramePictureView>(
      find.byType(FramePictureView).first,
    );
    expect(
      {for (final key in stack.live!.liftedRows.keys) key.frameId.value},
      {'${b.value}-0'},
      reason: 'B shows lifted in its own row — at the playhead, the frame '
          'on screen; A floats in the live row, as a cel\'s own lift does',
    );
    expect(
      surfaceRgbaInPlace(stack.live!.liftedRows.values.single.surface, 75, 75) ?? 0,
      0,
      reason: 'B is drawn from its own cel with its hole while the box is '
          'open, not as it stood',
    );

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    final confirmed = await windowBehind(
      tester,
      () async => commands.applyTransform(),
    );
    expect(
      confirmed?.title,
      editorActionLabel(EditorActionIds.confirm),
      reason: '🗣️F-566: 「다른 블록에 걸쳐서 변형할때만 진행창뜸」 — four cels',
    );
    await tester.pumpAndSettle();

    for (final cel in ['0', '1']) {
      expect(
        (inked(session, a, cel, 25, 25), inked(session, a, cel, 75, 25)),
        (false, true),
        reason: 'A\'s cel $cel moved right by 20',
      );
      expect(
        (inked(session, b, cel, 75, 75), inked(session, b, cel, 125, 75)),
        (false, true),
        reason: 'B\'s cel $cel moved right by 20 with it, once',
      );
    }

    session.historyManager.undo();
    await tester.pumpAndSettle();

    for (final cel in ['0', '1']) {
      expect(
        (inked(session, a, cel, 25, 25), inked(session, b, cel, 75, 75)),
        (true, true),
        reason: 'one undo brings every cel back',
      );
    }
  });

  testWidgets('🗣️F-566: with the range let go, the cel you stand on is '
      'confirmed at once — 「변형도 셀 하나만 할때는 진행창안띄움」', (
    tester,
  ) async {
    final session = await pump(tester);
    session.frameRangeSelection.value = null;
    await tester.pumpAndSettle();
    final commands = await openTheBox(tester);

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    expect(
      await windowBehind(tester, () async => commands.applyTransform()),
      isNull,
    );
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, a, '0', 75, 25)),
      (false, true),
      reason: 'A\'s cel 0 moved right by 20',
    );
    expect(
      inked(session, b, '0', 75, 75),
      isTrue,
      reason: 'and nothing else did',
    );
  });

  testWidgets('the box stands around both rows\' pictures — a scale grows '
      'them from the middle of the two (I-37: 「실루엣은 전체를 기준으로」)', (
    tester,
  ) async {
    final session = await pump(tester);
    final commands = await openTheBox(tester);

    // Both together span x 20..110, so the box's middle is x 65, and twice
    // as wide A (20..60) spans -25..55. Around A's own middle (x 40) it
    // would span 0..80.
    commands.editTransformValues((now) => now.copyWith(sx: 2));
    await tester.pumpAndSettle();
    await windowBehind(tester, () async => commands.applyTransform());
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 50, 25), inked(session, a, '0', 70, 25)),
      (true, false),
      reason: 'A grew from the middle of both rows, not from its own',
    );
  });

  /// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second-Q1 (유저
  /// 2026-11-19, 「상자가 뜰 때 미리 들기」): the box at rest cuts the cels it
  /// frames ahead of the press that opens it, and that press cuts only a
  /// cel that changed since.
  group('🗣️a box at rest cuts its cels ahead', () {
    /// The turns and the engine's answers a run of the box at rest takes,
    /// one begun since [runs] were through: a cut a turn and its float
    /// another, the turns running on with no frame asked for, and each step
    /// told on the machine's own clock (brush's told doors, b7aba1ce1).
    Future<void> untilCutAhead(WidgetTester tester, int runs) async => expect(
      await settleAsync(tester, () => debugCutsAheadThrough > runs),
      isTrue,
      reason: '⛔premise: the box at rest cut every cel it frames',
    );

    /// Ctrl+T — the box at rest — and its cuts ([untilCutAhead]).
    Future<CanvasSelectionCommands> restTheBox(WidgetTester tester) async {
      final runs = debugCutsAheadThrough;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await untilCutAhead(tester, runs);
      return tester
          .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
          .selectionCommands!;
    }

    testWidgets('🎯the press that opens the box cuts nothing the box at rest '
        'cut — and lifts both cels', (tester) async {
      await pump(tester);
      final before = debugSelectionLiftsBuilt;
      final commands = await restTheBox(tester);
      expect(
        debugSelectionLiftsBuilt - before,
        2,
        reason: '⛔premise: the box at rest cut its two cels',
      );

      final cut = debugSelectionLiftsBuilt;
      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(debugSelectionLiftsBuilt, cut, reason: 'nothing cut again');
      final stack = tester.widget<FramePictureView>(
        find.byType(FramePictureView).first,
      );
      expect(
        {for (final key in stack.live!.liftedRows.keys) key.frameId.value},
        {'${b.value}-0'},
        reason: 'B lifted in its own row, A floats in the live row',
      );
    });

    /// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second ④
    /// (브러시/렌더링 2026-11-20, b7aba1ce1): what a box at rest cuts and
    /// lays ahead is asked of the engine and told — each step waited for
    /// the GPU on the UI's thread, and for all the GPU had queued with it.
    /// So the turns alone ask; what is told comes on the machine's clock.
    ///
    /// ⚠️Not counted by the UI thread's waits (`debugWaitsHere`): with the
    /// box at rest every frame of this test waits once, the run's or not
    /// (공통 2026-11-20 — not the doors', the screen's read-back's nor the
    /// ink bounds'), so the count says nothing of the doors.
    testWidgets('🎯a box at rest asks its cuts of the engine and is told — '
        'its turns wait for none of them', (tester) async {
      await pump(tester);
      final runs = debugCutsAheadThrough;
      final lifts = debugSelectionLiftsBuilt;
      final floats = debugFloatSurfacesMade;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      // The turns a run takes, on the pumped clock alone.
      for (var turn = 0; turn < 6; turn += 1) {
        await tester.pump(Duration.zero);
      }

      expect(
        debugSelectionLiftsBuilt - lifts,
        1,
        reason: '⛔LIVENESS: the first cel\'s lift asked',
      );
      expect(
        debugCutsAheadThrough,
        runs,
        reason: 'a cut answered on the pumped clock — waited for, not told',
      );

      await untilCutAhead(tester, runs);
      expect(
        (debugSelectionLiftsBuilt - lifts, debugFloatSurfacesMade - floats),
        (2, 2),
        reason: 'LIVENESS: both cels cut and laid ahead, once told',
      );
    });

    testWidgets('the press lays no float the box at rest laid', (tester) async {
      await pump(tester);
      final before = debugFloatSurfacesMade;
      final commands = await restTheBox(tester);
      expect(
        debugFloatSurfacesMade - before,
        2,
        reason: '⛔premise: the box at rest laid its two floats',
      );

      final laid = debugFloatSurfacesMade;
      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(debugFloatSurfacesMade, laid, reason: 'nothing laid again');
    });

    testWidgets('a wall moved since the floats were laid cuts and lays them '
        'again at the press', (tester) async {
      final session = await pump(tester);
      final commands = await restTheBox(tester);
      session.projectSettings.setPasteboardSize(PasteboardSize.two);
      await tester.pumpAndSettle();
      final cut = debugSelectionLiftsBuilt;
      final laid = debugFloatSurfacesMade;

      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(
        debugSelectionLiftsBuilt,
        cut + 2,
        reason:
            'a wall moved stores every cel anew — what lets a float laid '
            'ahead check its cut and no wall of its own',
      );
      expect(debugFloatSurfacesMade, laid + 2, reason: 'both, on the new wall');
    });

    testWidgets('a cel whose picture changed since it was cut is cut again at '
        'the press — and it alone', (tester) async {
      final session = await pump(tester);
      final commands = await restTheBox(tester);
      // B's block again, where it was: the same outline, a picture the cut
      // was not made from.
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(
          session.requireActiveCut,
          b,
          FrameId('${b.value}-0'),
        ),
        blockOn(session, left: 70, top: 70, right: 110, bottom: 90),
      );

      final cut = debugSelectionLiftsBuilt;
      final laid = debugFloatSurfacesMade;
      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(debugSelectionLiftsBuilt, cut + 1, reason: 'B, not A');
      expect(
        debugFloatSurfacesMade,
        laid + 1,
        reason: 'B\'s float of its new cut, not of the one before',
      );
    });

    testWidgets('a row posed since its cel was cut is cut again at the press '
        '— its picture the same, where it stands not', (tester) async {
      final session = await pump(tester);
      final size = session.requireActiveCut.canvasSize;
      final commands = await restTheBox(tester);
      // The marquee's ants run for ever: a few frames, and the turns.
      Future<void> frames() async {
        for (var i = 0; i < 3; i += 1) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var turn = 0; turn < 4; turn += 1) {
          await tester.pump(Duration.zero);
        }
      }

      // The whole canvas selected: the box stands on the marquee, so a pose
      // moves no edge of it and the box at rest is not told again.
      final runs = debugCutsAheadThrough;
      commands.setRegion(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(
            left: 0,
            top: 0,
            right: size.width.toDouble(),
            bottom: size.height.toDouble(),
          ),
        ),
      );
      await frames();
      await untilCutAhead(tester, runs);
      final before = debugSelectionLiftsBuilt;

      session.laneVerbs.updateLayerTransformTrack(
        b,
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>.empty().withKey(0, 90),
        ),
      );
      await frames();
      final cut = debugSelectionLiftsBuilt;
      expect(
        cut,
        before,
        reason: '⛔premise: the pose did not tell the box at rest again',
      );
      commands.beginTransform();
      await frames();

      expect(commands.transformActive, isTrue);
      expect(debugSelectionLiftsBuilt, cut + 1, reason: 'B, not A');
    });

    testWidgets('a mask set since the cels were cut cuts them again at the '
        'press', (tester) async {
      await pump(tester);
      final commands = await restTheBox(tester);
      tester
          .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel).first)
          .selectionMaskOptions!
          .value = const SelectionMaskOptions(
        growPx: 2,
      );
      await tester.pump();

      final cut = debugSelectionLiftsBuilt;
      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(debugSelectionLiftsBuilt, cut + 2, reason: 'both, grown');
    });

    testWidgets('a box told on a still screen still cuts — the run asks for '
        'the frame it waits on', (tester) async {
      final session = await pump(tester);
      await restTheBox(tester);
      final cut = debugSelectionLiftsBuilt;
      // The range let go of: the box frames A's cel alone, told in the one
      // frame that change asks for — and no frame after it but its own.
      session.frameRangeSelection.value = null;
      await tester.pump();
      for (var turn = 0; turn < 4; turn += 1) {
        await tester.pump(Duration.zero);
      }

      expect(debugSelectionLiftsBuilt, cut + 1, reason: 'A, cut again');
    });

    testWidgets('a float laid ahead, moved by halves, stands on whole pixels '
        '— where it lands, as one laid at the press does', (tester) async {
      await pump(tester);
      final commands = await restTheBox(tester);
      final laid = debugFloatSurfacesMade;
      commands.beginTransform();
      await tester.pumpAndSettle();
      expect(
        debugFloatSurfacesMade,
        laid,
        reason: '⛔premise: the floats were laid ahead',
      );

      commands.editTransformValues((now) => now.copyWith(tx: 40.5, ty: 25.5));
      await tester.pumpAndSettle();
      final live = tester
          .widget<FramePictureView>(find.byType(FramePictureView).first)
          .live!;
      final floats = [
        ?live.floatOverlay?.value,
        for (final lifted in live.liftedRows.values) ?lifted.float?.value,
      ];
      expect(floats, hasLength(2), reason: '⛔premise: both cels float');
      for (final float in floats) {
        final offset = (float.surfaceOffset.x, float.surfaceOffset.y);
        expect(
          offset,
          (offset.$1.roundToDouble(), offset.$2.roundToDouble()),
          reason: 'no pixel stands at a half',
        );
      }
    });

    testWidgets('a posed row cut ahead lands as its picture shows — its '
        'float laid on the canvas, not in the row\'s artwork', (tester) async {
      final session = await pump(tester);
      session.laneVerbs.updateLayerTransformTrack(
        b,
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>.empty().withKey(0, 90),
        ),
      );
      await tester.pump();
      final coordinator = session.pixelEditing.coordinator!;
      final key = session.brushFrameKeyForCut(
        session.requireActiveCut,
        b,
        FrameId('${b.value}-0'),
      );
      final before = bitmapSurfaceContentBounds(
        coordinator.currentSurfaceOf(key),
      )!;
      final commands = await restTheBox(tester);
      final cut = debugSelectionLiftsBuilt;
      final laid = debugFloatSurfacesMade;
      commands.beginTransform();
      await tester.pumpAndSettle();
      expect(
        (debugSelectionLiftsBuilt, debugFloatSurfacesMade),
        (cut, laid),
        reason: '⛔premise: the press lifted what the box at rest cut and laid',
      );

      commands.editTransformValues((now) => now.copyWith(tx: 10));
      await tester.pumpAndSettle();
      await windowBehind(tester, () async => commands.applyTransform());
      await tester.pumpAndSettle();
      final landed = bitmapSurfaceContentBounds(
        coordinator.currentSurfaceOf(key),
      )!;

      expect(landed, isNot(before), reason: '⛔CONTROL: the move landed');
      expect(
        (
          landed.rightExclusive - landed.left,
          landed.bottomExclusive - landed.top,
        ),
        (
          before.rightExclusive - before.left,
          before.bottomExclusive - before.top,
        ),
        reason: 'B\'s block as it stood, moved — not turned again',
      );
    });

    testWidgets('a memory warning takes back what the box at rest cut', (
      tester,
    ) async {
      final session = await pump(tester);
      final coordinator = session.pixelEditing.coordinator!;
      final commands = await restTheBox(tester);
      final key = session.brushFrameKeyForCut(
        session.requireActiveCut,
        b,
        FrameId('${b.value}-0'),
      );
      final standing = coordinator.currentSurfaceOf(key);

      coordinator.frameStore.respondToMemoryPressure();
      expect(
        coordinator.currentSurfaceOf(key),
        same(standing),
        reason: '⛔premise: the warning left the picture as it stood',
      );
      final cut = debugSelectionLiftsBuilt;
      commands.beginTransform();
      await tester.pumpAndSettle();

      expect(commands.transformActive, isTrue);
      expect(debugSelectionLiftsBuilt, cut + 2, reason: 'cut again, both');
    });

    testWidgets('a build that changed nothing under the box cuts nothing '
        'again', (tester) async {
      await pump(tester);
      await restTheBox(tester);
      final cut = debugSelectionLiftsBuilt;

      tester.element(find.byType(CanvasSelectionLayer).first).markNeedsBuild();
      await tester.pumpAndSettle();
      for (var turn = 0; turn < 4; turn += 1) {
        await tester.pump(Duration.zero);
      }

      expect(debugSelectionLiftsBuilt, cut);
    });

    testWidgets('the cuts go with the box at rest — another tool lets them '
        'go', (tester) async {
      final session = await pump(tester);
      final store = session.pixelEditing.coordinator!.frameStore;
      final views = store.reclaimableViewCount;
      await restTheBox(tester);
      expect(
        store.reclaimableViewCount,
        views + 1,
        reason: 'the cuts, held as a view the store may reclaim',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();

      expect(store.reclaimableViewCount, views);
    });
  });

  /// 🗣️F-615-Q1 asked what a press starting a new outline does to a range
  /// moved in the box — and with the box open there is no such press: the
  /// box takes every press on the canvas, inside it or out. A new outline
  /// is drawn once something has taken the box away, and what takes it
  /// lands the range first (F-615-Q2).
  testWidgets('🗣️F-615-Q1: with the box open over a range, a press on the '
      'canvas is the box\'s — it lands nothing', (tester) async {
    final session = await pump(tester);
    final commands = await openTheBox(tester);
    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();

    final window = await windowBehind(tester, () async {
      final press = await tester.startGesture(
        tester.getTopLeft(find.byType(CanvasSelectionLayer).first) +
            const Offset(8, 8),
        kind: PointerDeviceKind.mouse,
      );
      await press.moveBy(const Offset(0, 40));
      await press.up();
    });
    expect(window, isNull);
    await tester.pumpAndSettle();
    expect(commands.transformActive, isTrue);
    expect(
      (inked(session, b, '1', 75, 75), inked(session, b, '1', 125, 75)),
      (true, false),
      reason: 'B\'s other cel stands as it was: nothing landed',
    );
  });

  /// 🗣️F-615-Q2 (유저 2026-11-19, 「착지하고 나서 바꾼다」): what takes the
  /// box away — another tool, a run, another tab — lands the range first,
  /// behind 확정's window, and comes once the window is down.
  group('🗣️F-615-Q2: a switch lands the range before it switches', () {
    /// The box opened over the range and moved right by 20, not confirmed.
    Future<CanvasSelectionCommands> moveTheBox(WidgetTester tester) async {
      final commands = await openTheBox(tester);
      commands.editTransformValues((now) => now.copyWith(tx: 20));
      await tester.pumpAndSettle();
      return commands;
    }

    void expectEveryCelMoved(EditorSessionManager session) {
      for (final cel in ['0', '1']) {
        expect(
          (inked(session, a, cel, 25, 25), inked(session, a, cel, 75, 25)),
          (false, true),
          reason: 'A\'s cel $cel moved right by 20',
        );
        expect(
          (inked(session, b, cel, 75, 75), inked(session, b, cel, 125, 75)),
          (false, true),
          reason: 'B\'s cel $cel moved right by 20 with it',
        );
      }
    }

    testWidgets('the brush\'s key: the window first, and the brush once it '
        'is down', (tester) async {
      final session = await pump(tester);
      await moveTheBox(tester);
      final tools = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .brushTool!;
      final before = tools.value.tool;
      expect(before, isNot(CanvasTool.brush), reason: '⛔premise');

      final inHand = <CanvasTool>[];
      watchTheBar(tester, onShare: (_) => inHand.add(tools.value.tool));
      final window = await windowBehind(
        tester,
        () => tester.sendKeyEvent(LogicalKeyboardKey.keyB),
      );
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(inHand, isNotEmpty);
      expect(
        inHand,
        everyElement(before),
        reason: 'the tool stays while the window stands',
      );
      await tester.pumpAndSettle();
      expect(tools.value.tool, CanvasTool.brush);
      expectEveryCelMoved(session);
    });

    testWidgets('a run: the window first, and the run once it is down', (
      tester,
    ) async {
      final session = await pump(tester);
      await moveTheBox(tester);
      final playback = session.playbackRig.playback;

      final running = <bool>[];
      watchTheBar(tester, onShare: (_) => running.add(playback.isActive));
      final window = await windowBehind(
        tester,
        () async => playOrStop(playback, scope: PlaybackScope.activeCut),
      );
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(running, isNotEmpty);
      expect(
        running,
        everyElement(isFalse),
        reason: 'nothing plays while the window stands',
      );
      expect(playback.isActive, isTrue);
      playback.stop();
      await tester.pumpAndSettle();
      expectEveryCelMoved(session);
    });

    /// The window takes the pointers that were down under it (the
    /// navigator cancels them), so a held button's hold ends with it: the
    /// press landed the range and held nothing — and picked nothing
    /// (🗣️F-615-Q1, 「누름은 착지만」): the right button is the eyedropper's
    /// out of the box.
    testWidgets('a held button\'s tool: the window first — and the window '
        'takes the pointer, so the tool in hand stays and picks nothing', (
      tester,
    ) async {
      final session = await pump(tester);
      await moveTheBox(tester);
      final tools = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .brushTool!;
      final before = tools.value.tool;
      final colour = tools.value.color;

      final inHand = <CanvasTool>[];
      watchTheBar(tester, onShare: (_) => inHand.add(tools.value.tool));
      late TestGesture right;
      final window = await windowBehind(tester, () async {
        right = await tester.startGesture(
          tester.getTopLeft(find.byType(CanvasSelectionLayer).first) +
              const Offset(8, 8),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
      });
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(inHand, isNotEmpty);
      expect(inHand, everyElement(before));
      await tester.pumpAndSettle();
      expect(tools.value.tool, before);

      await right.up();
      await tester.pumpAndSettle();
      expect(tools.value.tool, before);
      expect(
        tools.value.color,
        colour,
        reason: 'the press landed the range and no more: no pick',
      );
      expectEveryCelMoved(session);
    });

    testWidgets('a brush group\'s press: the window first, and its tool once '
        'it is down', (tester) async {
      final session = await pump(tester);
      await moveTheBox(tester);
      final workspace = tester.widget<EditorWorkspace>(
        find.byType(EditorWorkspace),
      );
      final tools = workspace.brushTool!;
      final before = tools.value.tool;

      final inHand = <CanvasTool>[];
      watchTheBar(tester, onShare: (_) => inHand.add(tools.value.tool));
      final window = await windowBehind(
        tester,
        () async => workspace.brushKeys!.press(
          const BrushGroupPress(CanvasTool.eraser, BrushGroupId('none')),
        ),
      );
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(inHand, isNotEmpty);
      expect(inHand, everyElement(before));
      await tester.pumpAndSettle();
      expect(tools.value.tool, CanvasTool.eraser);
      expectEveryCelMoved(session);
    });

    testWidgets('a brush\'s press: the window first, and the brush in hand '
        'once it is down', (tester) async {
      final session = await pump(tester, brushes: true);
      final shipped = tester
          .widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first)
          .presets
          .last;
      await moveTheBox(tester);
      final workspace = tester.widget<EditorWorkspace>(
        find.byType(EditorWorkspace),
      );
      final tools = workspace.brushTool!;
      final before = tools.value.tool;

      final inHand = <CanvasTool>[];
      watchTheBar(tester, onShare: (_) => inHand.add(tools.value.tool));
      final window = await windowBehind(
        tester,
        () async => workspace.brushKeys!.press(
          BrushPresetPress(
            CanvasTool.brush,
            shipped.id,
            group: shipped.groupId,
          ),
        ),
      );
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(inHand, isNotEmpty);
      expect(inHand, everyElement(before));
      await tester.pumpAndSettle();
      expect((tools.value.tool, tools.value.presetId), (
        CanvasTool.brush,
        shipped.id,
      ));
      expectEveryCelMoved(session);
    });

    testWidgets('another tab: the window first, and the tab once it is '
        'down', (tester) async {
      final session = await pump(tester);
      final projects = tester
          .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
          .projects;
      final other = projects.open(createDefaultProject());
      await tester.pumpAndSettle();
      await projects.activate(session);
      await tester.pumpAndSettle();
      await moveTheBox(tester);

      final shown = <bool>[];
      watchTheBar(
        tester,
        onShare: (_) => shown.add(identical(projects.active, session)),
      );
      final window = await windowBehind(
        tester,
        () async => unawaited(projects.activate(other)),
      );
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      expect(shown, isNotEmpty);
      expect(
        shown,
        everyElement(isTrue),
        reason: 'the tab stays while the window stands',
      );
      expect(identical(projects.active, other), isTrue);

      await projects.activate(session);
      await tester.pumpAndSettle();
      expectEveryCelMoved(session);
    });

    testWidgets('its tab\'s close: the window first, and the question once '
        'it is down — about the project with the range landed', (
      tester,
    ) async {
      final session = await pump(tester);
      final projects = tester
          .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
          .projects;
      projects.open(createDefaultProject());
      await tester.pumpAndSettle();
      await projects.activate(session);
      await tester.pumpAndSettle();
      await moveTheBox(tester);
      final close = find.byKey(const ValueKey<String>('project-tab-close-0'));
      expect(close, findsOneWidget, reason: '⛔premise: its tab is first');

      final window = await windowBehind(tester, () => tester.tap(close));
      expect(window?.title, editorActionLabel(EditorActionIds.confirm));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('system-exit-dialog')),
        findsOneWidget,
        reason: 'the landed range is work the close asks about',
      );
      expectEveryCelMoved(session);

      await tester.tap(
        find.byKey(const ValueKey<String>('system-exit-cancel')),
      );
      await tester.pumpAndSettle();
      expect(projects.sessions, contains(session));
    });
  });
}
