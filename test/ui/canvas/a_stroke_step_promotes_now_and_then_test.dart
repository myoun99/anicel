import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/project_scratch_folder.dart';

/// 🚨A SNAPSHOT IS A FIXED PRICE WHATEVER ITS SIZE (2026-09-25, the real
/// Windows app: 32×32 and 2448×1313 alike 1.6–2.0 ms of raster), and on a
/// GPU that answers within the frame the display buffer's promotion slot is
/// free on every paint — so each stroke step paid for its head AND a second
/// full snapshot. A step patched over the real base promotes only now and
/// then, and patches over an older base in between: a larger dirty rect,
/// the same picture.
///
/// ⚠️UNDER `runAsync`, WITH A TURN OF THE EVENT QUEUE AFTER EACH PAINT — the
/// promotion is a real `Picture.toImage`, which the fake async zone never
/// completes; without that every promotion would stay in flight and this
/// would count nothing.
void main() {
  const canvasSize = CanvasSize(width: 512, height: 512);
  const tileSize = 64;
  const steps = 40;
  const nodes = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
  ];
  const captureKey = ValueKey<String>('stroke-capture');

  /// A stroke that stays inside one tile: step i has drawn pixels 0…i of a
  /// line, so every step's dirty rect is that tile — a small share of the
  /// buffer, which is the case the throttle is for. Built once, before the
  /// loop.
  final surfaces = <BitmapSurfacePainter>[];
  var tile = BitmapTile.blank(size: tileSize);
  for (var step = 0; step <= steps; step += 1) {
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: step % tileSize,
      y: 10 + step ~/ tileSize,
      color: RgbaColor(r: 200, g: 30, b: 30, a: 255),
    );
    surfaces.add(
      BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {TileCoord(x: 1, y: 1): tile},
        ),
        showTransparentBackground: false,
      ),
    );
  }

  Future<void> paint(
    WidgetTester tester,
    DisplayBufferCache buffers,
    LayerFrameImageCache imageCache,
    BitmapSurfacePainter surface,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: captureKey,
            child: SizedBox(
              width: 512,
              height: 512,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: imageCache,
                debugBufferCache: buffers,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: surface,
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<Uint8List> captured(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  testWidgets('a stroke promotes every few steps, and the picture is the one '
      'a cold compose makes', (tester) async {
    tester.view.physicalSize = const Size(512, 512);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());
    late Uint8List stroked;
    late int promoted;
    late int afterCold;
    await tester.runAsync(() async {
      await paint(tester, buffers, imageCache, surfaces.first);
      await Future<void>.delayed(Duration.zero);
      afterCold = buffers.promotedCount;
      final before = buffers.promotedCount;
      for (var step = 1; step <= steps; step += 1) {
        await paint(tester, buffers, imageCache, surfaces[step]);
        await Future<void>.delayed(Duration.zero);
      }
      promoted = buffers.promotedCount - before;
      stroked = await captured(tester);
    });
    final reading =
        'patched=${buffers.patchedCount} full=${buffers.fullCount} '
        'promoted=$promoted over $steps steps';
    expect(
      afterCold,
      greaterThanOrEqualTo(1),
      reason: 'a compose from nothing is where a chain would start, so its '
          'snapshot is asked for at once:\n$reading',
    );
    expect(
      buffers.patchedCount,
      greaterThanOrEqualTo(steps - 2),
      reason: 'the steps did not patch, so nothing here was measured:\n'
          '$reading',
    );
    expect(
      promoted,
      lessThanOrEqualTo(steps ~/ DisplayBufferCache.promoteEvery + 2),
      reason: 'a patch over the real base promoted on (nearly) every step — '
          'two full snapshots a step:\n$reading',
    );
    expect(
      promoted,
      greaterThanOrEqualTo(steps ~/ (2 * DisplayBufferCache.promoteEvery)),
      reason: 'the base stopped moving at all:\n$reading',
    );

    // The same final picture composed from nothing.
    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    late Uint8List fresh;
    await tester.runAsync(() async {
      await paint(
        tester,
        cold,
        LayerFrameImageCache(frameStore: BrushFrameStore()),
        surfaces[steps],
      );
      fresh = await captured(tester);
    });
    expect(cold.patchedCount, 0, reason: 'a cold cache composes whole');
    expect(stroked.length, fresh.length);
    var differing = 0;
    for (var i = 0; i < stroked.length; i += 1) {
      if (stroked[i] != fresh[i]) {
        differing += 1;
      }
    }
    expect(
      differing,
      0,
      reason: 'patching over an older base changed the picture',
    );
  });

  // What a run's tree holds: rows drawn from their made images, none
  // standing live.
  const runKey = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  const runRows = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: runKey, opacity: 1),
    ),
  ];

  /// A cache holding [runKey]'s image, made from a one-tile cel on disk.
  Future<LayerFrameImageCache> heldRunImage(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('anicel-run-rows');
    deleteAfterSessionEnds(dir);
    final surface = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {TileCoord(x: 2, y: 2): tile},
    );
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(runKey, surface),
    );
    final file = File('${dir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    final store = BrushFrameStore()
      ..restoreFromFile({
        runKey: AnicelCelFileRef(
          filePath: file.path,
          dataOffset: 0,
          length: blob.bytes.length,
          canvasSize: canvasSize,
          tileSize: tileSize,
        ),
      });
    final cache = LayerFrameImageCache(frameStore: store);
    await tester.runAsync(
      () => cache.prepare(
        key: runKey,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    return cache;
  }

  /// [frames] frames of [tree], each on another paper so each one composes
  /// whole, with a turn of the event queue after each for a snapshot to land.
  Future<void> showFrames(
    WidgetTester tester, {
    required List<CompositeNode<CanvasStackRow>> tree,
    required LayerFrameImageCache imageCache,
    required DisplayBufferCache buffers,
    required BitmapSurfacePainter? painter,
    required int frames,
  }) => tester.runAsync(() async {
    for (var index = 0; index < frames; index += 1) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 512,
              height: 512,
              child: CanvasLayerStackView(
                nodes: tree,
                imageCache: imageCache,
                debugBufferCache: buffers,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: painter,
                paintPaper: true,
                paperBackground: ProjectBackground.color(
                  0xFF000000 | (index * 0x202020),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(Duration.zero);
    }
  });

  // A tree draws its live surface only with a live row in it AND a painter
  // to draw that row: a run's tree stands no row live
  // (`EditingCanvas.playingStack`) while the host still hands the canvas
  // its surface painter, and the film's track stack hands it none.
  for (final (:name, :run, :painted) in [
    (name: 'a run on the canvas', run: true, painted: true),
    (name: 'a live row with no painter', run: false, painted: false),
  ]) {
    testWidgets('🚨a tree that draws no live surface asks no snapshot — '
        '$name composes each frame whole and patches none', (tester) async {
      tester.view.physicalSize = const Size(512, 512);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final buffers = DisplayBufferCache();
      addTearDown(buffers.dispose);
      final imageCache = run
          ? await heldRunImage(tester)
          : LayerFrameImageCache(frameStore: BrushFrameStore());
      const frames = 6;
      await showFrames(
        tester,
        tree: run ? runRows : nodes,
        imageCache: imageCache,
        buffers: buffers,
        painter: painted ? surfaces.first : null,
        frames: frames,
      );
      if (run) {
        expect(
          imageCache.peek(
            runKey,
            PlaybackQuality.full,
            canvasSize: canvasSize,
            sourceEffects: const [],
            inkSuffices: true,
          ),
          isNotNull,
          reason: '⛔LIVENESS: the run\'s row is drawn from its made image',
        );
      }
      expect(
        buffers.fullCount,
        greaterThanOrEqualTo(frames),
        reason: 'fixture: every frame composed whole',
      );
      expect(
        buffers.promotedCount,
        0,
        reason: '↩️a run asked a snapshot of every frame it showed and '
            'threw it away unread',
      );
    });
  }
}
