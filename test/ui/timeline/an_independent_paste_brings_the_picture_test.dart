import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★AN INDEPENDENT PASTE BRINGS THE PICTURE.
///
/// 유저 (F-62): 「프레임 복사후 독립붙여넣기시, **그림이 복제되지않음.** 그림
/// 복제되고 이름만 없는상태로 되도록」.
///
/// ⛔`duplicateFrameContent` deep-copies `strokes` and its doc says 「the copy
/// owes the source nothing afterwards」 — which reads as 「everything came」
/// and is not. The PICTURE is not a `Frame` field: pixels live in
/// `brushFrameStore` under a key that carries the frame ID, so a minted cel
/// resolved to an empty surface and the pasted block came out blank.
///
/// ⚠️Surfaces are immutable with structural tile sharing, so storing the same
/// object under the new key IS the copy — the same reasoning
/// `UnlinkLayerCommand` states where it forks a linked member's cels.
void main() {
  /// ⚠️Built at the CUT's canvas size, not a convenient 4x4: the resolver
  /// asks the store for that size, and a surface of another shape does not
  /// come back. 🧪The first version of this test stored 4x4 and died on its
  /// own premise — which is the premise assertion doing its job.
  BitmapSurface ink(CanvasSize canvasSize) {
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..fillRange(0, 16, 255);
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile).putTiles([
      (coord: TileCoord(x: 0, y: 0), tile: BitmapTile(size: tile, pixels: pixels)),
    ]);
  }

  ({EditorSessionManager session, LayerId from, LayerId to}) twoRows() {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final from = session.activeLayerId!;
    session.layerStack.addLayerOfKind(LayerKind.animation);
    final to = session.activeLayerId!;

    session.selectLayer(from);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    // Put a real picture on it — the whole point of the card.
    final layer = session.layers.firstWhere((l) => l.id == from);
    session.renderCaches.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(
        session.activeCutOrNull!,
        from,
        layer.frames.single.id,
      ),
      ink(session.activeCutOrNull!.canvasSize),
    );
    return (session: session, from: from, to: to);
  }

  /// The cel exposed at frame 0 of [layerId], read the way the existing
  /// paste tests read it — the timeline names the id, the layer holds the cel.
  Frame? exposedAtZero(EditorSessionManager s, LayerId layerId) {
    final layer = s.layers.firstWhere((l) => l.id == layerId);
    final id = layer.timeline[0]?.frameId;
    if (id == null) {
      return null;
    }
    return layer.frames.where((f) => f.id == id).firstOrNull;
  }

  bool hasPicture(EditorSessionManager s, LayerId layerId) {
    final layer = s.layers.firstWhere((l) => l.id == layerId);
    final frame = exposedAtZero(s, layerId);
    if (frame == null) {
      return false;
    }
    return s.brushSurfaceForLayerFrame(layer, frame)?.tiles.isNotEmpty ?? false;
  }

  test('🚨★★★the pasted block carries the drawing, into another row', () {
    final f = twoRows();
    expect(
      hasPicture(f.session, f.from),
      isTrue,
      reason: '⛔premise: the SOURCE actually has a picture — a test that '
          'pasted an empty cel would pass while measuring nothing',
    );

    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();
    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);
    f.session.pasteIndependentFrameAtCurrentFrame();

    expect(
      hasPicture(f.session, f.to),
      isTrue,
      reason: '🚨「그림 복제되고」 — the picture is the thing being pasted',
    );
  });

  /// 🚨F-161 (유저 2026-09-17): 「복사는 항상 언제든 들고있게. 컷2의
  /// 레이어에서 붙여넣기 가능」. Cut 2's store has no picture under cut 1's
  /// key, so the picture has to travel on the board itself.
  test('🚨the picture comes along into ANOTHER cut', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();

    final cut1 = f.session.activeCutId;
    f.session.cutVerbs.createCut();
    expect(f.session.activeCutId, isNot(cut1), reason: 'premise: in cut 2');
    final target = f.session.activeLayerId!;
    f.session.selectFrameIndex(0);
    f.session.pasteIndependentFrameAtCurrentFrame();

    expect(
      hasPicture(f.session, target),
      isTrue,
      reason: '「컷2의 레이어에서 붙여넣기」 — the drawing, not an empty cel',
    );
  });

  test('the board holds the picture as it was COPIED — drawn over '
      'afterwards, the paste is still the copy', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();

    final cut = f.session.activeCutOrNull!;
    final source = f.session.layers.firstWhere((l) => l.id == f.from);
    final key = f.session.brushFrameKeyForCut(
      cut,
      f.from,
      source.frames.single.id,
    );
    final store = f.session.renderCaches.brushFrameStore;
    final asCopied = store.bakedSurfaceOrNull(key)!;
    store.storeBakedSurface(
      key,
      ink(cut.canvasSize).putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: 256, pixels: Uint8List(256 * 256 * 4)),
        ),
        (
          coord: TileCoord(x: 1, y: 0),
          tile: BitmapTile(
            size: 256,
            pixels: Uint8List(256 * 256 * 4)..fillRange(0, 16, 255),
          ),
        ),
      ]),
    );
    expect(
      identical(store.bakedSurfaceOrNull(key), asCopied),
      isFalse,
      reason: 'premise: the source was drawn over after the copy',
    );

    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);
    f.session.pasteIndependentFrameAtCurrentFrame();

    final target = f.session.layers.firstWhere((l) => l.id == f.to);
    expect(
      identical(
        f.session.brushSurfaceForLayerFrame(
          target,
          exposedAtZero(f.session, f.to)!,
        ),
        asCopied,
      ),
      isTrue,
      reason: 'a clipboard holds what was copied, not what the source '
          'became — 「보통 프로그램이 그러니까」',
    );
  });

  test('⛔and it is INDEPENDENT — a new cel, unnamed', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();
    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);
    f.session.pasteIndependentFrameAtCurrentFrame();

    final source = f.session.layers.firstWhere((l) => l.id == f.from);
    final born = exposedAtZero(f.session, f.to)!;
    expect(
      born.id,
      isNot(source.frames.single.id),
      reason: 'a LINKED paste points at the same cel; this one mints',
    );
    expect(born.name, isNull, reason: '「이름만 없는상태로」');
  });

  /// The BLOCK DUPLICATE mints through the same kernel, so 「그림 복제되고
  /// 이름만 없는상태로」 is its law too. It used to run a hand-written second
  /// copy of the mint that threw the minted map away, so the twin came out
  /// blank — the same F-62 damage on the verb next door.
  test('🚨★★★an independent BLOCK DUPLICATE carries the drawing too', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    expect(
      hasPicture(f.session, f.from),
      isTrue,
      reason: '⛔premise: the source row actually has a picture',
    );

    f.session.frameVerbs.duplicateActiveBlock(linked: false);

    final layer = f.session.layers.firstWhere((l) => l.id == f.from);
    final bornId = layer.timeline[1]?.frameId;
    expect(bornId, isNotNull, reason: 'the copy landed after the block');
    expect(
      bornId,
      isNot(layer.timeline[0]?.frameId),
      reason: 'independent: a new cel, not the source',
    );
    final born = layer.frames.firstWhere((frame) => frame.id == bornId);
    expect(born.name, isNull, reason: '「이름만 없는상태로」');
    expect(
      f.session.brushSurfaceForLayerFrame(layer, born)?.tiles.isNotEmpty,
      isTrue,
      reason: '🚨「그림 복제되고」 — the duplicate is the picture, not an id',
    );
  });

  test('⛔a LINKED block duplicate still copies nothing', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.frameVerbs.duplicateActiveBlock(linked: true);

    final layer = f.session.layers.firstWhere((l) => l.id == f.from);
    expect(layer.frames.length, 1, reason: 'nothing was minted');
    expect(layer.timeline[1]?.frameId, layer.timeline[0]?.frameId);
  });

  test('⛔a LINKED paste copies nothing — it points at the cel that exists', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();
    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);
    if (!f.session.canPasteLinkedFrameAtCurrentFrame) {
      return; // A linked paste across rows is a different gate; not this test.
    }
    f.session.pasteLinkedFrameAtCurrentFrame();

    final source = f.session.layers.firstWhere((l) => l.id == f.from);
    expect(
      exposedAtZero(f.session, f.to)?.id,
      source.frames.single.id,
      reason: '⛔the same cel is what 「링크」 means — nothing was minted, so '
          'nothing had to be copied',
    );
  });
}
