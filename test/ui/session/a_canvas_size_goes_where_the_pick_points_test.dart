import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-624 (유저 2026-11-19): 「여러 컷블록 같이 선택하고 캔버스 크기 변경시
/// 일괄변경가능하게」 — the canvas size goes to the cuts a storyboard range
/// covers, or to the active cut when no range is up, through ONE verb and
/// as ONE undo step (절대명령 2: a selection does not split the law), each
/// picture placed as the anchor says from its own cut's size.
void main() {
  const small = CanvasSize(width: 400, height: 300);
  const wide = CanvasSize(width: 600, height: 300);
  const to = CanvasSize(width: 800, height: 600);

  EditorSessionManager session() {
    Cut cut(String id, int sequence, CanvasSize size) => createDefaultCut(
      cutId: CutId(id),
      name: id,
      layerId: defaultLayerIdForSequence(sequence),
      canvasSize: size,
    );
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('canvas-project'),
        name: 'Canvases',
        createdAt: DateTime.utc(2026, 11, 19),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V',
            cuts: [
              cut('cut-1', 1, small),
              cut('cut-2', 2, small),
              cut('cut-3', 3, wide),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  CanvasSize sizeOf(EditorSessionManager s, String id) =>
      s.cutById(CutId(id))!.canvasSize;

  /// A picture drawn on [cutId] — what a resize moves.
  BrushFrameKey draw(EditorSessionManager s, CutId cutId) {
    final key = BrushFrameKey(
      projectId: const ProjectId('canvas-project'),
      trackId: const TrackId('track'),
      cutId: cutId,
      layerId: const LayerId('l'),
      frameId: const FrameId('drawn'),
    );
    s.renderCaches.brushFrameStore.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: s.cutById(cutId)!.canvasSize,
        tileSize: defaultCelTileSize,
      ).putTiles([
        (
          coord: TileCoord(x: 1, y: 1),
          tile: BitmapTile(
            size: defaultCelTileSize,
            pixels: Uint8List(BitmapTile.bytesFor(defaultCelTileSize))
              ..fillRange(0, BitmapTile.bytesFor(defaultCelTileSize), 9),
          ),
        ),
      ]),
    );
    return key;
  }

  void rangeOverTheLastTwo(EditorSessionManager s) {
    final axis = s.trackFrameAxis();
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: axis.entryFor(const CutId('cut-2'))!.startFrame,
      headGlobalFrame: axis.entryFor(const CutId('cut-3'))!.startFrame,
    );
    expect(s.cutVerbs.addressedCutIds, const [
      CutId('cut-2'),
      CutId('cut-3'),
    ], reason: '⛔premise');
  }

  test('with no range up, the size goes to the ACTIVE cut', () {
    final s = session();
    final active = s.activeCutId!;
    expect(s.cutVerbs.addressedCutIds, [active], reason: '⛔premise');

    s.cutVerbs.resizeActiveCutCanvas(to);

    expect(s.cutById(active)!.canvasSize, to);
    expect(sizeOf(s, 'cut-3'), wide);
  });

  test('🚨with a range up, the size goes to EVERY cut it covers — the active '
      'one left out when the range does not reach it — as one undo step', () {
    final s = session();
    final active = s.activeCutId!;
    rangeOverTheLastTwo(s);

    s.cutVerbs.resizeActiveCutCanvas(to);

    expect(sizeOf(s, 'cut-2'), to);
    expect(sizeOf(s, 'cut-3'), to);
    expect(
      s.cutById(active)!.canvasSize,
      small,
      reason: 'the active cut is outside the range',
    );

    s.undo();
    expect(sizeOf(s, 'cut-2'), small);
    expect(sizeOf(s, 'cut-3'), wide);
  });

  test('a canvas adjusted on the canvas lands on every cut the range covers '
      '(I-79), as one undo step', () {
    final s = session();
    rangeOverTheLastTwo(s);

    s.cutVerbs.placeActiveCutCanvas(to, contentOffset: (dx: 10, dy: 20));

    expect(sizeOf(s, 'cut-2'), to);
    expect(sizeOf(s, 'cut-3'), to);
    s.undo();
    expect(sizeOf(s, 'cut-2'), small);
    expect(sizeOf(s, 'cut-3'), wide);
  });

  test('the window opens on the first cut the pick points at, as 컷 설정 '
      'does', () {
    final s = session();
    expect(s.cutVerbs.addressedCut?.id, s.activeCutId, reason: 'no range');
    rangeOverTheLastTwo(s);

    expect(s.cutVerbs.addressedCut?.id, const CutId('cut-2'));
  });

  test('🚨what is worked out ahead is every addressed cut\'s — each by the '
      'move its own size asks, and each taken by the step — its report '
      'running once from nothing to all of them', () async {
    final s = session();
    rangeOverTheLastTwo(s);
    final drawn = [for (final id in ['cut-2', 'cut-3']) draw(s, CutId(id))];
    final heard = <double>[];

    await s.cutVerbs.resizeActiveCutCanvasAhead(
      to,
      anchor: CanvasResizeAnchor.center,
      report: heard.add,
    );

    final store = s.renderCaches.brushFrameStore;
    for (final cel in drawn) {
      expect(store.movedAheadOf(cel), isNotNull, reason: '$cel');
    }
    expect(heard, [0.5, 1.0], reason: 'a cut of two, then both');

    final movedHere = store.celsMovedHere;
    s.cutVerbs.resizeActiveCutCanvas(to, anchor: CanvasResizeAnchor.center);
    expect(sizeOf(s, 'cut-3'), to, reason: '⛔premise: the step was taken');
    expect(store.celsMovedHere, movedHere, reason: 'moved ahead, not here');
  });
}
