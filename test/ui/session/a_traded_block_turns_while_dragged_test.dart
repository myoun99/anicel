import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-98 (유저 2026-10-26): 「잘 바뀌는데, 바꾸는동안 블록이 라이브로
/// 안변함. 즉 위엔 빈 블록, 아래는 그림 존재하는 흰 블록일때, 바꾸는 도중에
/// 위가 빈 블록, 아래가 흰 블록인 채임. 거기서 손 떼고 나서야 블록이 서로
/// 변함. 다른 블록 드래그 규칙 통일적용해서 라이브로 변하게」.
///
/// A trade (F-330) carries no cel: the blocks stand where they stood, and
/// each one's white or grey is where its picture IS while the hand is down
/// ([celPixelsOf], F-313) — so the rows must be told the moment the trade is
/// shown, as they are when a picture lands, and again when it is taken back.
void main() {
  /// A base with one cel on frame 0 holding a picture, and the synced row
  /// above it, whose cel there holds none — 「위엔 빈 블록, 아래는 흰 블록」 —
  /// with the coordinator the canvas hands the pixel verbs, as a trade
  /// needs to be able to write what it shows.
  ({EditorSessionManager s, LayerId base, LayerId mirror}) group() {
    const tileSize = 256;
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    s.createDrawingAtCurrentFrame();
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final mirror = s.activeLayer!.id;
    final cut = s.requireActiveCut;
    final baseKey = s.brushFrameKeyForCut(
      cut,
      base,
      s.layerById(base)!.frames.first.id,
    );
    s.pixelEditing.coordinator =
        BrushFrameEditingCoordinator(
          initialFrameKey: baseKey,
          frameStore: s.renderCaches.brushFrameStore,
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: cut.canvasSize,
            tileSize: tileSize,
          ),
          historyPolicy: const BrushHistoryPolicy(),
        )..restoreSurfaceSnapshot(
          baseKey,
          BitmapSurface(
            canvasSize: cut.canvasSize,
            tileSize: tileSize,
            tiles: {
              TileCoord(x: 0, y: 0): BitmapTile(
                size: tileSize,
                pixels: Uint8List(tileSize * tileSize * 4)
                  ..fillRange(0, tileSize * tileSize * 4, 0xFF),
              ),
            },
          ),
        );
    return (s: s, base: base, mirror: mirror);
  }

  /// Whether [row]'s block on frame 0 reads as drawn — the white the rows
  /// paint ([LayerStack.celHasContentForLayer]).
  bool drawn(EditorSessionManager s, LayerId row) =>
      s.layerStack.celHasContentForLayer(s.layerById(row)!, 0);

  /// The rows of [rows] told to paint again since the last read — each
  /// listening as its painter does.
  Set<LayerId> Function() hearing(EditorSessionManager s, List<LayerId> rows) {
    final heard = <LayerId>{};
    for (final row in rows) {
      void hears() => heard.add(row);
      final signal = s.layerStack.celTintRevision.forRow(row);
      signal.addListener(hears);
      addTearDown(() => signal.removeListener(hears));
    }
    return () {
      final read = {...heard};
      heard.clear();
      return read;
    };
  }

  void beginTrade(EditorSessionManager s, LayerId base, LayerId mirror) {
    s.selectLayer(base);
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);
  }

  test('the trade shown turns both blocks while the hand is down, and the '
      'rows are told so', () {
    final (:s, :base, :mirror) = group();
    expect([drawn(s, mirror), drawn(s, base)], [false, true], reason: '⛔전제');
    final heard = hearing(s, [base, mirror]);

    beginTrade(s, base, mirror);

    expect(
      [drawn(s, mirror), drawn(s, base)],
      [true, false],
      reason: 'the picture is on its way up, and the base\'s cel will be '
          'left without one',
    );
    expect(heard(), {base, mirror});
  });

  test('a trade taken back — the hand moved off the other row — turns them '
      'back, and tells the rows again', () {
    final (:s, :base, :mirror) = group();
    beginTrade(s, base, mirror);
    final heard = hearing(s, [base, mirror]);

    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: base);

    expect([drawn(s, mirror), drawn(s, base)], [false, true]);
    expect(heard(), {base, mirror});
  });

  test('the same trade shown again tells no row', () {
    final (:s, :base, :mirror) = group();
    beginTrade(s, base, mirror);
    final heard = hearing(s, [base, mirror]);

    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);

    expect(heard(), isEmpty, reason: 'nothing moved: no row paints again');
  });

  test('a trade let go of without landing turns both blocks back, and tells '
      'their rows', () {
    final (:s, :base, :mirror) = group();
    beginTrade(s, base, mirror);
    final heard = hearing(s, [base, mirror]);

    s.rangeMove.cancelFrameRangeMoveDrag();

    expect(s.dragPreview.value, isNull, reason: '⛔전제: the hand is off');
    expect([drawn(s, mirror), drawn(s, base)], [false, true]);
    expect(heard(), {base, mirror});
  });

  // ⛔F-166: every row painting again throws the dock's still picture away,
  // so a drag tells the rows only when it hangs a picture somewhere else —
  // not on every step it shows.
  test('a block carried along its own row hangs no picture elsewhere, and '
      'tells no row', () {
    final (:s, :base, :mirror) = group();
    s.selectLayer(base);
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    final heard = hearing(s, [base, mirror]);

    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2, targetLayerId: base);
    expect(s.dragPreview.value, isNotNull, reason: '⛔전제: a step shown');
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3, targetLayerId: base);

    expect(heard(), isEmpty);
  });
}
