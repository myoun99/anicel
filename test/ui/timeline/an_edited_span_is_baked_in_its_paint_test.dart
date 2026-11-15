/// These cases raster tiles for real and wait for landings off-frame — the
/// bound the other store files state, for their reason (under load the
/// 30s default dies bare).
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/text/laid_out_glyph.dart'
    show debugGlyphsLaidOut;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart';

import '../../helpers/a_word_that_waits.dart';
import '../../helpers/exposure_of.dart';
import '../../helpers/frame_name_of.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/tiles_drawn_off_the_paint.dart';
import '../../helpers/tiles_laid.dart';
import 'tile_store_idle.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨F-314 (유저 2026-10-08: 「코마 바꿀때 +나 N이나 코마텍스트 이런 위젯이랑
/// 블록이랑 위치 어긋나는 프레임 1프레임정도 있거나 하는데 1프레임도 위치
/// 안어긋나게. 움직일 프레임에서 통합해서 같이 움직이도록」): A SPAN AN EDIT
/// MOVED IS BAKED IN THE PAINT THAT ASKS FOR IT.
///
/// The row's chrome — the +, the N/H/R tag, the grips — follows an edit in
/// the frame the edit lands in. The tile followed it a frame later: the
/// store showed the tile from before the edit while the fresh one went up
/// off-frame, and on the device every step of a drag did (8 of 8, Surface,
/// 10-25). It is drawn on the engine inside the ask now — a word never seen
/// before with it, which the engine bakes there
/// (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q3 · Q4, 유저
/// 2026-11-15); the one wait left is a word that is not the engine's to
/// set, which Flutter rasters ([waits]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);
  readTheEnginesFacesFirst();

  final store = TimelineGridTileStore.instance;

  /// [name] as a word its tile waits for: Flutter's to raster.
  String waits(String name) => '$name$aLetterNoBundledFaceHas';

  /// A row [frames] long with a block [length] long at every fourth frame,
  /// its cel named [name] (none: the block's head is a mark) — four frames
  /// to a span at 128px.
  Layer rowLayer(
    String id, {
    int frames = 4,
    int length = 2,
    String? name = 'A',
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: [
      Frame(id: FrameId('$id-f'), duration: 1, strokes: const [], name: name),
    ],
    timeline: {
      for (var start = 0; start < frames; start += 4)
        start: TimelineExposure.drawing(FrameId('$id-f'), length: length),
    },
  );

  _CountingSubstrates painterFor(
    Layer layer, {
    int frames = 4,
    double crossAxisExtent = 28,
  }) => _CountingSubstrates(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: 128,
      frameEndIndexExclusive: frames,
    ),
    crossAxisExtent: crossAxisExtent,
    exposureStateForLayer: exposureOf,
    frameNameForLayer: frameNameOf,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    tileStore: store,
    substrateGeneration: 'f314',
  );

  /// What a paint asks of the store for the row's first span.
  TimelineGridTilePicture? ask(TimelineRowCellsPainter painter) =>
      store.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );

  /// What a repaint does: the painter's own paint, which asks the store for
  /// every span it shows — on a grid's screen, where its tiles are laid.
  void paintRow(TimelineRowCellsPainter painter, int frames) {
    final recorder = ui.PictureRecorder();
    tilesLaidBy(
      () => painter.paint(Canvas(recorder), Size(frames * 128.0, 28)),
    );
    recorder.endRecording().dispose();
  }

  /// A painter shown on screen: attached, it hears its row's landings.
  void show(TimelineRowCellsPainter painter, VoidCallback onLanding) {
    painter.addListener(onLanding);
    addTearDown(() => painter.removeListener(onLanding));
  }

  /// The first span of [painter]'s row, cold: baked in the ask, as a span
  /// nothing stands in for is.
  Future<TimelineGridTilePicture> landed(
    TimelineRowCellsPainter painter,
  ) async {
    final tile = ask(painter);
    expect(tile, isNotNull, reason: 'premise: cold, baked in the ask');
    return tile!;
  }

  var landings = 0;
  void countLanding() => landings += 1;

  setUp(() {
    store.clear();
    landings = 0;
    store.revision.addListener(countLanding);
  });

  tearDown(() {
    store.revision.removeListener(countLanding);
    store.clear();
  });

  test('a comma edit is baked in the ask: the fresh tile, drawn in it, the '
      'one before it let go, nothing left for off-frame', () async {
    final before = await landed(painterFor(rowLayer('r')));
    final drawnOff = countTilesDrawnOffThePaint(store);
    final landingsBefore = landings;

    final edited = painterFor(rowLayer('r', length: 3));
    final baked = ask(edited);

    expect(baked, isNotNull);
    expect(
      identical(baked, before),
      isFalse,
      reason: 'the block a step behind its grips: the tile before the edit',
    );
    expect(landings, landingsBefore + 1, reason: 'it landed in the ask');
    expect(before.debugHolds, 0, reason: 'the tile it replaced went');
    expect(store.debugBusy, isFalse, reason: 'nothing left for off-frame');
    expect(ask(edited), same(baked), reason: 'and it shows the edit');
    await tileStoreIdle(store);
    expect(drawnOff(), 0, reason: 'drawn in the ask, none off the paint');
  });

  // The ink an ask tells a moved span by is the ink its bake writes.
  // ↩️It was written again by the bake (a-grid-row-paints-its-cells-on-a-
  // canvas-beside-its-tiles, 11-15).
  test('a span its ink moved is baked from the substrate and the ink the ask '
      'read', () async {
    await landed(painterFor(rowLayer('r')));
    final written = store.debugInksWritten;
    final edited = painterFor(rowLayer('r', name: null));

    final baked = ask(edited);

    expect(baked, isNotNull, reason: 'premise: baked in the ask');
    expect(edited.substratesAnswered, 1);
    expect(store.debugInksWritten, written + 1);
  });

  test('the tile baked in the ask is the one drawn off the paint, to the '
      'last byte', () async {
    Uint8List bytesOf(TimelineGridTilePicture tile) => tile.picture.read();

    // A head with no name is a mark: its edges, the X's and the paper's
    // rounded corners are the partly clear pixels the two could part on.
    await landed(painterFor(rowLayer('r', name: null)));
    final baked = ask(painterFor(rowLayer('r', name: null, length: 3)))!;
    expect(landings, 2, reason: 'premise: baked in the ask');

    // The same cells on a row of their own, warmed: drawn off the paint.
    final twin = painterFor(rowLayer('twin', name: null, length: 3));
    final drawnOff = countTilesDrawnOffThePaint(store);
    store.warmAhead(
      painter: twin,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    await tileStoreIdle(store);
    expect(drawnOff(), 1, reason: 'premise: drawn off the paint');
    final offThePaint = bytesOf(ask(twin)!);
    var partlyClear = 0;
    for (var alpha = 3; alpha < offThePaint.length; alpha += 4) {
      if (offThePaint[alpha] != 0 && offThePaint[alpha] != 255) {
        partlyClear += 1;
      }
    }
    expect(partlyClear, greaterThan(0), reason: 'premise: edges to part on');

    expect(bytesOf(baked), offThePaint);
  });

  // 🗣️a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q3 · Q4
  // (유저 2026-11-15: 「(다) 글자도 엔진이 그 자리에서 굽는다」 · 「그대로 간다
  // — 격자 칸 글자는 엔진이 굽는다」). ↩️Such a word stood the tile before it
  // in while Flutter rastered it and the bake read it back.
  test('a word never seen before is baked in the ask that sets it, by the '
      'engine — the fresh tile, nothing left for off-frame', () async {
    final before = await landed(painterFor(rowLayer('r')));
    final drawnOff = countTilesDrawnOffThePaint(store);
    final landingsBefore = landings;
    final wordsBefore = store.debugWordsBakedOnTheEngine;
    final laidOutBefore = debugGlyphsLaidOut;

    final renamed = painterFor(rowLayer('r', name: 'Q7'));
    final baked = ask(renamed);

    expect(baked, isNotNull);
    // 🔬A layout was 50–100 µs of what a new name cost its frame (the test
    // VM, 11-15), and the bake laid the word out a second time.
    expect(
      debugGlyphsLaidOut,
      laidOutBefore + 1,
      reason:
          'laid out once, where the span sets it: the bake on the engine '
          'reads that painter',
    );
    expect(
      identical(baked, before),
      isFalse,
      reason: 'the tile before the rename stood in for a frame',
    );
    expect(landings, landingsBefore + 1, reason: 'it landed in the ask');
    expect(
      store.debugWordsBakedOnTheEngine,
      wordsBefore + 1,
      reason: 'the one word the rename set, baked once',
    );
    expect(store.debugBusy, isFalse, reason: 'nothing left for off-frame');
    expect(ask(renamed), same(baked), reason: 'and it shows the rename');
    expect(
      store.debugWordsBakedOnTheEngine,
      wordsBefore + 1,
      reason: 'a word baked is kept',
    );
    await tileStoreIdle(store);
    expect(drawnOff(), 0, reason: 'drawn in the ask, none off the paint');
  });

  // ⏳A word with a letter none of the bundled faces has is Flutter's to
  // raster (`bakeWordOnEngine`), till the person says what it is to be
  // (the same card's Q5): the wait every new word made till 11-15.
  test('a word that is not the engine\'s to set stands the tile before it '
      'in while Flutter\'s raster is read back, and lands off-frame — once '
      'baked, the next edit is baked in its ask', () async {
    final before = await landed(painterFor(rowLayer('r')));
    final wordsBefore = store.debugWordsBakedOnTheEngine;

    final renamed = painterFor(rowLayer('r', name: waits('Q7')));
    expect(
      ask(renamed),
      same(before),
      reason: 'its bake reads the word back, which an ask cannot wait for',
    );
    expect(store.debugBusy, isTrue, reason: 'the word and its tile go up');
    await tileStoreIdle(store);
    expect(
      store.debugWordsBakedOnTheEngine,
      wordsBefore,
      reason: 'the engine would have set its emoji as an empty box',
    );
    final fresh = ask(renamed);
    expect(fresh, isNotNull);
    expect(identical(fresh, before), isFalse, reason: 'the fresh one landed');

    final landingsBefore = landings;
    final again = painterFor(rowLayer('r', name: waits('Q7'), length: 3));
    final baked = ask(again);
    expect(identical(baked, fresh), isFalse);
    expect(landings, landingsBefore + 1, reason: 'the word is baked now');
    expect(store.debugBusy, isFalse);
  });

  test('a raster in flight when an ask bakes the span lands nothing over '
      'it — the ask is the newer', () async {
    await landed(painterFor(rowLayer('r')));
    final held = holdTilesDrawnOffThePaint(store);

    // A word that waits: the ask stands the old tile in and a drain takes
    // it up, its drawing held here.
    ask(painterFor(rowLayer('r', name: waits('Z9'))));
    expect(await pollUntil(() => held.length == 1), isTrue, reason: 'premise');

    // A later edit back to words already baked: baked in its ask.
    final latest = painterFor(rowLayer('r', length: 3));
    final baked = ask(latest)!;

    final live = TimelineGridTilePicture.debugLive;
    held.single.complete();
    await tileStoreIdle(store);
    expect(
      ask(latest),
      same(baked),
      reason: 'the drain\'s raster, of an older ask, landed over it',
    );
    expect(baked.debugHolds, isPositive);
    expect(
      TimelineGridTilePicture.debugLive,
      live,
      reason: 'the tile the drain drew for nothing is freed',
    );
  });

  test('an ask that bakes the span takes it off the queue — the older ask '
      'queued for it lands nothing after', () async {
    await landed(painterFor(rowLayer('r')));
    // A word that waits: stood in, and queued for a drain.
    ask(painterFor(rowLayer('r', name: waits('Y3'))));
    expect(store.debugBusy, isTrue, reason: 'premise: queued');

    // In the same turn, an edit back to words already baked.
    final latest = painterFor(rowLayer('r', length: 3));
    final baked = ask(latest)!;
    await tileStoreIdle(store);
    expect(ask(latest), same(baked), reason: 'the queued ask landed over it');
  });

  test('an ask that bakes the span takes it off a warm-up — the span asked '
      'for past a window\'s edge is not baked again after', () async {
    await landed(painterFor(rowLayer('r')));
    final latest = painterFor(rowLayer('r', length: 3));
    store.warmAhead(
      painter: latest,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    final baked = ask(latest)!;
    await tileStoreIdle(store);
    expect(ask(latest), same(baked), reason: 'the warm-up baked it again');
  });

  test('a row the queue turned away hears its tile when the store comes back '
      'to it and bakes it in that ask', () async {
    // Two spans, landed; then renamed to a word that waits ([waits]), so
    // both are stood in and queued — and thirty-two spans of a row that
    // sets the same word, queued after them, turn both away. The filler's
    // first raster bakes the word.
    final row = painterFor(rowLayer('r', frames: 8), frames: 8);
    void repaint() {}
    show(row, repaint);
    paintRow(row, 8);
    await tileStoreIdle(store);

    final renamed = painterFor(
      rowLayer('r', frames: 8, name: waits('W5')),
      frames: 8,
    );
    var heard = 0;
    row.removeListener(repaint);
    show(renamed, () => heard += 1);
    final filler = painterFor(
      rowLayer('filler', frames: 128, name: waits('W5')),
      frames: 128,
    );
    final drawnOff = countTilesDrawnOffThePaint(store);
    paintRow(renamed, 8);
    paintRow(filler, 128);
    expect(store.debugBusy, isTrue, reason: 'premise');
    await tileStoreIdle(store);

    expect(drawnOff(), 32, reason: 'the filler\'s alone: the row was baked in '
        'the ask the store came back with');
    expect(heard, greaterThan(0), reason: 'nothing else would repaint it');
    paintRow(renamed, 8);
    expect(store.debugBusy, isFalse, reason: 'its spans show the rename');
  });

  test('a row the store comes back to with nothing baked in that ask is not '
      'repainted for it — its landings repaint it, once each', () async {
    // Two cold spans whose word waits, never baked, turned away by
    // thirty-two queued after them for a word of their own: the store comes
    // back to them with their word still unbaked, and queues them.
    final row = painterFor(
      rowLayer('r', frames: 8, name: waits('V1')),
      frames: 8,
    );
    var repaints = 0;
    show(row, () => repaints += 1);
    final filler = painterFor(
      rowLayer('filler', frames: 128, name: waits('V2')),
      frames: 128,
    );
    paintRow(row, 8);
    paintRow(filler, 128);
    expect(store.debugBusy, isTrue, reason: 'premise: queued');
    await tileStoreIdle(store);

    expect(repaints, 2, reason: 'a repaint of a row with cold spans is the '
        'classic paint again (I-22 ③) — for nothing new, here');
  });

  test('a stand-in is a tile of the span\'s own size — a taller row, or a '
      'span the axis cut shorter, keeps the classic paint while its word is '
      'waited for', () async {
    await landed(painterFor(rowLayer('tall')));
    final taller = painterFor(
      rowLayer('tall', name: waits('T1')),
      crossAxisExtent: 40,
    );
    expect(ask(taller), isNull, reason: 'a 28px tile stretched over 40px');

    await landed(painterFor(rowLayer('short')));
    final shorter = painterFor(rowLayer('short', name: waits('T2')), frames: 3);
    expect(
      store.tileFor(
        painter: shorter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 3,
        devicePixelRatio: 1.0,
      ),
      isNull,
      reason: 'four cells\' tile squeezed into three',
    );
  });
}

/// A row's painter that counts the substrates it answers
/// ([TimelineRowCellsPainter.substrateIn]) — however the store asks.
final class _CountingSubstrates extends TimelineRowCellsPainter {
  _CountingSubstrates({
    required super.layer,
    required super.geometry,
    required super.crossAxisExtent,
    required super.exposureStateForLayer,
    required super.frameNameForLayer,
    required super.colorScheme,
    required super.baseTextStyle,
    required super.tileStore,
    required super.substrateGeneration,
  });

  int substratesAnswered = 0;

  @override
  TimelineRowSubstrate substrateIn(int from, int to) {
    substratesAnswered += 1;
    return super.substrateIn(from, to);
  }
}
