import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// F-313 (유저 2026-10-08): 「다른행이동하면 일시적으로 빈 블록으로 만드는
/// 로직 있는거같은데 싹 삭제하고 법 통일. 항상 보여야함」.
///
/// A move that carries a cel onto another row shows it, until the release,
/// under the row it came from (`celPixelsOf`); the release re-keys its
/// pixels onto the row it lands on. The pixels do not change — only the
/// key a screen asks with does — so the frame it lands on shows it as the
/// frame before did: its preview travels with it, and the frame is drawn as
/// it stands from it while its picture is laid.
///
/// 🔬Measured before the pictures travelled with their cel (2026-10-12):
/// **0 of 32** columns on the first frame after the release, at 50% and at
/// 100%, for a cel that lands as an image row (an onion ghost, a row of a
/// multi-row move the brush is not on). ↩️Pinned on the editing stack's row
/// images at both zooms, until a frame's one picture was all a screen drew
/// (one-picture-per-frame ②-5b-1) — the zoom asks nothing of a picture
/// made at the canvas's own resolution.
void main() {
  const tileSize = 16;
  const tileCount = 8;
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);
  const zoom = 0.5;

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  final from = keyOf('from');
  final to = keyOf('to');
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 1,
    canvasSize: canvasSize,
    layers: const [],
  );
  const frame = 0;
  final screen = GlobalKey();

  /// One opaque cel of eight tiles, full in colour [channel] (0 red, 2 blue).
  BitmapSurface opaque(int channel) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + channel] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// The cels of [channelOf], each [opaque] in the channel it names, kept
  /// in a file as an opened project keeps them.
  ({BrushFrameStore cels, StackRun run, FramePictureStore<FramePictureKey> store})
  celsOf(Map<BrushFrameKey, int> channelOf) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      for (final MapEntry(:key, value: channel) in channelOf.entries)
        key: opaque(channel),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final run = runOver(images, store, canvasSize: canvasSize, stackOf: (_) => []);
    return (cels: cels, run: run, store: store);
  }

  List<CompositeNode<CanvasStackRow>> rowOf(BrushFrameKey cel) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: cel, opacity: 1),
    ),
  ];

  /// [cel]'s row on a screen that draws nothing live — as the onion ghosts'
  /// view draws one.
  Future<void> pumpRow(WidgetTester tester, StackRun run, BrushFrameKey cel) =>
      tester.pumpWidget(
        onAScreen(
          screen,
          size: viewSize,
          under: const Color(0xFF000000),
          view: FramePictureView(
            run: run,
            picture: (cut: cut, frameIndex: frame, paintPaper: false),
            nodes: rowOf(cel),
            viewport: CanvasViewport(zoom: zoom),
            laysWhatItMisses: true,
            wholeFrames: false,
          ),
        ),
      );

  /// Blue columns on the row through the middle of the cel.
  Future<int> blueColumns(WidgetTester tester) async {
    final shot = await shotOf(tester, screen);
    var n = 0;
    final row = (tileSize * zoom / 2).floor();
    for (var x = 0; x < shot.width; x += 1) {
      final o = (row * shot.width + x) * 4;
      if (shot.rgba[o + 2] > 0xC8 && shot.rgba[o + 3] == 0xFF) n += 1;
    }
    return n;
  }

  Future<bool> showsBlueWhole(WidgetTester tester) => settleAsync(
    tester,
    () async => await blueColumns(tester) == viewSize.width.toInt(),
  );

  testWidgets('🚨a cel that lands as an image row is whole on the first '
      'frame after the release', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final (:cels, :run, store: _) = celsOf({from: 2});
    await pumpRow(tester, run, from);
    expect(
      await showsBlueWhole(tester),
      isTrue,
      reason: 'fixture: the drag shows the cel under the row it came from',
    );

    cels.rekeyFrames([(from, to)]);
    // ONE frame — ⛔not pumpAndSettle, which lets the asynchronous read land.
    await pumpRow(tester, run, to);

    expect(await blueColumns(tester), viewSize.width.toInt());
  });

  testWidgets('🚨a cel carried onto a key a picture was made under shows '
      'itself — not that picture', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    // A red cel under the key the blue one is carried to, its picture made.
    final (:cels, :run, :store) = celsOf({from: 2, to: 0});
    await pumpRow(tester, run, to);
    final red = run.pictures.keyOfStack(rowOf(to), (
      cut: cut,
      frameIndex: frame,
      paintPaper: false,
    ));
    expect(
      await settleAsync(tester, () => store.peek(red) != null),
      isTrue,
      reason: '⛔premise: the red cel\'s picture is made',
    );
    await pumpRow(tester, run, from);
    expect(await showsBlueWhole(tester), isTrue, reason: 'fixture');

    cels.rekeyFrames([(from, to)]);
    await pumpRow(tester, run, to);

    expect(
      await blueColumns(tester),
      viewSize.width.toInt(),
      reason: 'the key the cel lands on named the red cel\'s picture: asked '
          'at the same revision, the screen shows the cel that is gone',
    );
    expect(await showsBlueWhole(tester), isTrue, reason: 'and stays so');
  });
}
