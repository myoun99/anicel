/// These cases raster tiles for real and wait for them to land, which under
/// a loaded machine crosses the test package's default 30s — see the head of
/// `timeline_grid_tile_store_test.dart` for the bound and the open round.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/straight_rgba_image.dart'
    show debugRawRgbaUploader;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨I-22 ③: A LANDED TILE REPAINTS ITS OWN ROW.
///
/// Every row painter listened to the store's one landing count, so each
/// landing repainted every row — and a row with cold spans repaints them the
/// classic way. A zoom past the stale tiles' reach leaves every visible span
/// of every row cold at once (~480 at 0.8px/frame over 24 rows): measured,
/// the frames after it went on repainting all 24 rows by hand until the last
/// tile landed (p50 84ms, debug).
///
/// Those repaints were also what asked again for the spans the queue's cap
/// had turned away. A row whose every request was turned away has no
/// landing of its own to repaint it, so the store now comes back to it
/// itself once its queue runs dry — with what the row shows then.
///
/// And each of them asked again for the tiles still being rastered, which
/// the store rastered a second time: with a row repainting on every landing
/// of its own, that fed itself (900 rasters of 19 tiles in the third case
/// here, before the store stopped asking twice).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;
  final store = TimelineGridTileStore.instance;

  /// A row [frames] long with a block of two at every fourth frame — four
  /// frames to a span at 24px (`timelineFrameWindowSpanFor`).
  Layer rowLayer(String id, {required int frames}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {
      for (var start = 0; start < frames; start += 4)
        start: TimelineExposure.drawing(FrameId('$id-f'), length: 2),
    },
  );

  TimelineRowCellsPainter painterFor(Layer layer, {required int frames}) =>
      TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: exposureOf,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
        substrateGeneration: 'i22',
      );

  /// What a repaint does: the painter's own paint, which asks the store for
  /// every span it shows and keeps warm.
  void paintRow(TimelineRowCellsPainter painter, int frames) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size(frames * 24.0, 28));
    recorder.endRecording().dispose();
  }

  /// A painter shown on screen: attached, it repaints on what it listens to.
  void show(TimelineRowCellsPainter painter, VoidCallback onRepaint) {
    painter.addListener(onRepaint);
    addTearDown(() => painter.removeListener(onRepaint));
  }

  Future<void> idle() async {
    while (store.debugBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
  });

  test('a landed tile repaints the row it belongs to, and no other', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final a = painterFor(rowLayer('a', frames: 8), frames: 8);
    final b = painterFor(rowLayer('b', frames: 8), frames: 8);
    var aRepaints = 0;
    var bRepaints = 0;
    show(a, () => aRepaints += 1);
    show(b, () => bRepaints += 1);

    paintRow(a, 8);
    expect(store.debugBusy, isTrue, reason: 'premise: its two spans are cold');
    await idle();

    expect(aRepaints, 2, reason: 'each of its landings repaints its row');
    expect(bRepaints, 0, reason: 'and never another row');
  });

  test('a row the queue turned away is come back to once the queue runs dry '
      '— every span each row paints ends up warm', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    // Twenty spans a row: sixty asked for at once, and the queue keeps 32 —
    // the first row's every request is turned away.
    final rows = [
      for (final id in ['r0', 'r1', 'r2'])
        painterFor(rowLayer(id, frames: 80), frames: 80),
    ];
    for (final row in rows) {
      show(row, () => paintRow(row, 80));
    }
    for (final row in rows) {
      paintRow(row, 80);
    }
    await idle();

    for (final row in rows) {
      paintRow(row, 80);
      expect(
        store.debugBusy,
        isFalse,
        reason: '${row.layer.id} found every span it shows warm',
      );
    }
  });

  test('a row turned away that nothing shows any more is not rastered — the '
      'rows still shown are', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final gone = painterFor(rowLayer('gone', frames: 40), frames: 40);
    final shown = painterFor(rowLayer('shown', frames: 40), frames: 40);
    final big = painterFor(rowLayer('big', frames: 128), frames: 128);
    show(shown, () => paintRow(shown, 40));
    show(big, () => paintRow(big, 128));
    // Ten, ten and thirty-two: both rows asked for first are turned away,
    // and the one nothing shows is the first to be come back to.
    paintRow(gone, 40);
    paintRow(shown, 40);
    paintRow(big, 128);
    await idle();

    paintRow(shown, 40);
    expect(store.debugBusy, isFalse, reason: 'the row still shown is warm');
    expect(
      [
        for (final (start, end) in gone.tileSpans)
          store.tileFor(
            painter: gone,
            spanStartIndex: start,
            spanEndIndexExclusive: end,
            devicePixelRatio: 1,
          ),
      ],
      everyElement(isNull),
      reason: 'nothing shows the other, so none of its tiles was made',
    );
  });

  test('a tile being rastered is not asked for again when its row repaints '
      'meanwhile', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    // The upload is held, so the raster is out for as long as the test says.
    final out = <({Completer<ui.Image> landing, int width, int height})>[];
    debugRawRgbaUploader =
        (
          rgba, {
          required width,
          required height,
          targetWidth,
          targetHeight,
        }) {
          final landing = Completer<ui.Image>();
          out.add((landing: landing, width: width, height: height));
          return landing.future;
        };
    addTearDown(() => debugRawRgbaUploader = null);
    final a = painterFor(rowLayer('a', frames: 4), frames: 4);
    show(a, () => paintRow(a, 4));

    paintRow(a, 4);
    while (out.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    paintRow(a, 4);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(out, hasLength(1), reason: 'its one tile is out once, not twice');

    for (final (:landing, :width, :height) in out) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      landing.complete(recorder.endRecording().toImageSync(width, height));
    }
    await idle();
    expect(out, hasLength(1), reason: 'and its landing asks for nothing more');
  });

  test('a row turned away in a world no longer live is not come back to — '
      'the store does not bring the old world back (#29)', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    TimelineRowCellsPainter inWorld(String world, String id, int frames) =>
        TimelineRowCellsPainter(
          layer: rowLayer(id, frames: frames),
          geometry: testFrameGeometry(
            frameCellExtent: 24,
            frameEndIndexExclusive: frames,
          ),
          crossAxisExtent: 28,
          exposureStateForLayer: exposureOf,
          colorScheme: const ColorScheme.dark(),
          baseTextStyle: const TextStyle(fontSize: 11),
          tileStore: store,
          substrateGeneration: world,
        );
    final old = inWorld('then', 'old', 40);
    final filler = inWorld('then', 'filler', 128);
    final current = inWorld('now', 'current', 16);
    show(old, () => paintRow(old, 40));
    show(current, () => paintRow(current, 16));
    paintRow(old, 40);
    paintRow(filler, 128);
    // The cut switches before the drain runs.
    paintRow(current, 16);
    await idle();

    expect(
      [
        for (final (start, end) in old.tileSpans)
          store.tileFor(
            painter: old,
            spanStartIndex: start,
            spanEndIndexExclusive: end,
            devicePixelRatio: 1,
          ),
      ],
      everyElement(isNull),
      reason: 'the old world is still shown, but it is not the live one',
    );
  });

  test('the store is busy while ANY raster is out — a drain that finishes '
      'beside another does not call it idle', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final out = <({Completer<ui.Image> landing, int width, int height})>[];
    debugRawRgbaUploader =
        (
          rgba, {
          required width,
          required height,
          targetWidth,
          targetHeight,
        }) {
          final landing = Completer<ui.Image>();
          out.add((landing: landing, width: width, height: height));
          return landing.future;
        };
    addTearDown(() => debugRawRgbaUploader = null);
    void land(int index) {
      final (:landing, :width, :height) = out[index];
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      landing.complete(recorder.endRecording().toImageSync(width, height));
    }

    final a = painterFor(rowLayer('a', frames: 4), frames: 4);
    final b = painterFor(rowLayer('b', frames: 4), frames: 4);
    paintRow(a, 4);
    while (out.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Asked for while the first drain is out: a second drain takes it.
    paintRow(b, 4);
    while (out.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    land(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.debugBusy, isTrue, reason: "b's raster is still out");

    land(1);
    await idle();
  });

  test('a clear fences off a raster still out — its key is asked for again '
      'at once, the store is idle, and the old pixels land nowhere', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final out = <({Completer<ui.Image> landing, int width, int height})>[];
    debugRawRgbaUploader =
        (
          rgba, {
          required width,
          required height,
          targetWidth,
          targetHeight,
        }) {
          final landing = Completer<ui.Image>();
          out.add((landing: landing, width: width, height: height));
          return landing.future;
        };
    addTearDown(() => debugRawRgbaUploader = null);
    void land(int index) {
      final (:landing, :width, :height) = out[index];
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      landing.complete(recorder.endRecording().toImageSync(width, height));
    }

    Future<void> until(bool Function() done) async {
      for (var wait = 0; wait < 500 && !done(); wait += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    final a = painterFor(rowLayer('a', frames: 4), frames: 4);
    var landings = 0;
    show(a, () => landings += 1);
    paintRow(a, 4);
    await until(() => out.isNotEmpty);
    expect(out, hasLength(1), reason: 'premise: its one tile is out');

    // What a test's tear-down does — a widget test's clock never lets that
    // upload land.
    store.clear();
    expect(store.debugBusy, isFalse, reason: 'the raster out is not counted');
    paintRow(a, 4);
    await until(() => out.length > 1);
    expect(out, hasLength(2), reason: 'its key is asked for again at once');

    land(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(landings, 0, reason: 'the fenced raster lands nowhere');
    land(1);
    await idle();
    expect(landings, 1, reason: 'the one asked for after it does');
  });

  test('a row is come back to with its NEWEST painter — once a tile of its '
      'lands, its repaints ask for it and the store does not', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final before = painterFor(rowLayer('b', frames: 40), frames: 40);
    // An edit: the same row, a new layer — a tile of the old one is stale
    // for the new painter, which shows it only until its own lands.
    final after = painterFor(rowLayer('b', frames: 40), frames: 40);
    // Thirty-two spans nothing repaints, to fill the queue.
    final filler = painterFor(rowLayer('filler', frames: 128), frames: 128);
    var landings = 0;
    void repaintBefore() {}
    show(before, repaintBefore);

    paintRow(before, 40);
    paintRow(filler, 128);
    // The edit lands before the drain runs: the old painter goes, the new
    // one is attached and paints.
    before.removeListener(repaintBefore);
    show(after, () {
      landings += 1;
      paintRow(after, 40);
    });
    paintRow(after, 40);
    await idle();

    paintRow(after, 40);
    expect(store.debugBusy, isFalse, reason: 'the new painter is warm');
    expect(
      landings,
      10,
      reason: 'each of its ten spans rastered once, for the new painter — '
          'never again for the old layer, over what the new one had shown',
    );
  });
}
