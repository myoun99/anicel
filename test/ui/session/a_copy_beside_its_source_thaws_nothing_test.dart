import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/pill_row_clipboard.dart';

/// 🗣️Card `timeline-copy-thaws-every-cel` (유저 2026-11-04: 「FU파일에서
/// 타임라인복제해서 사용하려하는데, 메모리가 3000mb까지 폭증」): a copy
/// made beside its source read every cel it copied as a use, so each one
/// kept in the saved file thawed hot. A copy takes its source's picture in
/// the tier the store keeps it in ([BrushFrameStore.copyCel]) — a
/// duplicated block, row, cut and timeline, and a cel or a row given cels
/// of its own (링크 독립).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EditorSessionManager session;
  late BrushFrameStore store;
  late int drawnRowAt;

  final ink = Uint8List(256 * 256 * 4);
  for (var at = 0; at < ink.length; at += 1) {
    ink[at] = (at * 31 + 7) & 0xFF;
  }

  Layer drawnRowOf(Cut cut) => cut.layers[drawnRowAt];

  BrushFrameKey keyOf(Cut cut, LayerId row, FrameId cel) =>
      session.brushFrameKeyForCut(cut, row, cel);

  /// What [key] shows, read as a render reads it — nothing thawed.
  Uint8List? shown(BrushFrameKey key) => store
      .bakedSurfaceOrNull(key, read: CelRead.look)
      ?.tiles[TileCoord(x: 0, y: 0)]
      ?.pixels;

  /// The drawing kept in the saved file, and nothing else in the store — as
  /// an opened project keeps it.
  late void Function() keepTheDrawing;

  setUp(() {
    session = EditorSessionManager(initialProject: newUntitledProject());
    store = session.renderCaches.brushFrameStore;
    final cut = session.requireActiveCut;
    final row = session.activeLayer!;
    drawnRowAt = cut.layers.indexOf(row);
    final drawn = keyOf(cut, row.id, row.frames.single.id);
    keepTheDrawing = () {
      keepInAFile(store, {
        drawn: BitmapSurface(
          canvasSize: cut.canvasSize,
          tileSize: 256,
          tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 256, pixels: ink)},
        ),
      });
      expect(store.hotBakedBytes, 0, reason: 'fixture: kept, not hot');
    };
    keepTheDrawing();
  });
  tearDown(() => session.dispose());

  /// The cel [row] holds now that it did not hold before [step].
  FrameId celMintedBy(void Function() step) {
    final before = {
      for (final cel in drawnRowOf(session.requireActiveCut).frames) cel.id,
    };
    step();
    return drawnRowOf(
      session.requireActiveCut,
    ).frames.map((cel) => cel.id).where((id) => !before.contains(id)).single;
  }

  void expectThawsNothing(BrushFrameKey copy) {
    expect(shown(copy), ink, reason: 'the copy shows its source\'s picture');
    expect(store.hotBakedBytes, 0, reason: 'a kept cel thawed hot');
  }

  test('a duplicated block', () {
    final copy = celMintedBy(
      () => session.frameVerbs.duplicateActiveBlock(linked: false),
    );
    final cut = session.requireActiveCut;
    expectThawsNothing(keyOf(cut, drawnRowOf(cut).id, copy));
  });

  test('a cel given a copy of its own (링크 독립)', () {
    session.frameVerbs.duplicateActiveBlock(linked: true);
    final copy = celMintedBy(session.cells.unlinkCells);
    final cut = session.requireActiveCut;
    expectThawsNothing(keyOf(cut, drawnRowOf(cut).id, copy));
  });

  test('a duplicated row', () {
    final before = {for (final row in session.requireActiveCut.layers) row.id};
    session.layerVerbs.duplicateActiveLayer();
    final cut = session.requireActiveCut;
    final copy = cut.layers.where((row) => !before.contains(row.id)).single;
    expectThawsNothing(keyOf(cut, copy.id, copy.frames.single.id));
  });

  test('a row given cels of its own (링크 독립 of a row)', () {
    final before = {for (final row in session.requireActiveCut.layers) row.id};
    linkDuplicateActiveRow(session);
    final linked = session.requireActiveCut.layers
        .where((row) => !before.contains(row.id))
        .single;
    expect(session.layerVerbs.isLayerLinked(linked.id), isTrue);
    // The board took the rows by value (F-161), reading the drawing.
    keepTheDrawing();

    session.layerVerbs.unlinkLayers([linked.id]);

    expect(session.layerVerbs.isLayerLinked(linked.id), isFalse);
    final cut = session.requireActiveCut;
    final copy = cut.layers.firstWhere((row) => row.id == linked.id);
    expectThawsNothing(keyOf(cut, copy.id, copy.frames.single.id));
  });

  test('a duplicated cut', () {
    final source = session.requireActiveCut;
    session.cutVerbs.duplicateActiveCut();
    final copy = session.requireActiveCut;
    expect(copy.id, isNot(source.id), reason: 'the copy is where you stand');
    final row = drawnRowOf(copy);
    expectThawsNothing(keyOf(copy, row.id, row.frames.single.id));
  });

  test('a duplicated timeline', () {
    final source = session.requireActiveCut;
    session.timelineVerbs.duplicateTimeline(
      session.repository.requireProject().currentTimeline.id,
      '',
    );
    final copy = session.requireActiveCut;
    expect(copy.id, isNot(source.id), reason: 'the copy is opened');
    final row = drawnRowOf(copy);
    expectThawsNothing(keyOf(copy, row.id, row.frames.single.id));
  });
}
