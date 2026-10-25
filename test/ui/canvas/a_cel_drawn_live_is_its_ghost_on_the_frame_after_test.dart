import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/quiet_turns.dart' show QuietTurn;
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/one_piece.dart';
import '../../helpers/settle_async.dart';

/// 🚨★★★A CEL THE CANVAS DREW LIVE IS ITS GHOST ON THE FRAME AFTER — WHOLE
/// (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The cel you are drawing on is drawn live; every onion ghost is one
/// composed image the ghosts' stack asks a cache for. Step to the next frame
/// and the cel you were just drawing is the ghost behind it — and if the
/// cache has no image of it yet (the prerender only warms one once the
/// editor goes idle) the ghost used to show NOTHING for the frames an
/// asynchronous build takes: what you had just drawn vanished and came back.
///
/// 🔬Measured on these fixtures before the fix (2026-09-17, when it was the
/// layer you left that went missing): at 50% on the production buffer
/// route **0 of 32** columns on the first frame — the synchronous road only
/// ever answered at full quality, and below 100% the stack asks for a LEVEL
/// — and at 100% on the direct walk, two of eight tiles pictured, again
/// **0 of 32**.
///
/// The stack reads which cels the canvas under it drew live the build it
/// replaces ([CanvasLayerStackView.drawnLive]) and composes those on the
/// spot, at the quality asked, every missing tile pictured inside the call.
/// ↩️It read them off its own active rows, until the frame's one picture
/// drew the live row and the ghosts lay over it (one-picture-per-frame ②-3)
/// — the regression this pins was there from then until ②-5a.
///
/// ⛔AND ONLY THOSE. A cel that was NOT on screen — a frame scrubbed to, a
/// project just opened — is not composed inside the build: a whole cold
/// stack made in one build is a stall nobody asked for.
void main() {
  const tileSize = 16;
  const tileCount = 8;
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  // The VIEW is two tiles wide; the cel is eight.
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);

  BrushFrameKey keyOf(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  final screen = GlobalKey();

  /// One blue cel of eight tiles.
  BitmapSurface blue() {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
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

  /// A store whose [frames] are each one [blue], FILE-BACKED cel — file-
  /// backed because `storeBakedSurface` alone registers pixels without a
  /// drawing state, and the cache refuses at its first gate.
  BrushFrameStore blueStore(List<String> frames) {
    final store = BrushFrameStore();
    keepInAFile(store, {for (final frame in frames) keyOf(frame): blue()});
    return store;
  }

  /// The surface a canvas draws [key]'s cel live from — the same tile
  /// objects the image cache composes.
  BitmapSurface surfaceOf(BrushFrameStore store, BrushFrameKey key) =>
      BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface;

  /// The ghosts' stack: [ghosts] each a row's image, over a canvas that
  /// draws [drawnLive] live.
  Future<void> pumpGhosts(
    WidgetTester tester,
    LayerFrameImageCache images,
    List<BrushFrameKey> ghosts, {
    required Set<BrushFrameKey> drawnLive,
    required double zoom,
    required bool walk,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: screen,
            child: ClipRect(
              child: SizedBox(
                width: viewSize.width,
                height: viewSize.height,
                child: CanvasLayerStackView(
                  nodes: [
                    for (final ghost in ghosts)
                      CompositeLeaf<CanvasStackRow>(
                        CanvasLayerImageRequest(frameKey: ghost, opacity: 1),
                      ),
                  ],
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom),
                  drawnLive: drawnLive,
                  debugDisableSingleBuffer: walk,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// WHAT THE LAST PUMP PUT ON SCREEN, read off the layer tree.
  ///
  /// ⛔Not by calling the painter again. The picture made inside the build
  /// is only that frame's: its plain snapshot lands a moment later, the view
  /// takes it and lets the first one go — so the painter object of the frame
  /// under test holds a disposed image by the time a test could call it, and
  /// a second paint would be measuring a frame the app never shows anyway.
  Future<Uint8List> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// Paints what the stack's painter on screen draws NOW — a recording only:
  /// a disposed image it still holds fails the draw.
  void paintNow(WidgetTester tester) {
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder, Offset.zero & viewSize), viewSize);
    recorder.endRecording().dispose();
  }

  /// Blue columns on the row through the middle of the cel at [zoom].
  int blueColumns(Uint8List rgba, double zoom) {
    var n = 0;
    final row = (tileSize * zoom / 2).floor();
    for (var x = 0; x < viewSize.width.toInt(); x += 1) {
      final o = (row * viewSize.width.toInt() + x) * 4;
      if (rgba[o + 2] > 0xC8 && rgba[o + 3] == 0xFF) n += 1;
    }
    return n;
  }

  int pictured(BitmapSurface surface) => surface.tiles.values
      .where((tile) => BitmapTileImageCache.instance.imageFor(tile) != null)
      .length;

  /// The canvas draws [drawn]'s cel live, with [drawn]'s live paint having
  /// pictured [picturedWhileLive] of its tiles; the frame steps and the cel
  /// is a ghost. Answers how much of it the first frame after shows.
  Future<int> firstFrameAfterTheStep(
    WidgetTester tester, {
    required double zoom,
    required bool walk,
    required int picturedWhileLive,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final drawn = keyOf('drawn');
    final live = surfaceOf(store, drawn);
    // What the canvas's live paint pictured of the cel: the tiles it drew.
    for (final tile in live.tiles.values.take(picturedWhileLive)) {
      BitmapTileImageCache.instance.pictureFor(tile);
    }

    await pumpGhosts(
      tester,
      images,
      const [],
      drawnLive: {drawn},
      zoom: zoom,
      walk: walk,
    );
    expect(pictured(live), picturedWhileLive, reason: 'fixture');

    // THE STEP: the cel is a ghost now. ONE frame — ⛔not pumpAndSettle,
    // which would let the asynchronous pass land.
    await pumpGhosts(
      tester,
      images,
      [drawn],
      drawnLive: const {},
      zoom: zoom,
      walk: walk,
    );
    return blueColumns(await onScreen(tester), zoom);
  }

  testWidgets('🚨at 50% — every zoomed-out step: the cel drawn live is whole '
      'as its ghost on the first frame after', (tester) async {
    expect(
      await firstFrameAfterTheStep(
        tester,
        zoom: 0.5,
        walk: false,
        picturedWhileLive: tileCount ~/ 2,
      ),
      viewSize.width.toInt(),
      reason: 'below 100% the stack asks for a LEVEL of the cel, which the '
          'synchronous road refused outright — so what you had just been '
          'drawing vanished until an asynchronous build landed',
    );
  });

  testWidgets('🚨on the direct walk, where the live paint pictured only the '
      'tiles in view: the cel is whole as its ghost on the first frame '
      'after', (tester) async {
    expect(
      await firstFrameAfterTheStep(
        tester,
        zoom: 1,
        walk: true,
        picturedWhileLive: 2,
      ),
      viewSize.width.toInt(),
      reason: 'six of the eight tiles had no picture, so a compose that '
          'needs every tile pictured ALREADY answered nothing — the '
          'pictures it lacks are made inside the call',
    );
  });

  testWidgets('🚨and when its snapshot SETTLES, the deferred picture is let '
      'go in the build the settle asks for', (tester) async {
    // 유저 2026-09-23, through the board/integration session's measurement
    // (board `I-19`): 「솔로 버벅임」. The cel composed in the build is a
    // deferred image; its plain snapshot takes its place a moment later
    // (the same pixels), and the deferred picture pins every tile picture
    // it drew for as long as a handle on it lives.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn', 'other']);
    final drawn = keyOf('drawn');
    final other = keyOf('other');
    final images = _HandedImages(frameStore: store, watched: drawn);
    addTearDown(images.dispose);
    // The ghost already there is warm, as every row is once the editor has
    // sat idle: after the step, the settle is the only thing still to come.
    await tester.runAsync(
      () => images.prepare(
        key: other,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    await pumpGhosts(
      tester,
      images,
      [other],
      drawnLive: {drawn},
      zoom: 1,
      walk: false,
    );
    await lendBothClocks(
      tester,
      rounds: 6,
      beat: const Duration(milliseconds: 30),
    );

    // THE STEP: the cel is composed in the build, as a deferred image.
    await pumpGhosts(
      tester,
      images,
      [other, drawn],
      drawnLive: const {},
      zoom: 1,
      walk: false,
    );
    expect(
      await settleAsync(tester, () {
        // Painted at every turn, as a sibling repainting the layer paints
        // it: between the settle and the build it asks for, the painter on
        // screen still draws with the clone the settle replaced — which
        // may not go before that build.
        paintNow(tester);
        return images.handed.isNotEmpty &&
            !identical(images.handed.last.image, images.handed.first.image);
      }),
      isTrue,
      reason: 'fixture: the stack was handed a second handle — the snapshot '
          'that settled in place of the deferred image',
    );
    // Then the frames the settle asks for: the stack's build, which lets
    // its clone go, and the boundaries the cache's own retired handle waits
    // out (`DeferredImageDisposer`) — frames, not time.
    while (tester.binding.hasScheduledFrame) {
      await tester.pump();
    }
    final inTheBuild = images.handed.first;
    final settled = images.handed.last;
    expect(
      identical(settled.content, inTheBuild.content),
      isTrue,
      reason: 'fixture: of the same pixels',
    );
    expect(
      inTheBuild.image.debugGetOpenHandleStackTraces(),
      isEmpty,
      reason: 'the deferred picture pins every tile picture it drew for as '
          'long as a handle on it lives, so the stack lets its clone go in '
          'the build the settle asks for — not whenever the rows next '
          'happen to change',
    );
    expect(
      blueColumns(await onScreen(tester), 1),
      viewSize.width.toInt(),
      reason: 'and the cel is still all there',
    );
  });

  testWidgets('⛔a cel the canvas did NOT draw live is not composed inside '
      'the build — it arrives with the asynchronous pass, as it always has', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn', 'cold']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final cold = surfaceOf(store, keyOf('cold'));

    await pumpGhosts(
      tester,
      images,
      const [],
      drawnLive: {keyOf('drawn')},
      zoom: 1,
      walk: false,
    );
    // A ghost nobody was looking at comes in (a frame scrubbed to).
    await pumpGhosts(
      tester,
      images,
      [keyOf('cold')],
      drawnLive: const {},
      zoom: 1,
      walk: false,
    );

    expect(
      pictured(cold),
      0,
      reason: 'a build must not make a cold cel\'s pictures: with a stack of '
          'cold rows — every frame scrubbed to — that is the whole stack '
          'pictured and composed inside one build',
    );
    expect(
      blueColumns(await onScreen(tester), 1),
      0,
      reason: 'and so its first frame is still the asynchronous pass\'s to '
          'fill — if this ever reads whole, the cold half of the law has '
          'been widened and the stall came with it',
    );
  });
}

/// The cache as the stack sees it, remembering every image it hands over
/// for [watched] in order — the one place the build's deferred picture and
/// the snapshot that settles in its place can be seen side by side.
class _HandedImages extends LayerFrameImageCache {
  _HandedImages({required super.frameStore, required this.watched});

  final BrushFrameKey watched;
  final List<LayerFrameImage> handed = [];

  LayerFrameImage? _noted(BrushFrameKey key, LayerFrameImage? image) {
    if (key == watched && image != null) {
      handed.add(image);
    }
    return image;
  }

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    required bool makePictures,
    bool inkSuffices = false,
  }) => _noted(
    key,
    super.prepareSyncOrNull(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      makePictures: makePictures,
      inkSuffices: inkSuffices,
    ),
  );

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
    Future<QuietTurn?> Function()? turn,
  }) async => _noted(
    key,
    await super.prepare(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      shouldAbort: shouldAbort,
      inkSuffices: inkSuffices,
      turn: turn,
    ),
  );
}
