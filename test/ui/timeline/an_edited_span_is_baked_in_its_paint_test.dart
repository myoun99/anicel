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
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

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
/// 10-25). It is drawn on the engine inside the ask now; the one wait left
/// is a word never baked before, whose bake reads its faces first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);

  final store = TimelineGridTileStore.instance;

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

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    int frames = 4,
    double crossAxisExtent = 28,
  }) => TimelineRowCellsPainter(
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

  /// The first span of [painter]'s row, cold, landed off-frame.
  Future<TimelineGridTilePicture> landed(
    TimelineRowCellsPainter painter,
  ) async {
    expect(ask(painter), isNull, reason: 'premise: cold');
    await tileStoreIdle(store);
    return ask(painter)!;
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

  test('the tile baked in the ask is the one drawn off the paint, to the '
      'last byte', () async {
    Uint8List bytesOf(TimelineGridTilePicture tile) => tile.picture.read();

    // A head with no name is a mark: its edges, the X's and the paper's
    // rounded corners are the partly clear pixels the two could part on.
    await landed(painterFor(rowLayer('r', name: null)));
    final baked = ask(painterFor(rowLayer('r', name: null, length: 3)))!;
    expect(landings, 2, reason: 'premise: baked in the ask');

    // The same cells on a row of their own, cold: drawn off the paint.
    final offThePaint = bytesOf(
      await landed(painterFor(rowLayer('twin', name: null, length: 3))),
    );
    var partlyClear = 0;
    for (var alpha = 3; alpha < offThePaint.length; alpha += 4) {
      if (offThePaint[alpha] != 0 && offThePaint[alpha] != 255) {
        partlyClear += 1;
      }
    }
    expect(partlyClear, greaterThan(0), reason: 'premise: edges to part on');

    expect(bytesOf(baked), offThePaint);
  });

  test('a word never baked before stands the tile before it in while it '
      'bakes, and lands off-frame — once baked, the next edit is baked in '
      'its ask', () async {
    final before = await landed(painterFor(rowLayer('r')));

    final renamed = painterFor(rowLayer('r', name: 'Q7'));
    expect(
      ask(renamed),
      same(before),
      reason: 'its bake reads the word back, which an ask cannot wait for',
    );
    expect(store.debugBusy, isTrue, reason: 'the word and its tile go up');
    await tileStoreIdle(store);
    final fresh = ask(renamed);
    expect(fresh, isNotNull);
    expect(identical(fresh, before), isFalse, reason: 'the fresh one landed');

    final landingsBefore = landings;
    final again = painterFor(rowLayer('r', name: 'Q7', length: 3));
    final baked = ask(again);
    expect(identical(baked, fresh), isFalse);
    expect(landings, landingsBefore + 1, reason: 'the word is baked now');
    expect(store.debugBusy, isFalse);
  });

  test('a raster in flight when an ask bakes the span lands nothing over '
      'it — the ask is the newer', () async {
    await landed(painterFor(rowLayer('r')));
    final held = holdTilesDrawnOffThePaint(store);

    // A new word: the ask stands the old tile in and a drain takes it up,
    // its drawing held here.
    ask(painterFor(rowLayer('r', name: 'Z9')));
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
    // A new word: stood in, and queued for a drain.
    ask(painterFor(rowLayer('r', name: 'Y3')));
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
    // Two spans, landed; then renamed to a word no tile has baked yet, so
    // both are stood in and queued — and thirty-two spans of a row that
    // sets the same word, queued after them, turn both away. The filler's
    // first raster bakes the word.
    final row = painterFor(rowLayer('r', frames: 8), frames: 8);
    void repaint() {}
    show(row, repaint);
    paintRow(row, 8);
    await tileStoreIdle(store);

    final renamed = painterFor(
      rowLayer('r', frames: 8, name: 'W5'),
      frames: 8,
    );
    var heard = 0;
    row.removeListener(repaint);
    show(renamed, () => heard += 1);
    final filler = painterFor(
      rowLayer('filler', frames: 128, name: 'W5'),
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
    // Two cold spans, turned away by thirty-two queued after them: the
    // store comes back to them cold, and queues them.
    final row = painterFor(rowLayer('r', frames: 8), frames: 8);
    var repaints = 0;
    show(row, () => repaints += 1);
    final filler = painterFor(rowLayer('filler', frames: 128), frames: 128);
    paintRow(row, 8);
    paintRow(filler, 128);
    await tileStoreIdle(store);

    expect(repaints, 2, reason: 'a repaint of a row with cold spans is the '
        'classic paint again (I-22 ③) — for nothing new, here');
  });

  test('a stand-in is a tile of the span\'s own size — a taller row, or a '
      'span the axis cut shorter, keeps the classic paint while its new word '
      'bakes', () async {
    await landed(painterFor(rowLayer('tall')));
    final taller = painterFor(
      rowLayer('tall', name: 'T1'),
      crossAxisExtent: 40,
    );
    expect(ask(taller), isNull, reason: 'a 28px tile stretched over 40px');

    await landed(painterFor(rowLayer('short')));
    final shorter = painterFor(rowLayer('short', name: 'T2'), frames: 3);
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
