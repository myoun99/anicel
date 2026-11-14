/// Tiles are drawn for real here, on two engines a test, each compiling the
/// grids' passes where it is first drawn on: the bound is this file's own
/// (`timeline_grid_tile_generation_test.dart` says why).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/the_apps_engine_let_go.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — the frame grids' tiles are
/// pictures the engine keeps, and go with the engine they were drawn on
/// (`TimelineGridTileStore`, by `StandsOnTheAppsEngine`): a device lays
/// nothing of another's. Each span is drawn again on the next engine, a
/// row drawing its cells itself meanwhile.
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = TimelineGridTileStore.instance;
  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 2)},
  );

  /// The tile the store answers a row of [layer] with, for its first span.
  TimelineGridTilePicture? tile() => store.tileFor(
    painter: TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: exposureOf,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
      tileStore: store,
    ),
    spanStartIndex: 0,
    spanEndIndexExclusive: 4,
    devicePixelRatio: 1.0,
  );

  setUp(store.clear);

  test('a tile drawn on the engine let go is the store\'s no more — freed, '
      'no row having laid it — and its span is drawn again on the '
      'next', () async {
    await openAppGpuEngine();
    expect(await pollUntil(() => tile() != null), isTrue, reason: '⛔premise');
    final first = tile();
    final live = TimelineGridTilePicture.debugLive;

    theAppsEngineLostAndLetGo();

    expect(TimelineGridTilePicture.debugLive, live - 1);
    expect(tile(), isNull, reason: 'no engine is open');
    expect(store.debugBusy, isFalse, reason: 'nor is one asked for');

    await openAppGpuEngine();
    expect(await pollUntil(() => tile() != null), isTrue);
    expect(identical(tile(), first), isFalse);
    expect(TimelineGridTilePicture.debugLive, live);
  });

  test('a tile on its way as the engine is let go is drawn on neither: not '
      'on the one let go, nor by a pass compiled for it on the '
      'next', () async {
    await openAppGpuEngine();
    var landings = 0;
    void landed() => landings += 1;
    store.revision.addListener(landed);
    addTearDown(() => store.revision.removeListener(landed));
    var lost = false;
    store.debugBeforeDrawing = () async {
      lost = true;
      theAppsEngineLostAndLetGo();
    };
    addTearDown(() => store.debugBeforeDrawing = null);
    final live = TimelineGridTilePicture.debugLive;

    expect(tile(), isNull, reason: '⛔premise: asked for, drawn off the paint');
    expect(await pollUntil(() => lost), isTrue, reason: '⛔premise');
    // What the raster would do after is done by now.
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(landings, 0);
    expect(TimelineGridTilePicture.debugLive, live);
    expect(appGpuGridKernels.compiled, isNull);
  });
}
