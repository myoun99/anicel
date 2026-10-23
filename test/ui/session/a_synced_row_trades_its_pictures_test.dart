import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🗣️F-330 (유저 2026-10-10): 「같은 위치에 대한 행이동은 타임라인을 바꾸는게
/// 아니고 서로의 그림을 바꾸는거라 가능해도될듯. 물론 … 이름이 사라진다던가
/// 하는 버그는 신중하게 확인」 · I-98 (10-14): 「싱크행이라도 선택/드래그로
/// 블록끼리 자리바꾸는 이동은 가능하도록. 내부 그림만 바꿔치기」.
///
/// A range moved on the same frames onto another row of its attach group
/// trades the rows' PICTURES: no cel, name, exposure or link moves.
void main() {
  const tileSize = 256;

  /// A session whose base has cels on frames 0 and 2, under [mirrors]
  /// synced rows above it — each cel painted its own red, the coordinator
  /// the canvas would hand the pixel verbs set up.
  ({EditorSessionManager s, LayerId base, List<LayerId> mirrors}) attachGroup({
    int mirrors = 1,
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final base = s.activeLayer!.id;
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(0);
    final mirrorIds = <LayerId>[];
    for (var n = 0; n < mirrors; n += 1) {
      s.folders.addAttachedLayer(AttachedPlacement.above);
      mirrorIds.add(s.activeLayer!.id);
    }
    final cut = s.requireActiveCut;
    s.pixelEditing.coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        base,
        s.layerById(base)!.frames.first.id,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: cut.canvasSize,
        tileSize: tileSize,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    var red = 10;
    for (final row in [base, ...mirrorIds]) {
      for (final frame in s.layerById(row)!.frames) {
        paint(s, row, frame.id, red);
        red += 10;
      }
    }
    return (s: s, base: base, mirrors: mirrorIds);
  }

  test('a base\'s range dropped on its synced row on the same frames trades '
      'their pictures cel for cel — every cel, name and block stays — and '
      'one undo trades them back', () {
    final (:s, :base, :mirrors) = attachGroup();
    final mirror = mirrors.single;
    final before = reds(s, [base, mirror]);
    final rowsBefore = s.requireActiveCut.layers;
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 0,
      headIndex: 2,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);

    final baseCel = s.layerById(base)!.frames.first.id;
    final mirrorCel = s.layerById(mirror)!.baseFrameLinks[baseCel]!;
    expect(
      celPixelsOf(s.dragPreview.value, base, baseCel),
      (row: mirror, cel: mirrorCel),
      reason: 'while the hand is down, the base cel shows the picture coming '
          'to it — still in the mirror\'s cel',
    );
    expect(s.frameRangeSelection.value!.layerId, mirror);
    expect(reds(s, [base, mirror]), before, reason: 'nothing written yet');
    final shown = s.dragPreview.value;
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);
    expect(
      identical(s.dragPreview.value, shown),
      isTrue,
      reason: 'a step that trades the same pictures shows the same preview — '
          'the canvas reads it by identity, and sleeps through it',
    );

    final pairs = [
      for (final cel in s.layerById(base)!.frames)
        (
          s.brushFrameKeyForCut(s.requireActiveCut, base, cel.id),
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            mirror,
            s.layerById(mirror)!.baseFrameLinks[cel.id]!,
          ),
        ),
    ];
    final pairedBefore = [
      for (final (baseKey, mirrorKey) in pairs)
        (redOf(s, baseKey), redOf(s, mirrorKey)),
    ];

    s.rangeMove.endFrameRangeMoveDrag();

    expect(
      [
        for (final (baseKey, mirrorKey) in pairs)
          (redOf(s, mirrorKey), redOf(s, baseKey)),
      ],
      pairedBefore,
      reason: 'each base cel holds what its own mirror cel held, and back',
    );
    expect(pairedBefore.every((pair) => pair.$1 != pair.$2), isTrue);
    expect(
      s.requireActiveCut.layers,
      rowsBefore,
      reason: '유저: 「이름이 사라진다던가 하는 버그」 — no cel, name, block or '
          'link moved',
    );
    expect(s.frameRangeSelection.value!.layerId, mirror);

    s.undo();
    expect(reds(s, [base, mirror]), before);
  });

  test('a range of synced rows alone trades too — one mirror\'s pictures '
      'for another\'s, the base untouched', () {
    final (:s, :base, :mirrors) = attachGroup(mirrors: 2);
    final before = {
      for (final row in [base, ...mirrors]) row: reds(s, [row]),
    };
    s.updateFrameRangeSelectionDrag(
      layerId: mirrors.first,
      anchorIndex: 0,
      headIndex: 2,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(mirrors.first), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: mirrors.last,
    );
    s.rangeMove.endFrameRangeMoveDrag();

    expect(reds(s, [base]), before[base]);
    expect(reds(s, [mirrors.first]), before[mirrors.last]);
    expect(reds(s, [mirrors.last]), before[mirrors.first]);
  });

  test('a range of synced rows released without a trade moves nothing and '
      'says to edit the owner', () {
    final (:s, :base, :mirrors) = attachGroup();
    final mirror = mirrors.single;
    final before = reds(s, [base, mirror]);
    final rowsBefore = s.requireActiveCut.layers;
    s.updateFrameRangeSelectionDrag(
      layerId: mirror,
      anchorIndex: 0,
      headIndex: 2,
    );
    cursorNotices.clear();

    expect(s.rangeMove.beginFrameRangeMoveDrag(mirror), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3, targetLayerId: mirror);
    expect(s.dragPreview.value, isNull, reason: 'its blocks are the base\'s');
    s.rangeMove.endFrameRangeMoveDrag();

    expect(cursorNotices.message, AppText.strings.noticeEditAttachOwner);
    cursorNotices.clear();
    expect(s.requireActiveCut.layers, rowsBefore);
    expect(reds(s, [base, mirror]), before);
  });

  test('a step off the same frames is the move again: the base slides, and '
      'no picture trades', () {
    final (:s, :base, :mirrors) = attachGroup();
    final mirror = mirrors.single;
    final before = reds(s, [base, mirror]);
    s.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 0,
      headIndex: 2,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: mirror);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 4, targetLayerId: mirror);
    s.rangeMove.endFrameRangeMoveDrag();

    final slid = s.layerById(base)!.timeline;
    expect(slid.containsKey(4), isTrue, reason: 'the base slid');
    expect(slid.containsKey(0), isFalse);
    expect(reds(s, [base, mirror]), before);
  });
}

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

/// The red of each cel of [rows], row by row in cel order — 0 for an
/// empty cel.
List<int> reds(EditorSessionManager s, List<LayerId> rows) => [
  for (final row in rows)
    for (final frame in s.layerById(row)!.frames)
      redOf(s, s.brushFrameKeyForCut(s.requireActiveCut, row, frame.id)),
];

int redOf(EditorSessionManager s, BrushFrameKey key) {
  final tile = s.pixelEditing.coordinator!
      .currentSurfaceOf(key)
      .tileAt(TileCoord(x: 0, y: 0));
  return tile == null ? 0 : tile.readPixels((_, view) => view[0]);
}
