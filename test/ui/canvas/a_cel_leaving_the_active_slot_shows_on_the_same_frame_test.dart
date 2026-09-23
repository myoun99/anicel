import 'dart:io';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A CEL THAT LEAVES THE ACTIVE SLOT IS STILL ON SCREEN THE SAME FRAME
/// (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The layer you are drawing on is painted from its tiles; every other row
/// is one composed image the stack asks a cache for. The build in which you
/// switch layers — or step to the next frame with onion skin on — the cel
/// you were just drawing changes route, and if the cache has no image of it
/// yet (the prerender only warms one once the editor goes idle) the row used
/// to show NOTHING for the frames an asynchronous build takes: the artwork
/// you had just drawn vanished and came back.
///
/// 🔬Measured on these fixtures before the fix (2026-09-17):
/// · at 50% on the production buffer route — all 8 tiles pictured, and
///   still **0 of 32** columns on the first frame after the switch, because
///   the synchronous handoff only ever answered at full quality and below
///   100% the stack asks for a LEVEL (so: every zoomed-out layer switch);
/// · at 100% on the direct walk (what a view past the display buffer's cap
///   falls back to) — the paint reaches only the screen, 2 of 8 tiles were
///   pictured, the handoff's 「every tile is already decoded」 was false,
///   and again **0 of 32**.
///
/// The stack reads which cels the widget it replaces was drawing as ACTIVE
/// rows ([CanvasActiveLayerRow.frameKey]) and composes those on the spot,
/// at the quality asked, every missing tile pictured inside the call.
///
/// ⛔AND ONLY THOSE. A cel that was NOT on screen — a frame scrubbed to, a
/// project just opened — is not composed inside the build: a whole cold
/// stack made in one build is a stall nobody asked for. The last test pins
/// that half, so the law cannot quietly widen into it.
void main() {
  const tileSize = 16;
  const tileCount = 8;
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  // The VIEW is two tiles wide; the cel is eight.
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  final screen = GlobalKey();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-leaving-the-slot');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on Object catch (_) {}
  });

  /// A store whose [layers] are each one blue, FILE-BACKED cel of eight
  /// tiles — file-backed because `storeBakedSurface` alone registers pixels
  /// without a drawing state, and the cache refuses at its first gate.
  BrushFrameStore blueStore(List<String> layers) {
    final refs = <BrushFrameKey, AnicelCelFileRef>{};
    for (final layer in layers) {
      final tiles = <TileCoord, BitmapTile>{};
      for (var x = 0; x < tileCount; x += 1) {
        final pixels = Uint8List(tileSize * tileSize * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels[i + 2] = 0xFF;
          pixels[i + 3] = 0xFF;
        }
        tiles[TileCoord(x: x, y: 0)] = BitmapTile(
          size: tileSize,
          pixels: pixels,
        );
      }
      final key = keyOf(layer);
      final blob = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(
          key,
          BitmapSurface(
            canvasSize: canvasSize,
            tileSize: tileSize,
            tiles: tiles,
          ),
        ),
      );
      final file = File('${tempDir.path}/$layer.bin')
        ..writeAsBytesSync(blob.bytes);
      refs[key] = AnicelCelFileRef(
        filePath: file.path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
    }
    return BrushFrameStore()..restoreFromFile(refs);
  }

  /// The surface a canvas paints [key]'s cel from — the same tile objects
  /// the image cache composes.
  BitmapSurface surfaceOf(BrushFrameStore store, BrushFrameKey key) =>
      BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface;

  Future<void> pumpStack(
    WidgetTester tester,
    LayerFrameImageCache images,
    List<CompositeNode<CanvasStackRow>> nodes, {
    required double zoom,
    required bool walk,
    BitmapSurfacePainter? active,
    bool keepsComposites = false,
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
                  nodes: nodes,
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom),
                  activeSurfacePainter: active,
                  // The law is what the paint BODY draws this frame; the
                  // kept composite can re-serve the frame before — unless
                  // what is kept is the question.
                  debugDisableBake: !keepsComposites,
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
  Future<Uint8List> paintStack(WidgetTester tester) async {
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

  /// Draws [key]'s cel as the ACTIVE row, then switches away from it, and
  /// answers how much of it the first frame after the switch shows.
  Future<int> firstFrameAfterLeavingTheSlot(
    WidgetTester tester, {
    required double zoom,
    required bool walk,
    required int expectedPicturedWhileActive,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final key = keyOf('drawn');
    final live = surfaceOf(store, key);

    await pumpStack(
      tester,
      images,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: key),
        ),
      ],
      zoom: zoom,
      walk: walk,
      active: BitmapSurfacePainter(
        surface: live,
        showTransparentBackground: false,
        lineage: 'leaving-the-slot',
      ),
    );
    expect(
      blueColumns(await paintStack(tester), zoom),
      viewSize.width.toInt(),
      reason: 'fixture: the cel is on screen as the active row',
    );
    expect(
      live.tiles.values
          .where((tile) => BitmapTileImageCache.instance.imageFor(tile) != null)
          .length,
      expectedPicturedWhileActive,
      reason: 'fixture: how much of the cel the active paint reached',
    );

    // THE SWITCH: the same cel is an image row now. ONE frame — ⛔not
    // pumpAndSettle, which would let the asynchronous pass land.
    await pumpStack(
      tester,
      images,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
      zoom: zoom,
      walk: walk,
    );
    return blueColumns(await paintStack(tester), zoom);
  }

  testWidgets('🚨at 50% — every zoomed-out layer switch: the cel is whole on '
      'the first frame after it leaves the slot', (tester) async {
    expect(
      await firstFrameAfterLeavingTheSlot(
        tester,
        zoom: 0.5,
        walk: false,
        expectedPicturedWhileActive: tileCount,
      ),
      viewSize.width.toInt(),
      reason: 'below 100% the stack asks for a LEVEL of the cel, which the '
          'synchronous road refused outright — so the layer you had just '
          'been drawing on vanished until an asynchronous build landed',
    );
  });

  testWidgets('🚨on the direct walk, where the paint pictured only the tiles '
      'in view: the cel is whole on the first frame after it leaves', (
    tester,
  ) async {
    expect(
      await firstFrameAfterLeavingTheSlot(
        tester,
        zoom: 1,
        walk: true,
        expectedPicturedWhileActive: 2,
      ),
      viewSize.width.toInt(),
      reason: 'six of the eight tiles had no picture, so a compose that '
          'needs every tile pictured ALREADY answered nothing — the '
          'pictures it lacks are made inside the call now',
    );
  });

  testWidgets('🚨and when its snapshot SETTLES, the display buffer keeps '
      'what it already drew and the deferred picture is let go', (
    tester,
  ) async {
    // 유저 2026-09-23, through the board/integration session's measurement
    // (board `I-19`): 「솔로 버벅임」, layer select included. 🔬The F-130
    // `solo` arm, 24 drawn rows, named it: a select rastered the WHOLE
    // display buffer twice on consecutive frames. The first raster is the
    // switch itself. The second was this — the cel composed in the build is
    // a deferred image, its plain snapshot takes its place a moment later
    // (same pixels), and the stack took the new handle for a new picture.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn', 'below']);
    final drawn = keyOf('drawn');
    final below = keyOf('below');
    final images = _HandedImages(frameStore: store, watched: drawn);
    addTearDown(images.dispose);
    final live = surfaceOf(store, drawn);

    Future<void> frame({required bool drawnIsActive}) => pumpStack(
      tester,
      images,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: below, opacity: 1),
        ),
        CompositeLeaf<CanvasStackRow>(
          drawnIsActive
              ? CanvasActiveLayerRow(opacity: 1, frameKey: drawn)
              : CanvasLayerImageRequest(frameKey: drawn, opacity: 1),
        ),
      ],
      zoom: 1,
      walk: false,
      active: drawnIsActive
          ? BitmapSurfacePainter(
              surface: live,
              showTransparentBackground: false,
              lineage: 'leaving-the-slot',
            )
          : null,
      keepsComposites: true,
    );

    /// Lets every picture the engine owes land — the async pass's compose
    /// and a snapshot's `toImage` both finish in real time.
    Future<void> landEverything() async {
      for (var i = 0; i < 6; i += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    // The row under it is warm, as every row is once the editor has sat
    // idle: after the switch, the settle is the only thing still to come.
    await tester.runAsync(
      () => images.prepare(
        key: below,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    await frame(drawnIsActive: true);
    await landEverything();
    final state = tester.state(find.byType(CanvasLayerStackView)) as dynamic;
    // ignore: avoid_dynamic_calls
    final buffer = state.debugBufferCacheInUse as DisplayBufferCache;
    final rastersBeforeTheSwitch = buffer.fullCount;

    // THE SWITCH: the cel is composed in the build, as a deferred image.
    await frame(drawnIsActive: false);
    final rastersAfterTheSwitch = buffer.fullCount;
    expect(
      rastersAfterTheSwitch,
      greaterThan(rastersBeforeTheSwitch),
      reason: 'fixture: the switch itself rasters the buffer — the one '
          'raster a select has to pay',
    );

    await landEverything();
    final inTheBuild = images.handed.first;
    final settled = images.handed.last;
    expect(
      identical(settled.image, inTheBuild.image),
      isFalse,
      reason: 'fixture: the stack was handed a second handle — the snapshot '
          'that settled in place of the deferred image',
    );
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

    // Then the next rebuild, which anything causes, and a paint for any
    // reason at all — the stack has no boundary of its own, so a hover or
    // a cursor blink beside it is enough: both ask with whatever the stack
    // holds by then.
    await frame(drawnIsActive: false);
    tester
        .renderObject<RenderCustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .markNeedsPaint();
    await tester.pump();
    expect(
      buffer.fullCount,
      rastersAfterTheSwitch,
      reason: 'the settle is the same pixels on a new handle — rastering the '
          'whole buffer again for it is the second full raster a select '
          'used to pay',
    );
    expect(
      blueColumns(await paintStack(tester), 1),
      viewSize.width.toInt(),
      reason: 'and the cel is still all there',
    );
  });

  testWidgets('⛔a cel that was NOT on screen is not composed inside the '
      'build — it arrives with the asynchronous pass, as it always has', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore(['drawn', 'cold']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final cold = surfaceOf(store, keyOf('cold'));

    await pumpStack(
      tester,
      images,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('drawn')),
        ),
      ],
      zoom: 1,
      walk: false,
      active: BitmapSurfacePainter(
        surface: surfaceOf(store, keyOf('drawn')),
        showTransparentBackground: false,
        lineage: 'leaving-the-slot',
      ),
    );
    // A row nobody was looking at enters the stack (a frame scrubbed to).
    await pumpStack(
      tester,
      images,
      [
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: keyOf('cold'), opacity: 1),
        ),
      ],
      zoom: 1,
      walk: false,
    );

    expect(
      cold.tiles.values
          .where((tile) => BitmapTileImageCache.instance.imageFor(tile) != null)
          .length,
      0,
      reason: 'a build must not make a cold cel\'s pictures: with a stack of '
          'cold rows — every frame scrubbed to — that is the whole stack '
          'pictured and composed inside one build',
    );
    expect(
      blueColumns(await paintStack(tester), 1),
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
  }) => _noted(
    key,
    super.prepareSyncOrNull(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      makePictures: makePictures,
    ),
  );

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
  }) async => _noted(
    key,
    await super.prepare(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      shouldAbort: shouldAbort,
    ),
  );
}
