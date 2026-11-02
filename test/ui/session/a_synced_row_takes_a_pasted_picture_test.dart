import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-545 (유저 2026-11-02): 「어태치 싱크 레이어의 프레임블록 복사한걸 다른
/// 어태치 싱크행에 붙여넣을수있게. 대신 블록을 붙여넣는다기보단 그 경우 그림을
/// 교체하는게 되도록. 물론 싱크행을 대상으로 한 링크붙여넣기는 불가」.
///
/// A paste on a synced row hangs pictures in the cels its blocks show: no
/// cel, name, exposure or link moves, as in the trade a rows' hop makes
/// (F-330 · I-98).
void main() {
  const plain = LayerId('plain');
  const other = LayerId('other');
  const base = LayerId('base');
  const m1 = LayerId('m1');
  const m2 = LayerId('m2');
  const m3 = LayerId('m3');
  const m4 = LayerId('m4');
  const sound = LayerId('sound');
  const secondBase = LayerId('second-base');
  const secondMirror = LayerId('second-mirror');
  const conte = LayerId('conte');
  const c1 = LayerId('c1');
  const c2 = LayerId('c2');
  const position = 'position';

  FrameId cel(LayerId row, int index) => FrameId('${row.value}-$index');

  Frame frame(LayerId row, int index, {String? name}) => Frame(
    id: cel(row, index),
    duration: 2,
    name: name,
    strokes: const [],
  );

  /// [blocks] blocks two frames long from frame 0.
  Layer drawn(
    LayerId id, {
    LayerKind kind = LayerKind.animation,
    int blocks = 3,
    String? name,
  }) => Layer(
    id: id,
    name: id.value,
    kind: kind,
    frames: [
      for (var at = 0; at < blocks; at += 1)
        frame(id, at, name: at == 0 ? name : null),
    ],
    timeline: {
      for (var at = 0; at < blocks; at += 1)
        at * 2: TimelineExposure.drawing(cel(id, at), length: 2),
    },
  );

  /// A synced attach row of [on]'s [blocks], its first cel called [name],
  /// its Position keys [keys].
  Layer mirror(
    LayerId id, {
    LayerId on = base,
    LayerKind kind = LayerKind.animation,
    int blocks = 3,
    String? name,
    Map<int, double> keys = const {},
  }) => Layer(
    id: id,
    name: id.value,
    kind: kind,
    attachedToLayerId: on,
    baseFrameLinks: {
      for (var at = 0; at < blocks; at += 1) cel(on, at): cel(id, at),
    },
    timeline: const {},
    transformTrack: TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>(
        keys: {
          for (final MapEntry(key: at, value: x) in keys.entries)
            at: PropertyKey(CanvasPoint(x: x, y: x)),
        },
      ),
    ),
    frames: [
      for (var at = 0; at < blocks; at += 1)
        frame(id, at, name: at == 0 ? name : null),
    ],
  );

  /// Paints [red] over the first tile of [row]'s cel number [index].
  void paint(EditorSessionManager s, LayerId row, int index, int red) {
    final cut = s.requireActiveCut;
    final bytes = Uint8List(256 * 256 * 4);
    for (var pixel = 0; pixel < 256 * 256; pixel += 1) {
      bytes.setRange(pixel * 4, pixel * 4 + 4, [red, 0, 0, 255]);
    }
    s.pixelEditing.coordinator!.restoreSurfaceSnapshot(
      s.brushFrameKeyForCut(cut, row, cel(row, index)),
      BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: 256,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(size: 256, pixels: bytes),
        },
      ),
    );
  }

  void standUpTheCanvas(EditorSessionManager s) {
    final cut = s.requireActiveCut;
    final first = cut.layers.first;
    s.pixelEditing.coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        first.id,
        first.frames.first.id,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: cut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
  }

  /// Every row of the group painted: [plain] 10 20 30, [other] 40 50 60, the
  /// base 70 80 90, the mirrors from 100 by tens — and a second cut of
  /// another canvas, base and mirror unpainted. The first cel of each row of
  /// [blank] is left as it was born.
  EditorSessionManager rig({
    String? nameOnM1,
    String? nameOnPlain,
    Set<LayerId> blank = const {},
  }) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('synced-paste'),
        name: 'Synced paste',
        createdAt: DateTime.utc(2026, 11, 2),
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
                layers: [
                  drawn(plain, name: nameOnPlain),
                  drawn(other),
                  drawn(base),
                  mirror(m1, name: nameOnM1),
                  mirror(m2),
                  mirror(m3),
                  mirror(m4),
                ],
              ),
              Cut(
                id: const CutId('cut-2'),
                name: '2',
                duration: 12,
                canvasSize: const CanvasSize(width: 320, height: 180),
                layers: [
                  drawn(secondBase, blocks: 1),
                  mirror(secondMirror, on: secondBase, blocks: 1),
                ],
              ),
              Cut(
                id: const CutId('cut-3'),
                name: '3',
                duration: 6,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  drawn(conte, kind: LayerKind.storyboard),
                  mirror(
                    c1,
                    on: conte,
                    kind: LayerKind.storyboard,
                    keys: {1: 9},
                  ),
                  mirror(
                    c2,
                    on: conte,
                    kind: LayerKind.storyboard,
                    keys: {4: 5},
                  ),
                ],
              ),
            ],
            seLayers: [drawn(sound, kind: LayerKind.se, blocks: 1)],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    standUpTheCanvas(s);
    var red = 10;
    for (final row in [plain, other, base, m1, m2, m3, m4]) {
      for (var at = 0; at < 3; at += 1) {
        if (at > 0 || !blank.contains(row)) {
          paint(s, row, at, red);
        }
        red += 10;
      }
    }
    return s;
  }

  int redOf(EditorSessionManager s, BrushFrameKey key) {
    final tile = s.pixelEditing.coordinator!
        .currentSurfaceOf(key)
        .tileAt(TileCoord(x: 0, y: 0));
    return tile == null ? 0 : tile.readPixels((_, view) => view[0]);
  }

  /// The red of the picture each of [row]'s blocks shows, in order.
  List<int> shown(EditorSessionManager s, LayerId row) {
    final cut = s.requireActiveCut;
    final stored = cut.layers.firstWhere((layer) => layer.id == row);
    return [
      for (final block in ghostFreeTimeline(
        attachedRowAsShown(stored, cut.layers),
      ).values)
        if (block.isDrawing)
          redOf(s, s.brushFrameKeyForCut(cut, row, block.frameId!)),
    ];
  }

  void stand(EditorSessionManager s, LayerId row, int at) {
    s.selectLayer(row);
    s.selectFrameIndex(at);
  }

  void sweep(
    EditorSessionManager s,
    List<LayerId> rows, {
    required int from,
    required int to,
  }) {
    s.selectLayer(rows.first);
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: rows.first,
      startIndex: from,
      endIndexExclusive: to,
      layerIds: rows,
    );
  }

  /// A copy of [rows] over [from]..[to], the selection let go.
  void copy(
    EditorSessionManager s,
    List<LayerId> rows, {
    required int from,
    required int to,
  }) {
    sweep(s, rows, from: from, to: to);
    s.clipboard.copyFrameAtCurrentFrame();
    s.clearFrameRangeSelection();
  }

  group('a paste standing on a synced row', () {
    test('🚨hangs the picture of a synced row\'s block in the block it '
        'stands on: every cel, name, exposure and link stays, and one undo '
        'takes it back, one redo puts it on again', () {
      final s = rig();
      stand(s, m1, 2);
      s.clipboard.copyFrameAtCurrentFrame();
      final rowsBefore = s.requireActiveCut.layers;
      stand(s, m2, 0);
      expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);

      final undoBefore = s.historyManager.undoCount;
      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [110, 140, 150]);
      expect(s.requireActiveCut.layers, rowsBefore);
      expect(shown(s, m1), [100, 110, 120], reason: 'the copy left its row');
      expect(shown(s, base), [70, 80, 90]);
      expect(s.historyManager.undoCount, undoBefore + 1);

      s.undo();
      expect(shown(s, m2), [130, 140, 150]);
      s.redo();
      expect(shown(s, m2), [110, 140, 150]);
    });

    test('a LINKED paste stands down there: 「싱크행을 대상으로 한 '
        '링크붙여넣기는 불가」', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 0);

      expect(s.clipboard.canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(s.clipboard.pasteLinkedFrameAtCurrentFrame(), isNull);
      expect(shown(s, m2), [130, 140, 150]);
    });

    test('a cursor on a held cell stands on its block', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 3);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [130, 100, 150]);
    });

    test('a run of two pictures hangs in the block stood on and the next', () {
      final s = rig();
      copy(s, [m1], from: 0, to: 4);
      stand(s, m2, 2);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [130, 100, 110]);
    });

    test('the blocks running out stop it', () {
      final s = rig();
      copy(s, [m1], from: 0, to: 6);
      stand(s, m2, 4);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [130, 140, 100]);
    });

    test('with no block at the cursor or past it, nothing is lit', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 8);

      expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    });

    test('with no canvas to hang it on, nothing is lit — as a pixel verb '
        'stands down', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 0);

      s.pixelEditing.coordinator = null;

      expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    });

    test('⚠️Mine: a copy off any drawing row hangs the same way', () {
      final s = rig();
      stand(s, plain, 2);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 0);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [20, 140, 150]);
    });

    test('a copy of no drawing has no picture to hang', () {
      final s = rig();
      stand(s, sound, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      expect(s.clipboard.bankedRowLayerIds, [sound], reason: 'the premise');
      stand(s, m2, 0);

      expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    });

    test('a block the copy found blank leaves its place blank: the picture '
        'is what the block showed', () {
      final s = rig(blank: {m1});
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 0);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [0, 140, 150]);
    });

    test('a blank over a blank is no step at all', () {
      final s = rig(blank: {m1, m2});
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      stand(s, m2, 0);
      final undoBefore = s.historyManager.undoCount;

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(s.historyManager.undoCount, undoBefore);
    });

    test('a picture hung where it already hangs is no step at all', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      final undoBefore = s.historyManager.undoCount;

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(s.historyManager.undoCount, undoBefore);
      expect(shown(s, m1), [100, 110, 120]);
    });

    test('a copy from a cut of another canvas lands at this cut\'s', () {
      final s = rig();
      stand(s, m1, 0);
      s.clipboard.copyFrameAtCurrentFrame();
      s.selectCut(const CutId('cut-2'));
      standUpTheCanvas(s);
      stand(s, secondMirror, 0);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      final cut = s.requireActiveCut;
      final key = s.brushFrameKeyForCut(
        cut,
        secondMirror,
        cel(secondMirror, 0),
      );
      final landed = s.pixelEditing.coordinator!.currentSurfaceOf(key);
      expect(landed.canvasSize, cut.canvasSize);
      expect(shown(s, secondMirror), [100]);
    });

    test('a row riding the conte keeps lanes of its own (I-99): its keys '
        'come along, and no key past them moves, as no cell of it does', () {
      final s = rig();
      s.selectCut(const CutId('cut-3'));
      standUpTheCanvas(s);
      paint(s, c1, 0, 10);
      paint(s, c1, 1, 20);
      s.selectLayer(c1);
      s.updateFrameRangeSelectionDrag(
        layerId: c1,
        anchorIndex: 0,
        headIndex: 3,
        spanRows: [
          const LayerRowAddress(c1),
          const LaneRowAddress(c1, position),
        ],
      );
      s.clipboard.copyFrameAtCurrentFrame();
      s.clearFrameRangeSelection();
      stand(s, c2, 0);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(
        s.layerById(c2)!.transformTrack.position.keys.keys.toList(),
        [1, 4],
      );
      expect(shown(s, c2), [10, 20, 0]);
    });
  });

  group('a selection', () {
    test('holds the paste to the blocks it covers', () {
      final s = rig();
      copy(s, [m1], from: 0, to: 6);
      sweep(s, [m2], from: 0, to: 4);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [100, 110, 150]);
      expect(s.frameRangeSelection.value, isNull, reason: 'a replacing paste');
    });

    test('that starts inside a block starts on that block', () {
      final s = rig();
      copy(s, [m1], from: 0, to: 2);
      sweep(s, [m2], from: 3, to: 4);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [130, 100, 150]);
    });

    test('on cells no block stands on lights nothing', () {
      final s = rig();
      copy(s, [m1], from: 0, to: 2);
      sweep(s, [m2], from: 7, to: 9);

      expect(s.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);
    });

    test('🚨across two synced rows copies both and pastes them, row by row, '
        'on the two it is swept over: 「선택된 모든게」', () {
      final s = rig();
      copy(s, [m1, m2], from: 0, to: 2);
      expect(s.clipboard.bankedRowLayerIds, [m1, m2]);
      sweep(s, [m3, m4], from: 2, to: 4);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m3), [160, 100, 180]);
      expect(shown(s, m4), [190, 130, 210]);
    });

    test('takes a synced row\'s seat when the anchor is a row of its own: '
        'the row beside it lands on the seat past it', () {
      final s = rig();
      copy(s, [plain, m1, other], from: 0, to: 2);
      expect(s.clipboard.bankedRowLayerIds, [plain, m1, other]);
      sweep(s, [plain, m2, other], from: 4, to: 6);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, m2), [130, 140, 100]);
      expect(shown(s, plain).last, 10);
      expect(shown(s, other).last, 40);
    });

    test('a base pasted beside its synced row hands the row the cel the '
        'picture goes in: it lands after the splice', () {
      final s = rig();
      copy(s, [plain, m1], from: 0, to: 2);
      sweep(s, [base, m1], from: 2, to: 4);

      s.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, base), [70, 10, 90]);
      expect(shown(s, m1), [100, 100, 120]);
    });

    test('a LINKED paste passes a synced row by, keeping its seat', () {
      final s = rig();
      copy(s, [plain, m1, other], from: 0, to: 2);
      sweep(s, [plain, m2, other], from: 4, to: 6);

      s.clipboard.pasteLinkedFrameAtCurrentFrame(joinTakenNames: true);

      expect(shown(s, m2), [130, 140, 150]);
      expect(shown(s, other).last, 40);
    });

    test('a LINKED paste asks nothing of a synced row: no name joins there',
        () {
      final s = rig(nameOnPlain: 'A', nameOnM1: 'A');
      copy(s, [plain], from: 0, to: 2);
      sweep(s, [plain, m1], from: 4, to: 6);

      expect(s.clipboard.pasteLinkedFrameAtCurrentFrame(), isNull);
      expect(shown(s, plain).last, 10, reason: 'it pasted, and did not ask');
    });

    test('🚨a cut banks a synced row\'s pictures and lifts nothing off it: '
        'its blocks are its base\'s', () {
      final s = rig();
      sweep(s, [plain, m1], from: 0, to: 2);
      expect(s.clipboard.canCutRunAtCurrentFrame, isTrue);

      s.clipboard.cutRunAtCurrentFrame();

      expect(s.clipboard.bankedRowLayerIds, [plain, m1]);
      final stored = s.repository.requireProject().tracks.single.cuts.first;
      expect(
        stored.layers.firstWhere((layer) => layer.id == m1).timeline,
        isEmpty,
        reason: 'it stores no timeline',
      );
      expect(shown(s, m1), [100, 110, 120]);
      expect(shown(s, plain), [20, 30]);
    });
  });
}
