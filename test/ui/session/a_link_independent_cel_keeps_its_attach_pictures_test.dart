import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/independent_clip_mint.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🚨F-275 (유저 2026-10-04): 「기준레이어 링크된상태에서 독립시킬때, 어태치
/// 싱크레이어의 그림은 사라지고 기준레이어 그림만 남아있는데, 어태치 싱크
/// 레이어 그림도 남아있도록」.
///
/// A synced attach row keeps one MIRROR cel per base cel, found by the base
/// cel's id. 링크 독립 gives the base's block a cel of its own — a new id —
/// and the settle minted an EMPTY mirror under it: the base kept its picture
/// and the attach row lost the one it had drawn there.
void main() {
  /// A picture at the CUT's canvas size, its first bytes [shade].
  BitmapSurface ink(CanvasSize canvasSize, int shade) {
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..fillRange(0, 16, shade);
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: tile, pixels: pixels),
      ),
    ]);
  }

  Layer rowOf(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  int? shadeOf(EditorSessionManager s, LayerId rowId, FrameId cel) => s
      .renderCaches
      .brushFrameStore
      .bakedSurfaceOrNull(
        s.brushFrameKeyForCut(s.requireActiveCut, rowId, cel),
      )
      ?.tiles
      .values
      .firstOrNull
      ?.pixels
      .first;

  /// A base row showing cel A at 0 and — linked — at 5, with a synced attach
  /// row whose mirror of A carries a picture of its own.
  ({
    EditorSessionManager s,
    LayerId base,
    LayerId attach,
    FrameId a,
    FrameId mirrorOfA,
  })
  linkedBaseWithADrawnAttach() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    final canvas = s.requireActiveCut.canvasSize;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final a = rowOf(s, base).frames.single.id;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(s.requireActiveCut, base, a),
      ink(canvas, 200),
    );
    s.copyFrameAtCurrentFrame();
    s.selectFrameIndex(5);
    s.pasteLinkedFrameAtCurrentFrame();
    expect(rowOf(s, base).timeline[5]?.frameId, a, reason: '⛔전제: a link');

    s.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!.id;
    final mirrorOfA = rowOf(s, attach).baseFrameLinks[a]!;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(s.requireActiveCut, attach, mirrorOfA),
      ink(canvas, 90),
    );
    s.selectLayer(base);
    return (s: s, base: base, attach: attach, a: a, mirrorOfA: mirrorOfA);
  }

  test('링크 독립 on a base block: the attach row keeps the picture it had '
      'there, as a mirror of the new cel — and the other showing keeps its '
      'own', () {
    final fixture = linkedBaseWithADrawnAttach();
    final (:s, :base, :attach, :a, :mirrorOfA) = fixture;
    s.selectFrameIndex(5);
    expect(TimelineToolbarPanelContext(s).canUnlink, isTrue, reason: '⛔전제');
    final steps = s.historyManager.undoCount;

    TimelineToolbarPanelContext(s).unlink();

    final copy = rowOf(s, base).timeline[5]!.frameId!;
    expect(copy, isNot(a), reason: '⛔전제: the base block got its own cel');
    expect(shadeOf(s, base, copy), 200, reason: '⛔전제: F-62, the base');

    final mirrorOfCopy = rowOf(s, attach).baseFrameLinks[copy];
    expect(mirrorOfCopy, isNotNull, reason: 'the new cel is mirrored');
    expect(mirrorOfCopy, isNot(mirrorOfA), reason: 'by a cel of its own');
    expect(
      mirrorOfCopy,
      attachedMirrorCelId(attach, copy),
      reason: 'under the id the settle gives a mirror — nothing minted twice',
    );
    expect(
      rowOf(s, attach).frames.where((frame) => frame.id == mirrorOfCopy),
      hasLength(1),
    );
    expect(
      shadeOf(s, attach, mirrorOfCopy!),
      90,
      reason: '「어태치 싱크 레이어 그림도 남아있도록」',
    );
    expect(shadeOf(s, attach, mirrorOfA), 90, reason: 'the source keeps its');
    expect(
      rowOf(s, attach).baseFrameLinks[a],
      mirrorOfA,
      reason: 'and the other showing still mirrors A',
    );
    expect(s.historyManager.undoCount, steps + 1, reason: 'ONE undo step');

    s.undo();
    expect(rowOf(s, base).timeline[5]?.frameId, a);
    expect(
      rowOf(s, attach).baseFrameLinks.containsKey(copy),
      isFalse,
      reason: 'one undo takes the mirror back with the cel',
    );
    expect(
      rowOf(s, attach).frames.any((frame) => frame.id == mirrorOfCopy),
      isFalse,
    );
  });

  test('the mirrors are minted under the row the settle mints under — a '
      'linked row\'s group — and a base cel the row never mirrored is left '
      'to the settle', () {
    const mirrored = FrameId('a');
    const unmirrored = FrameId('b');
    const mirror = FrameId('attach-mirror-row-a');
    final attached = Layer(
      id: const LayerId('row'),
      name: 'A+1',
      frames: [Frame(id: mirror, duration: 1, strokes: const [])],
      timeline: const {},
      baseFrameLinks: {mirrored: mirror},
    );

    final copies = mirrorCopiesFor(
      attachedRows: [attached],
      baseMinted: {
        mirrored: const FrameId('a-copy'),
        unmirrored: const FrameId('b-copy'),
      },
      mintedUnder: (_) => const LayerId('canonical'),
    );

    final born = attachedMirrorCelId(
      const LayerId('canonical'),
      const FrameId('a-copy'),
    );
    expect(copies, hasLength(1));
    expect(copies.single.layerId, attached.id);
    expect(copies.single.born.map((frame) => frame.id), [born]);
    expect(copies.single.baseLinks, {const FrameId('a-copy'): born});
    expect(copies.single.minted, {mirror: born});

    expect(
      mirrorCopiesFor(
        attachedRows: [attached],
        baseMinted: {unmirrored: const FrameId('b-copy')},
        mintedUnder: (row) => row.id,
      ),
      isEmpty,
      reason: 'a row that gains nothing is no rider',
    );
  });

  test('every synced attach row keeps its OWN picture — and a mirror nobody '
      'drew on is copied as it is, empty', () {
    final fixture = linkedBaseWithADrawnAttach();
    final (:s, :base, :attach, :a, :mirrorOfA) = fixture;
    // A second synced row, never drawn on.
    s.folders.addAttachedLayer(AttachedPlacement.below);
    final bare = s.activeLayer!.id;
    final bareMirror = rowOf(s, bare).baseFrameLinks[a]!;
    expect(shadeOf(s, bare, bareMirror), isNull, reason: '⛔전제');
    s.selectLayer(base);
    s.selectFrameIndex(5);

    TimelineToolbarPanelContext(s).unlink();

    final copy = rowOf(s, base).timeline[5]!.frameId!;
    final bareCopy = rowOf(s, bare).baseFrameLinks[copy];
    expect(bareCopy, isNotNull);
    expect(shadeOf(s, bare, bareCopy!), isNull);
    expect(
      shadeOf(s, attach, rowOf(s, attach).baseFrameLinks[copy]!),
      90,
      reason: 'each row its own picture',
    );
  });
}
