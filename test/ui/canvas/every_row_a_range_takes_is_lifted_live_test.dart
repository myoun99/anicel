import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

/// 🗣️F-564 (유저 2026-11-04): 「다른 행 블록끼리 선택하고 변형도구
/// 사용할때, 일반행끼리는 라이브로도 상자가 두 그림 선택되서 되는데, 어태치
/// 싱크행끼리라던가는 두 행 블록 선택하고 변형할때 라이브로 안보임. 확정해야
/// 다른 행도 바뀜. … 다른각도에서도 점검하면서. 그리고 이건 일반행도
/// 마찬가지인데 변형중 다른행 블록 선택하면 바로 그게 라이브로 반영되게」.
///
/// Every cel a range takes lands at the confirm (F-116-b) and shows lifted
/// while the box is open (F-329) — whatever kind of row holds it, and
/// whether the range was taken before the box opened or while it was open.
void main() {
  const a = LayerId('row-a');
  const b = LayerId('row-b');
  const base = LayerId('base');
  const synced = LayerId('synced');
  const free = LayerId('free');
  const folder = LayerId('folder');
  const inner = LayerId('inner');
  const innerSynced = LayerId('inner-synced');

  /// Where each row's ink starts: a column 20 wide of its own, y 20..40.
  final lefts = {
    a: 10,
    b: 40,
    base: 70,
    synced: 100,
    free: 130,
    inner: 160,
    innerSynced: 190,
  };

  FrameId cel(LayerId row, int at) => FrameId('${row.value}-$at');

  /// Two cels on every drawing row; the synced rows mirror their base's.
  Project rows() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer drawn(
      LayerId id, {
      LayerId? inFolder,
      LayerId? on,
      AttachedMode mode = AttachedMode.free,
    }) {
      final mirrors = on != null && mode == AttachedMode.synced;
      return row.copyWith(
        id: id,
        name: id.value,
        folderId: inFolder,
        attachedToLayerId: on,
        attachedMode: mode,
        frames: [
          for (var at = 0; at < 2; at += 1)
            Frame(id: cel(id, at), duration: 1, strokes: const []),
        ],
        timeline: mirrors
            ? const {}
            : {
                for (var at = 0; at < 2; at += 1)
                  at: TimelineExposure.drawing(cel(id, at), length: 1),
              },
        baseFrameLinks: mirrors
            ? {for (var at = 0; at < 2; at += 1) cel(on, at): cel(id, at)}
            : const {},
      );
    }

    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                drawn(a),
                drawn(b),
                drawn(base),
                drawn(synced, on: base, mode: AttachedMode.synced),
                drawn(free, on: base),
                drawn(inner, inFolder: folder),
                drawn(
                  innerSynced,
                  inFolder: folder,
                  on: inner,
                  mode: AttachedMode.synced,
                ),
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

  BitmapSurface columnOn(EditorSessionManager session, int left) {
    final cut = session.requireActiveCut;
    const size = defaultCelTileSize;
    final pixels = Uint8List(size * size * 4);
    for (var y = 20; y < 40; y += 1) {
      for (var x = left; x < left + 20; x += 1) {
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

  /// ⛔Not `pumpAndSettle`: the marching ants of an open box never settle.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Stood on [standing] at frame 0, every row inked on both cels.
  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    LayerId standing = a,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: rows())));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final cut = session.requireActiveCut;
    final store = session.renderCaches.brushFrameStore;
    for (final MapEntry(key: row, value: left) in lefts.entries) {
      for (var at = 0; at < 2; at += 1) {
        store.storeBakedSurface(
          session.brushFrameKeyForCut(cut, row, cel(row, at)),
          columnOn(session, left),
        );
      }
    }
    session.selectLayer(standing);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    return session;
  }

  void take(EditorSessionManager session, List<LayerId> range) =>
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: range.first,
        layerIds: range,
        startIndex: 0,
        endIndexExclusive: 2,
      );

  /// Ctrl+T, and the box opens on the picture.
  Future<CanvasSelectionCommands> openTheBox(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await pumpFrames(tester);
    expect(commands.transformActive, isTrue, reason: '⛔전제: the box is open');
    return commands;
  }

  Map<BrushFrameKey, LiftedCel> lifted(WidgetTester tester) => tester
      .widget<FramePictureView>(find.byType(FramePictureView).first)
      .live!
      .liftedRows;

  Set<String> liftedCels(WidgetTester tester) => {
    for (final key in lifted(tester).keys) key.frameId.value,
  };

  /// Where [row]'s lifted float is drawn from, on the canvas.
  double? floatLeft(WidgetTester tester, LayerId row) {
    for (final MapEntry(:key, :value) in lifted(tester).entries) {
      if (key.layerId == row) {
        return value.float?.value?.drawnWorldRect.left;
      }
    }
    return null;
  }

  /// The row a range takes beside the one stood on, and the cels of it the
  /// box lifts at frame 0.
  final others = <String, (LayerId, Map<LayerId, String>)>{
    'a plain row': (b, {b: 'row-b-0'}),
    'a synced attach row': (synced, {synced: 'synced-0'}),
    'a free attach row': (free, {free: 'free-0'}),
    'a folder': (folder, {inner: 'inner-0', innerSynced: 'inner-synced-0'}),
  };

  for (final MapEntry(key: kind, value: (other, cels)) in others.entries) {
    testWidgets('$kind, taken BEFORE the box opens, shows lifted', (
      tester,
    ) async {
      final session = await pump(tester);
      take(session, [a, other]);
      await pumpFrames(tester);

      await openTheBox(tester);

      expect(liftedCels(tester), cels.values.toSet());
    });

    testWidgets('$kind, taken WHILE the box is open, shows lifted — carried '
        'by the move the box already holds', (tester) async {
      final session = await pump(tester);
      final commands = await openTheBox(tester);
      commands.editTransformValues((now) => now.copyWith(tx: 20));
      await pumpFrames(tester);
      expect(liftedCels(tester), isEmpty, reason: '⛔전제: A alone is lifted');

      take(session, [a, other]);
      await pumpFrames(tester);

      expect(liftedCels(tester), cels.values.toSet());
      for (final row in cels.keys) {
        // The float is drawn from its cel's first tile, which starts at 0.
        expect(
          floatLeft(tester, row),
          closeTo(20, 1),
          reason: '${row.value} floats where the box\'s move puts it',
        );
      }
    });
  }

  testWidgets('stood on a synced attach row, it is the live row and the '
      'plain row the range takes shows lifted beside it', (tester) async {
    final session = await pump(tester, standing: synced);
    take(session, [synced, b]);
    await pumpFrames(tester);

    await openTheBox(tester);

    expect(liftedCels(tester), {'row-b-0'});
    expect(
      session.pixelEditing.coordinator!.activeFrameKey.frameId,
      cel(synced, 0),
      reason: 'the canvas edits the synced row\'s own cel',
    );
  });
}
