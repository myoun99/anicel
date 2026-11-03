import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/cel_rekey.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🗣️F-546 (유저 2026-11-03): 「일반행 복사해서 다른 어태치싱크행에
/// 붙여넣을수있듯이. 그게 그림교체로 작동하듯이, 일반행을 어태치싱크행으로
/// 블록을 드래그하는것도 가능하게. 지금은 어태치행으로 드래그하면 기준행의
/// 블록을 바꿔치도록 작동되고있음. 어태치행이랑 그림 바꿔치는느낌? 결과적으로
/// 그렇게되면됨. 발견되는것들 알아서 법 통일」.
///
/// A drag with a synced row on either end moves no block: the blocks it
/// carries trade pictures with the blocks they land on, picked as a paste
/// picks them.
void main() {
  const tileSize = 256;

  setUp(cursorNotices.clear);

  /// A drawing row added over the active one: a new row's cel on frame 0,
  /// and one on each of [frames].
  LayerId drawingRow(EditorSessionManager s, List<int> frames) {
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final row = s.activeLayer!.id;
    for (final frame in frames) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    s.selectFrameIndex(0);
    return row;
  }

  /// [count] synced rows on [row], [placement] it.
  List<LayerId> mirrorsOn(
    EditorSessionManager s,
    LayerId row,
    int count, {
    AttachedPlacement placement = AttachedPlacement.above,
  }) {
    final mirrors = <LayerId>[];
    for (var n = 0; n < count; n += 1) {
      s.selectLayer(row);
      s.folders.addAttachedLayer(placement);
      mirrors.add(s.activeLayer!.id);
    }
    return mirrors;
  }

  /// A session over rows built by [build], every cel of every row painted
  /// its own red, the coordinator the canvas would hand the pixel verbs set
  /// up.
  EditorSessionManager sessionOf(void Function(EditorSessionManager) build) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    build(s);
    final cut = s.requireActiveCut;
    final first = s.layers.firstWhere((row) => row.frames.isNotEmpty);
    s.pixelEditing.coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        first.id,
        first.frames.first.id,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: cut.canvasSize,
        tileSize: tileSize,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    var red = 10;
    for (final row in s.layers) {
      for (final frame in row.frames) {
        paint(s, row.id, frame.id, red);
        red += 5;
      }
    }
    return s;
  }

  void sweep(
    EditorSessionManager s,
    LayerId row, {
    required int from,
    required int to,
    LayerId? over,
  }) {
    s.selectLayer(row);
    s.updateFrameRangeSelectionDrag(
      layerId: row,
      anchorIndex: from,
      headIndex: to,
      headLayerId: over,
    );
  }

  void drag(
    EditorSessionManager s,
    LayerId from, {
    required LayerId onto,
    int frames = 0,
  }) {
    expect(s.rangeMove.beginFrameRangeMoveDrag(from), isTrue, reason: '전제');
    s.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: frames,
      targetLayerId: onto,
    );
  }

  List<CelPictureMove> shownMoves(EditorSessionManager s) =>
      switch (s.dragPreview.value) {
        BlockMoveDragPreview(:final picturesMoved) => picturesMoved,
        _ => const [],
      };

  group('🎯a block dragged onto a synced row', () {
    /// A plain row's cels on 0 and 2 beside a base's on 0, 2 and 4 and its
    /// synced row.
    ({EditorSessionManager s, LayerId plain, LayerId base, LayerId mirror})
    rows() {
      late LayerId plain;
      late LayerId base;
      late LayerId mirror;
      final s = sessionOf((s) {
        base = drawingRow(s, [2, 4]);
        mirror = mirrorsOn(s, base, 1).single;
        s.selectLayer(base);
        plain = drawingRow(s, [2]);
      });
      return (s: s, plain: plain, base: base, mirror: mirror);
    }

    test('trades pictures with the block it lands on: no block, cel, name or '
        'link moves, and one undo trades them back', () {
      final (:s, :plain, :base, :mirror) = rows();
      final (a, b) = (redAt(s, plain, 0), redAt(s, mirror, 0));
      final baseRed = redAt(s, base, 0);
      final rowsBefore = s.requireActiveCut.layers;
      final steps = s.historyManager.undoCount;
      sweep(s, plain, from: 0, to: 0);

      drag(s, plain, onto: mirror);
      expect(redAt(s, plain, 0), a, reason: 'nothing written yet');
      expect(redAt(s, mirror, 0), b);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, mirror, 0), a);
      expect(redAt(s, plain, 0), b, reason: '유저: 「그림 바꿔치는느낌」');
      expect(
        redAt(s, base, 0),
        baseRed,
        reason: '유저: 「기준행의 블록을 바꿔치도록」 is what stops',
      );
      expect(s.requireActiveCut.layers, rowsBefore);
      expect(s.historyManager.undoCount, steps + 1);
      expect(s.frameRangeSelection.value!.layerId, mirror);
      expect(s.activeLayer!.id, mirror);

      s.undo();
      expect(redAt(s, plain, 0), a);
      expect(redAt(s, mirror, 0), b);
    });

    test('anywhere along the row: the block at the landing, as a paste at '
        'that frame takes it', () {
      final (:s, :plain, :base, :mirror) = rows();
      final a = redAt(s, plain, 0);
      final (held, standing) = (redAt(s, mirror, 2), redAt(s, mirror, 0));
      final baseBefore = s.layerById(base)!.timeline;
      sweep(s, plain, from: 0, to: 0);

      drag(s, plain, onto: mirror, frames: 2);
      expect(s.frameRangeSelection.value!.startIndex, 2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, mirror, 2), a);
      expect(redAt(s, plain, 0), held);
      expect(redAt(s, mirror, 0), standing);
      expect(s.frameRangeSelection.value!.startIndex, 2);
      expect(s.layerById(base)!.timeline, baseBefore);
    });

    test('its blocks, the first to the first of those from the landing, '
        'until either runs out', () {
      final (:s, :plain, :mirror, base: _) = rows();
      final (a0, a2) = (redAt(s, plain, 0), redAt(s, plain, 2));
      final (m2, m4) = (redAt(s, mirror, 2), redAt(s, mirror, 4));
      sweep(s, plain, from: 0, to: 2);

      drag(s, plain, onto: mirror, frames: 2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, mirror, 2), a0);
      expect(redAt(s, mirror, 4), a2);
      expect(redAt(s, plain, 0), m2);
      expect(redAt(s, plain, 2), m4);
    });

    test('the hand moved along one block shows the same pictures, and the '
        'selection follows it', () {
      final (:s, :plain, :mirror, base: _) = rows();
      sweep(s, plain, from: 0, to: 0);

      drag(s, plain, onto: mirror);
      final shown = s.dragPreview.value;
      expect(shownMoves(s), isNotEmpty);
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: mirror,
      );
      expect(identical(s.dragPreview.value, shown), isTrue);
      s.rangeMove.cancelFrameRangeMoveDrag();
      expect(s.frameRangeSelection.value!.layerId, plain);
    });

    test('⛔slid along by its own mirror it is the slide it was, over a block '
        'of its row or not', () {
      final (:s, :base, :mirror, plain: _) = rows();
      sweep(s, base, from: 0, to: 0, over: mirror);

      drag(s, mirror, onto: mirror, frames: 2);

      expect(shownMoves(s), isEmpty);
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('⛔a span of mirrors over no block still says so at the press', () {
      final (:s, :mirror, base: _, plain: _) = rows();
      sweep(s, mirror, from: 9, to: 9);

      expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isFalse);
      expect(cursorNotices.message, AppText.strings.noticeEditAttachOwner);
      cursorNotices.clear();
    });

    test('⛔where no block stands at the landing it is the move it was: the '
        'block goes to the base, and the mirror shows it', () {
      final (:s, :plain, :base, :mirror) = rows();
      final cel = s.layerById(plain)!.timeline[0]!.frameId;
      sweep(s, plain, from: 0, to: 0);

      drag(s, plain, onto: mirror, frames: 9);
      expect(shownMoves(s), isEmpty);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(s.layerById(base)!.timeline[9]?.frameId, cel);
      expect(s.layerById(plain)!.timeline[0], isNull);
    });
  });

  group('every row on either end', () {
    /// Two attach groups side by side.
    ({
      EditorSessionManager s,
      LayerId base,
      LayerId mirror,
      LayerId otherBase,
      LayerId otherMirror,
    })
    groups() {
      late LayerId base;
      late LayerId mirror;
      late LayerId otherBase;
      late LayerId otherMirror;
      final s = sessionOf((s) {
        base = drawingRow(s, [2]);
        mirror = mirrorsOn(s, base, 1).single;
        s.selectLayer(base);
        otherBase = drawingRow(s, [2]);
        otherMirror = mirrorsOn(s, otherBase, 1).single;
      });
      return (
        s: s,
        base: base,
        mirror: mirror,
        otherBase: otherBase,
        otherMirror: otherMirror,
      );
    }

    void expectTraded(
      EditorSessionManager s,
      LayerId from,
      LayerId onto, {
      int frames = 0,
    }) {
      final rowsBefore = s.requireActiveCut.layers;
      final (a, b) = (redAt(s, from, 0), redAt(s, onto, frames));
      sweep(s, from, from: 0, to: 0);
      drag(s, from, onto: onto, frames: frames);
      s.rangeMove.endFrameRangeMoveDrag();
      expect(redAt(s, onto, frames), a);
      expect(redAt(s, from, 0), b);
      expect(s.requireActiveCut.layers, rowsBefore);
    }

    test('a base onto another group\'s mirror', () {
      final (:s, :base, :otherMirror, mirror: _, otherBase: _) = groups();
      expectTraded(s, base, otherMirror);
    });

    test('a mirror onto another group\'s', () {
      final (:s, :mirror, :otherMirror, base: _, otherBase: _) = groups();
      expectTraded(s, mirror, otherMirror);
    });

    test('a mirror onto a row of its own blocks', () {
      final (:s, :mirror, :otherBase, base: _, otherMirror: _) = groups();
      expectTraded(s, mirror, otherBase);
    });

    test('a base onto its own mirror, along the frames', () {
      final (:s, :base, :mirror, otherBase: _, otherMirror: _) = groups();
      expectTraded(s, base, mirror, frames: 2);
    });

    test('a mirror onto another of its group, along the frames', () {
      late LayerId first;
      late LayerId second;
      final s = sessionOf((s) {
        final base = drawingRow(s, [2]);
        [first, second] = mirrorsOn(s, base, 2);
      });
      expectTraded(s, first, second, frames: 2);
    });

    test('a block swept with its mirror trades once, the base\'s', () {
      final (:s, :base, :mirror, :otherMirror, otherBase: _) = groups();
      final (a, b) = (redAt(s, base, 0), redAt(s, otherMirror, 0));
      final kept = redAt(s, mirror, 0);
      sweep(s, base, from: 0, to: 0, over: mirror);

      drag(s, base, onto: otherMirror);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, otherMirror, 0), a);
      expect(redAt(s, base, 0), b);
      expect(redAt(s, mirror, 0), kept);
    });

    test('⛔a mirror onto a row whose block is pinned says to edit the owner',
        () {
      late LayerId mirror;
      late LayerId image;
      final s = sessionOf((s) {
        mirror = mirrorsOn(s, drawingRow(s, []), 1).single;
        s.layerStack.addLayerOfKind(LayerKind.image);
        image = s.activeLayer!.id;
        s.createDrawingAtCurrentFrame();
      });
      expect(shownRow(s, image).timeline[0]?.frameId, isNotNull, reason: '전제');
      sweep(s, mirror, from: 0, to: 0);

      drag(s, mirror, onto: image);

      expect(shownMoves(s), isEmpty);
      s.rangeMove.endFrameRangeMoveDrag();
      expect(cursorNotices.message, AppText.strings.noticeEditAttachOwner);
      cursorNotices.clear();
    });

    test('a mirror with nothing at the landing still says to edit the owner',
        () {
      final (:s, :mirror, :otherBase, base: _, otherMirror: _) = groups();
      final rowsBefore = s.requireActiveCut.layers;
      sweep(s, mirror, from: 0, to: 0);

      drag(s, mirror, onto: otherBase, frames: 9);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(cursorNotices.message, AppText.strings.noticeEditAttachOwner);
      cursorNotices.clear();
      expect(s.requireActiveCut.layers, rowsBefore);
    });

    test('mirrors over one block of two take the press', () {
      late LayerId mirror;
      late LayerId otherMirror;
      final s = sessionOf((s) {
        mirror = mirrorsOn(s, drawingRow(s, [2]), 1).single;
        otherMirror = mirrorsOn(
          s,
          drawingRow(s, []),
          1,
          placement: AttachedPlacement.below,
        ).single;
      });
      sweep(s, otherMirror, from: 2, to: 2, over: mirror);
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        unorderedEquals([otherMirror, mirror]),
        reason: '전제',
      );

      expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isTrue);
      s.rangeMove.cancelFrameRangeMoveDrag();
    });

    test('mirrors of two groups take the press, and trade', () {
      late LayerId mirror;
      late LayerId otherBase;
      late LayerId otherMirror;
      final s = sessionOf((s) {
        final base = drawingRow(s, [2]);
        mirror = mirrorsOn(s, base, 1).single;
        otherBase = drawingRow(s, [2]);
        otherMirror = mirrorsOn(
          s,
          otherBase,
          1,
          placement: AttachedPlacement.below,
        ).single;
      });
      expect(
        [for (final row in sectionedLayerOrder(s.layers)) row.id],
        containsAllInOrder([mirror, otherMirror, otherBase]),
        reason: '전제',
      );
      final (a, b) = (redAt(s, otherMirror, 0), redAt(s, mirror, 0));
      final (c, d) = (redAt(s, otherBase, 2), redAt(s, otherMirror, 2));
      sweep(s, otherMirror, from: 0, to: 0, over: mirror);
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        unorderedEquals([otherMirror, mirror]),
        reason: '전제',
      );

      drag(s, mirror, onto: otherMirror, frames: 2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, otherBase, 2), a);
      expect(redAt(s, otherMirror, 2), b);
      expect(redAt(s, otherMirror, 0), c);
      expect(redAt(s, mirror, 0), d);
    });
  });

  group('several rows', () {
    /// Rows in the order the walk takes them: a base, its two mirrors [far]
    /// and [near], and [lower] and [upper].
    ({
      EditorSessionManager s,
      LayerId upper,
      LayerId lower,
      LayerId near,
      LayerId far,
      LayerId base,
    })
    stack({List<int> upperCels = const [2]}) {
      late LayerId upper;
      late LayerId lower;
      late LayerId base;
      final s = sessionOf((s) {
        base = drawingRow(s, [2, 4]);
        final mirrors = mirrorsOn(s, base, 2);
        s.selectLayer(mirrors.last);
        lower = drawingRow(s, [2]);
        upper = drawingRow(s, upperCels);
      });
      final order = [for (final row in sectionedLayerOrder(s.layers)) row.id];
      final at = order.indexOf(lower);
      expect(order.sublist(at - 3, at + 2), [
        base,
        order[at - 2],
        order[at - 1],
        lower,
        upper,
      ], reason: '전제');
      return (
        s: s,
        upper: upper,
        lower: lower,
        near: order[at - 1],
        far: order[at - 2],
        base: base,
      );
    }

    test('🎯all landing on synced rows trade together, in one step', () {
      final (:s, :upper, :lower, :near, :far, base: _) = stack();
      final (a, b) = (redAt(s, upper, 0), redAt(s, lower, 0));
      final (m, n) = (redAt(s, near, 0), redAt(s, far, 0));
      final steps = s.historyManager.undoCount;
      sweep(s, upper, from: 0, to: 0, over: lower);

      drag(s, lower, onto: far);
      expect(
        s.frameRangeSelection.value!.spanLayerIds,
        unorderedEquals([near, far]),
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, near, 0), a);
      expect(redAt(s, far, 0), b);
      expect(redAt(s, upper, 0), m);
      expect(redAt(s, lower, 0), n);
      expect(s.historyManager.undoCount, steps + 1);
    });

    for (final frames in [0, 2]) {
      test('⛔one row landing on a synced row and one on a row of its own is '
          'the rigid move it was, $frames frames along', () {
        final (:s, :upper, :lower, :near, far: _, base: _) = stack();
        sweep(s, upper, from: 0, to: 0, over: lower);

        drag(s, lower, onto: near, frames: frames);

        expect(shownMoves(s), isEmpty, reason: 'a block leaves the row');
        s.rangeMove.cancelFrameRangeMoveDrag();
      });
    }

    test('a row of the span with no block in it stands aside', () {
      final (:s, :upper, :lower, :near, far: _, base: _) = stack(
        upperCels: const [],
      );
      final (a, b) = (redAt(s, lower, 2), redAt(s, near, 2));
      sweep(s, upper, from: 2, to: 2, over: lower);

      drag(s, lower, onto: near);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(redAt(s, near, 2), a);
      expect(redAt(s, lower, 2), b);
    });

    test('⛔a landing that gives a cel twice holds: a trade hangs every '
        'picture it takes', () {
      late List<LayerId> mirrors;
      final s = sessionOf((s) {
        mirrors = mirrorsOn(s, drawingRow(s, [2, 4]), 3);
      });
      final order = [
        for (final row in sectionedLayerOrder(s.layers))
          if (mirrors.contains(row.id)) row.id,
      ];
      final [nearest, middle, farthest] = order;
      List<int> pictures() => [
        for (final row in order)
          for (final frame in [0, 2, 4]) redAt(s, row, frame),
      ];
      final before = pictures();
      sweep(s, nearest, from: 0, to: 2, over: middle);

      drag(s, middle, onto: farthest, frames: 2);

      expect(shownMoves(s), isEmpty);
      s.rangeMove.endFrameRangeMoveDrag();
      expect(pictures(), before);
    });
  });
}

