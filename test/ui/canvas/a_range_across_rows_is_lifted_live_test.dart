import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

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

  /// Stood on A at frame 0, with a range over both rows' two frames.
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: twoRows())),
    );
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
    return (surfacePixelRgba(surface, x, y) ?? 0) != 0;
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
    final stack = tester.widget<CanvasLayerStackView>(
      find.byType(CanvasLayerStackView).first,
    );
    expect(
      {for (final key in stack.liftedRows.keys) key.frameId.value},
      {'${b.value}-0'},
      reason: 'B shows lifted in its own row — at the playhead, the frame '
          'on screen; A floats in the live row, as a cel\'s own lift does',
    );
    expect(
      surfacePixelRgba(stack.liftedRows.values.single.surface, 75, 75) ?? 0,
      0,
      reason: 'B is drawn from its own cel with its hole while the box is '
          'open, not as it stood',
    );

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    commands.applyTransform();
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
    commands.applyTransform();
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 50, 25), inked(session, a, '0', 70, 25)),
      (true, false),
      reason: 'A grew from the middle of both rows, not from its own',
    );
  });
}
