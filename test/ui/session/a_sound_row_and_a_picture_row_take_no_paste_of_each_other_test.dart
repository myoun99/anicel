import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';

/// 🗣️F-609 (유저 2026-11-17): 「s행에 일반 레이어에서 프레임 복사한거
/// 붙여넣기 가능해서 그림 붙여넣어져버리는데 일반레이어에서 복사된건
/// 결과적으로 안붙여넣어지도록. 다른거랑 똑같이 붙여넣어지는 대상에서
/// 판단되서 알아서 무시하는느낌. 규칙맞춰서」.
///
/// The row a paste lands on asks what the copy was made off — a sound's on a
/// sound's row, a picture's on a picture's, never across, as the effects
/// keep it (`EffectKind.isTakenByARow`). A row that does not take it keeps
/// its seat and lands nothing; the press goes dark where no row takes it.
///
/// The collaborator the paste lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
FrameClipboard clipboardOf(EditorSessionManager session) => session.clipboard;

void main() {
  const plain = LayerId('plain');
  const other = LayerId('other');
  const sound = LayerId('sound');
  const voice = LayerId('voice');

  FrameId cel(LayerId row, int index) => FrameId('${row.value}-$index');

  /// [blocks] blocks two frames long from frame 0.
  Layer row(
    LayerId id, {
    LayerKind kind = LayerKind.animation,
    int blocks = 2,
  }) => Layer(
    id: id,
    name: id.value,
    kind: kind,
    frames: [
      for (var at = 0; at < blocks; at += 1)
        Frame(id: cel(id, at), duration: 2, strokes: const []),
    ],
    timeline: {
      for (var at = 0; at < blocks; at += 1)
        at * 2: TimelineExposure.drawing(cel(id, at), length: 2),
    },
  );

  /// Paints [red] over the first tile of [row]'s cel [id].
  void paint(EditorSessionManager s, LayerId row, FrameId id, int red) {
    final cut = s.requireActiveCut;
    final bytes = Uint8List(256 * 256 * 4);
    for (var pixel = 0; pixel < 256 * 256; pixel += 1) {
      bytes.setRange(pixel * 4, pixel * 4 + 4, [red, 0, 0, 255]);
    }
    s.pixelEditing.coordinator!.restoreSurfaceSnapshot(
      s.brushFrameKeyForCut(cut, row, id),
      BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: 256,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(size: 256, pixels: bytes),
        },
      ),
    );
  }

  /// [plain] painted red 10 and 20, [other] beside it, and two SE rows —
  /// [sound] with a block at 0 and 2, [voice] with none.
  EditorSessionManager rig() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sound-and-picture'),
        name: 'Sound and picture',
        createdAt: DateTime.utc(2026, 11, 18),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('cut-1'),
                name: '1',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [row(plain), row(other, blocks: 0)],
              ),
            ],
            seLayers: [
              row(sound, kind: LayerKind.se),
              row(voice, kind: LayerKind.se, blocks: 0),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    s.pixelEditing.coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(cut, plain, cel(plain, 0)),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: cut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    paint(s, plain, cel(plain, 0), 10);
    paint(s, plain, cel(plain, 1), 20);
    return s;
  }

  /// [id] as it stands now — a cut's row or the track's.
  Layer now(EditorSessionManager s, LayerId id) => [
    ...s.requireActiveCut.layers,
    ...s.activeTrack.seLayers,
  ].firstWhere((layer) => layer.id == id);

  /// The cel each block of [id] starts on, by its frame.
  Map<int, FrameId?> blocks(EditorSessionManager s, LayerId id) => {
    for (final MapEntry(key: at, value: exposure)
        in now(s, id).timeline.entries)
      at: exposure.frameId,
  };

  int redOf(EditorSessionManager s, LayerId row, FrameId? id) {
    if (id == null) {
      return -1;
    }
    final tile = s.pixelEditing.coordinator!
        .currentSurfaceOf(s.brushFrameKeyForCut(s.requireActiveCut, row, id))
        .tileAt(TileCoord(x: 0, y: 0));
    return tile == null ? 0 : tile.readPixels((_, view) => view[0]);
  }

  void stand(EditorSessionManager s, LayerId id, int at) {
    s.clearFrameRangeSelection();
    s.selectLayer(id);
    s.selectFrameIndex(at);
  }

  void sweep(
    EditorSessionManager s,
    List<LayerId> rows, {
    required int from,
    required int to,
  }) {
    s.selectLayer(rows.first);
    s.selectFrameIndex(from);
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: rows.first,
      startIndex: from,
      endIndexExclusive: to,
      layerIds: rows,
    );
  }

  test('🚨a copy off a picture\'s row lands nothing on an SE row: both '
      'presses are dark, and a press anyway leaves the row and the undo as '
      'they were', () {
    final s = rig();
    stand(s, plain, 0);
    s.clipboard.copyFrameAtCurrentFrame();
    final before = now(s, sound);
    final undoBefore = s.historyManager.undoCount;
    stand(s, sound, 6);

    expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    expect(s.clipboard.canPasteLinkedFrameAtCurrentFrame, isFalse);
    s.clipboard.pasteIndependentFrameAtCurrentFrame();
    s.clipboard.pasteLinkedFrameAtCurrentFrame(joinTakenNames: true);

    expect(
      identical(now(s, sound), before),
      isTrue,
      reason: '「결과적으로 안붙여넣어지도록」 — no block, no cel, no picture',
    );
    expect(s.historyManager.undoCount, undoBefore);
  });

  test('a copy off an SE row lands nothing on a picture\'s row — the same '
      'question the other way', () {
    final s = rig();
    stand(s, sound, 0);
    s.clipboard.copyFrameAtCurrentFrame();
    final before = now(s, other);
    stand(s, other, 6);

    expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    expect(s.clipboard.canPasteLinkedFrameAtCurrentFrame, isFalse);
    s.clipboard.pasteIndependentFrameAtCurrentFrame();

    expect(identical(now(s, other), before), isTrue);
  });

  test('⛔CONTROL: a copy off an SE row lands on another SE row, and a '
      'picture\'s on another picture\'s row, picture and all', () {
    final s = rig();
    stand(s, sound, 0);
    s.clipboard.copyFrameAtCurrentFrame();
    stand(s, voice, 6);
    expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);
    s.clipboard.pasteIndependentFrameAtCurrentFrame();
    expect(blocks(s, voice).keys, [6]);

    stand(s, plain, 2);
    s.clipboard.copyFrameAtCurrentFrame();
    stand(s, other, 6);
    expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);
    s.clipboard.pasteIndependentFrameAtCurrentFrame();
    expect(redOf(s, other, blocks(s, other)[6]), 20);
  });

  test('a band over a picture\'s row and an SE row: the picture\'s row '
      'takes the copy, and the SE row keeps what the band covers on it', () {
    final s = rig();
    stand(s, plain, 0);
    s.clipboard.copyFrameAtCurrentFrame();
    final soundBefore = now(s, sound);
    sweep(s, [other, sound], from: 0, to: 2);

    expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);
    s.clipboard.pasteIndependentFrameAtCurrentFrame();

    expect(redOf(s, other, blocks(s, other)[0]), 10);
    expect(
      identical(now(s, sound), soundBefore),
      isTrue,
      reason: 'a row that does not take the copy lifts nothing either',
    );
  });

  test('a band copied off both kinds pastes each row\'s on the row of its '
      'kind — every row asks of its own row of the board', () {
    final s = rig();
    sweep(s, [plain, sound], from: 0, to: 2);
    s.clipboard.copyFrameAtCurrentFrame();
    s.clearFrameRangeSelection();
    expect(s.clipboard.bankedRowLayerIds, [plain, sound], reason: '⛔전제');
    sweep(s, [other, voice], from: 6, to: 8);

    s.clipboard.pasteIndependentFrameAtCurrentFrame();

    expect(redOf(s, other, blocks(s, other)[6]), 10);
    expect(blocks(s, voice).keys, [6]);
  });
}