/// [row] as the rail shows it.
Layer shownRow(EditorSessionManager s, LayerId row) =>
    s.layers.firstWhere((layer) => layer.id == row);

/// Paints [red] over the first tile of [row]'s cel [cel].
void paint(EditorSessionManager s, LayerId row, FrameId cel, int red) {
  final cut = s.requireActiveCut;
  final bytes = Uint8List(256 * 256 * 4);
  for (var pixel = 0; pixel < 256 * 256; pixel += 1) {
    bytes.setRange(pixel * 4, pixel * 4 + 4, [red, 0, 0, 255]);
  }
  s.pixelEditing.coordinator!.restoreSurfaceSnapshot(
    s.brushFrameKeyForCut(cut, row, cel),
    BitmapSurface(
      canvasSize: cut.canvasSize,
      tileSize: 256,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(size: 256, pixels: bytes),
      },
    ),
  );
}

/// The red of what [row] shows at [frame], 0 for an empty cel.
int redAt(EditorSessionManager s, LayerId row, int frame) {
  final cel = shownRow(s, row).timeline[frame]!.frameId!;
  final tile = s.pixelEditing.coordinator!
      .currentSurfaceOf(s.brushFrameKeyForCut(s.requireActiveCut, row, cel))
      .tileAt(TileCoord(x: 0, y: 0));
  return tile == null ? 0 : tile.readPixels((_, view) => view[0]);
}
