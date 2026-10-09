import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// I-37 — A FOLDER IS LIFTED WHOLE.
///
/// 유저 2026-10-02: 「폴더 전체를 하나로 들도록」, after asking on 09-16 for
/// 「폴더에 대한 변형도구 사용가능하게. 폴더 내부 전체 적용. 변형도구 실루엣은
/// 전체를 기준으로」. Stood on a folder, Ctrl+T opens ONE box around every
/// drawing row inside it; each row's cel shows its hole and its own float in
/// its own place in the composite while the box is open; the confirm moves
/// every one of them by the same transform, as one step of undo.
void main() {
  const folder = LayerId('lifted-folder');
  const a = LayerId('row-a');
  const b = LayerId('row-b');

  /// Two drawing rows inside [folder], each with two cels.
  Project folderProject() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer member(LayerId id) => row.copyWith(
      id: id,
      folderId: folder,
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
                member(a),
                member(b),
                createFolderLayer(id: folder, name: 'F'),
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

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: folderProject())),
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
    // The canvas edits a drawing row first, as a user arrives at a folder.
    session.selectLayer(a);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    session.selectLayer(folder);
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

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('stood on a folder, one box moves every drawing row inside it '
      '— as one step of undo', (tester) async {
    final session = await pump(tester);
    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: '⛔fixture premise: both rows draw where the test reads',
    );

    // Ctrl+T arms the transform tool; the box opens on the picture.
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    expect(
      commands.transformActive,
      isTrue,
      reason: 'a box opens on a folder',
    );
    final stack = tester.widget<CanvasLayerStackView>(
      find.byType(CanvasLayerStackView).first,
    );
    expect(
      {for (final key in stack.liftedRows.keys) key.frameId.value},
      {'${a.value}-0', '${b.value}-0'},
      reason: 'while the box is open, each row shows lifted in its own '
          'place in the composite',
    );
    // Each shows ITS OWN cel with its own hole: lifted whole, nothing of
    // either picture is left in either row.
    for (final MapEntry(:key, value: lifted) in stack.liftedRows.entries) {
      expect(
        (
          surfacePixelRgba(lifted.surface, 25, 25) ?? 0,
          surfacePixelRgba(lifted.surface, 75, 75) ?? 0,
        ),
        (0, 0),
        reason: '${key.frameId.value} is drawn from its own cel, holed',
      );
    }

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    commands.applyTransform();
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, a, '0', 75, 25)),
      (false, true),
      reason: 'A moved right by 20',
    );
    expect(
      (inked(session, b, '0', 75, 75), inked(session, b, '0', 125, 75)),
      (false, true),
      reason: 'B moved right by 20 with it',
    );
    expect(
      (inked(session, a, '1', 25, 25), inked(session, b, '1', 75, 75)),
      (true, true),
      reason: 'the other frame was not in it',
    );

    session.historyManager.undo();
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: 'one undo brings both rows back',
    );
  });

  testWidgets('a frame RANGE over the folder carries every row\'s cels '
      'across it by the same move (I-37-Q1 「변형만」 reaches in)', (
    tester,
  ) async {
    final session = await pump(tester);
    session.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: folder,
      startIndex: 0,
      endIndexExclusive: 2,
    );
    await tester.pumpAndSettle();

    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
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
        reason: 'B\'s cel $cel moved right by 20',
      );
    }
  });
}
