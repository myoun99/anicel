import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart'
    show conteInkRowKey;
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart'
    show timesheetInkPageKey;
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

  /// [ink] in the top-left tile of a surface [canvasSize] wide.
  BitmapSurface inked(CanvasSize canvasSize) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: 256,
    tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 256, pixels: ink)},
  );

  /// What [key] shows in [of] (the cels' store when left out), read as a
  /// render reads it — nothing thawed.
  Uint8List? shown(BrushFrameKey key, [BrushFrameStore? of]) => (of ?? store)
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
      keepInAFile(store, {drawn: inked(cut.canvasSize)});
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

  void expectThawsNothing(BrushFrameKey copy, [BrushFrameStore? of]) {
    expect(
      shown(copy, of),
      ink,
      reason: 'the copy shows its source\'s picture',
    );
    expect((of ?? store).hotBakedBytes, 0, reason: 'a kept cel thawed hot');
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

  // The copies an undo empties are the ones it made (`LinkPartCopies`): a
  // cel that keeps no picture was copied nothing, and emptying its key would
  // mark a cel unsaved that nothing touched.
  test('an undone 링크 독립 of a row empties only the copies it made', () {
    final drawn = drawnRowOf(session.requireActiveCut).frames.single.id;
    final blank = celMintedBy(() {
      session.selectFrameIndex(6);
      session.createDrawingAtCurrentFrame();
    });
    final before = {for (final row in session.requireActiveCut.layers) row.id};
    linkDuplicateActiveRow(session);
    final linked = session.requireActiveCut.layers
        .where((row) => !before.contains(row.id))
        .single
        .id;
    keepTheDrawing();
    expect(store.dirtyCelKeysSinceSave, isEmpty, reason: 'fixture: saved');

    session.layerVerbs.unlinkLayers([linked]);
    session.historyManager.undo();

    final cut = session.requireActiveCut;
    expect(session.layerVerbs.isLayerLinked(linked), isTrue);
    expect(
      store.celKeysOfCut(cut.id),
      isNot(contains(keyOf(cut, linked, drawn))),
      reason: 'the copy it made is emptied',
    );
    expect(
      store.dirtyCelKeysSinceSave,
      isNot(contains(keyOf(cut, linked, blank))),
    );
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

  // The sheets' handwriting is the same 「key A → key B」 copy, kept at the
  // sheet's size whatever the cut's canvas.
  group('the sheets\' handwriting', () {
    const sheet = CanvasSize(width: 512, height: 300);

    test('a duplicated cut\'s timesheet page', () {
      final pages = session.renderCaches.timesheetInkStore;
      final source = session.requireActiveCut;
      keepInAFile(pages, {timesheetInkPageKey(source.id, 0): inked(sheet)});

      session.cutVerbs.duplicateActiveCut();

      final copy = session.requireActiveCut;
      expect(copy.id, isNot(source.id), reason: 'the copy is where you stand');
      expectThawsNothing(timesheetInkPageKey(copy.id, 0), pages);
    });

    /// The drawn block written on under 'ink-src', that writing kept in the
    /// saved file — and, after [step], the one other id its row writes
    /// under.
    String blockHandwritingCopiedBy(void Function() step) {
      final cut = session.requireActiveCut;
      final row = drawnRowOf(cut);
      session.cutCommandCoordinator.updateExposureMemo(
        cutId: cut.id,
        layerId: row.id,
        blockStartIndex: row.timeline.keys.first,
        memo: const ExposureMemo(inkId: 'ink-src'),
      );
      keepInAFile(session.renderCaches.conteInkRowStore, {
        conteInkRowKey(cut.id, 'ink-src'): inked(sheet),
      });
      step();
      return {
        for (final layer in session.requireActiveCut.layers)
          for (final exposure in layer.timeline.values)
            ?exposure.memo?.inkId,
      }.where((id) => id.isNotEmpty && id != 'ink-src').single;
    }

    test('a duplicated block\'s', () {
      final copy = blockHandwritingCopiedBy(
        () => session.frameVerbs.duplicateActiveBlock(linked: false),
      );
      expectThawsNothing(
        conteInkRowKey(session.requireActiveCut.id, copy),
        session.renderCaches.conteInkRowStore,
      );
    });

    test('a duplicated row\'s blocks\'', () {
      final copy = blockHandwritingCopiedBy(
        session.layerVerbs.duplicateActiveLayer,
      );
      expectThawsNothing(
        conteInkRowKey(session.requireActiveCut.id, copy),
        session.renderCaches.conteInkRowStore,
      );
    });
  });
}
