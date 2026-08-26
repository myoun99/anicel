import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// H27 — 「이전 변형하기 전 그림이 남아있었음」.
///
/// Device report 2026-08-27 (iPhone): a second transform confirm left the
/// PRE-transform drawing on screen until the view was zoomed or panned. On
/// Windows the same thing lasts exactly one frame — a desktop produces the
/// next frame immediately, an idle phone produces none at all until you
/// touch the view. **Two severities, one cause.**
///
/// The cause is the cold-miss branch of `CanvasLayerStackView`'s synchronous
/// sweep. It held on to `_images[key]` — the picture as it was BEFORE the
/// edit — whenever the cache could not answer synchronously, and the painter
/// drew it.
///
/// ⛔The fix is NOT 「drop it on every cold miss」. That branch exists so a
/// LAYER SWITCH is flicker-free, and dropping unconditionally would put the
/// vanish-and-return back. `sourceRevision` is what tells the two apart:
/// `markCelEdited` bumps it on every surface write, a layer switch never
/// touches it. Both cases are pinned below, and the second one is what dies
/// if anyone simplifies the guard away.
///
/// ⚠️#1218's lesson applies here: 「프리뷰 채널은 값을 계속 나르고 있어서
/// 그걸 단언하면 옛 빌드에서도 통과한다」 — so these read the PIXELS the
/// stack painter actually produced, never a channel's value.
void main() {
  const tileSize = 16;
  const tileCount = 4;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  const size = Size(tileSize * tileCount * 1.0, tileSize * 1.0);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-h27');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BitmapSurface filledSurface({
    required int r,
    required int g,
    required int b,
  }) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = r;
        pixels[i + 1] = g;
        pixels[i + 2] = b;
        pixels[i + 3] = 0xFF;
      }
      // 🚨A FRESH tile object every call. BitmapTileImageCache keys pictures
      // by tile identity, so a new surface is a surface nothing has decoded
      // — which is precisely the state a just-confirmed transform leaves the
      // cel in, and the reason the sweep sees a cold miss at all.
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(
        coord: TileCoord(x: x, y: 0),
        size: tileSize,
        pixels: pixels,
      );
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  Future<void> pumpStack(
    WidgetTester tester,
    LayerFrameImageCache imageCache,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CanvasLayerImageNode(
                    CanvasLayerImageRequest(frameKey: key, opacity: 1),
                  ),
                ],
                imageCache: imageCache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                // The law under test is what the paint BODY draws this
                // frame. The kept composite buffer can re-serve yesterday's
                // whole picture between cache notifications, which would
                // hide the very frame this exists to pin.
                debugDisableBake: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One frame's pixels through the stack painter, recorded synchronously so
  /// no decode can land mid-record.
  Future<Uint8List> paintStack(WidgetTester tester) async {
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty, reason: 'the stack view paints through one');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    painted.first.painter!.paint(canvas, size);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    return bytes!;
  }

  bool blueAt(Uint8List rgba, int x, int y) {
    final offset = (y * size.width.toInt() + x) * 4;
    return rgba[offset] < 0x30 &&
        rgba[offset + 1] < 0x30 &&
        rgba[offset + 2] > 0xC8 &&
        rgba[offset + 3] == 0xFF;
  }

  /// Counted across the whole row, not sampled at one point: a stale picture
  /// that survived in three tiles out of four is still the bug.
  int blueColumns(Uint8List rgba) {
    var n = 0;
    for (var x = 0; x < size.width.toInt(); x += 1) {
      if (blueAt(rgba, x, tileSize ~/ 2)) n += 1;
    }
    return n;
  }

  /// A store whose cel is drawn blue and FILE-BACKED — the state a cel is in
  /// right after a project open.
  ///
  /// 🚨File-backed is not a convenience: `storeBakedSurface` alone registers
  /// pixels without a drawing state, `frameOrNull` stays null, and `prepare`
  /// refuses at its first gate. A fixture built that way measures nothing.
  BrushFrameStore blueStore() {
    final surface = filledSurface(r: 0, g: 0, b: 0xFF);
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final file = File('${tempDir.path}/cel.bin')
      ..writeAsBytesSync(blob.bytes);
    final store = BrushFrameStore();
    store.restoreFromFile({
      key: AnicelCelFileRef(
        filePath: file.path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: tileSize,
      ),
    });
    expect(store.celHasRenderableContent(key), isTrue);
    expect(store.frameOrNull(key)?.sourceRevision, isNotNull);
    return store;
  }

  /// The blue picture, built the way the app builds it.
  Future<LayerFrameImage> blueImage(
    WidgetTester tester,
    LayerFrameImageCache cache,
  ) async {
    final prepared = await tester.runAsync(
      () => cache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    expect(prepared, isNotNull);
    return prepared!;
  }

  /// Mounts a store whose cel is drawn blue and a stack that has ADOPTED it.
  /// After this the held image is the blue picture — the state the device is
  /// in before the transform is confirmed.
  Future<(BrushFrameStore, LayerFrameImageCache)> stackHoldingBlue(
    WidgetTester tester,
  ) async {
    final store = blueStore();

    // Adopt through the REAL cache, the way the app does — the sweep can
    // only hold what something legitimately handed it.
    final warm = LayerFrameImageCache(frameStore: store);
    await blueImage(tester, warm);
    await pumpStack(tester, warm);
    expect(
      blueColumns(await paintStack(tester)),
      size.width.toInt(),
      reason: 'the fixture has to actually be holding the blue picture, or '
          'everything below is measuring an empty stack',
    );

    // From here the synchronous door is shut, exactly as it is on the frame
    // after a confirm: the new tiles are undecoded, so the sweep gets null.
    return (store, _SyncColdCache(frameStore: store));
  }

  testWidgets(
    'an EDIT drops the held picture even when nothing can replace it yet — '
    '유저: 「이전 변형하기 전 그림이 남아있었음」',
    (tester) async {
      final (store, cold) = await stackHoldingBlue(tester);

      // The confirm: new pixels, and the one signal every surface write makes.
      store
        ..storeBakedSurface(key, filledSurface(r: 0xFF, g: 0, b: 0))
        ..markCelEdited(key);

      // ONE frame. ⛔Not pumpAndSettle — settling would let the async pass
      // decode the new picture and heal the very frame under test.
      await pumpStack(tester, cold);

      expect(
        blueColumns(await paintStack(tester)),
        0,
        reason: 'the cel no longer looks like that. Painting nothing is '
            'honest for the frame a decode has not landed in; painting the '
            'drawing as it was BEFORE the edit is the bug',
      );
    },
  );

  testWidgets(
    'an in-flight build that lands AFTER the edit is stamped with the '
    'revision it was asked at, not the one it finished at',
    (tester) async {
      // The other door into the same bug, and the one a rapid second confirm
      // actually goes through: the build was already running when the edit
      // landed, so what it returns is the drawing as it was BEFORE. Stamping
      // it with the revision standing at completion would make it look
      // current to the cold-miss guard, which would then never drop it —
      // H27 back, through the async pass instead of the sync sweep.
      final store = blueStore();
      final blue = await blueImage(tester, LayerFrameImageCache(
        frameStore: store,
      ));

      final cache = _InFlightCache(frameStore: store);
      await pumpStack(tester, cache);
      expect(
        blueColumns(await paintStack(tester)),
        0,
        reason: 'nothing has been handed to the stack yet',
      );

      // The confirm lands while that first build is still out.
      store
        ..storeBakedSurface(key, filledSurface(r: 0xFF, g: 0, b: 0))
        ..markCelEdited(key);

      // ...and only then does it come back, carrying the pre-edit picture.
      cache.inFlight.complete(blue);
      await tester.pump();

      // A frame later the sweep looks again, and finds nothing to replace it
      // with — the same cold door as the first test.
      await pumpStack(tester, cache);

      expect(
        blueColumns(await paintStack(tester)),
        0,
        reason: 'the build finished after the edit, so what it carries is '
            'already out of date the moment it arrives',
      );
    },
  );

  testWidgets(
    'a cold miss with NO edit keeps the picture — this is what the '
    'flicker-free layer switch is',
    (tester) async {
      final (_, cold) = await stackHoldingBlue(tester);

      // Same shut door, no edit: the cache went cold, the pixels did not
      // move. ⛔An unconditional drop here would pass the test above and put
      // the vanish-and-return this sweep exists to prevent straight back.
      await pumpStack(tester, cold);

      expect(
        blueColumns(await paintStack(tester)),
        size.width.toInt(),
        reason: 'a cold cache is not a changed drawing',
      );
    },
  );
}

/// A cache whose asynchronous build is IN FLIGHT and finishes on command,
/// with nothing available synchronously — the state a rapid second confirm
/// arrives in.
///
/// The second `prepare` never completes, because on device the build that
/// follows an edit is exactly that: not ready. A stub that answered again
/// would re-hand the stale picture under the CURRENT revision and re-stale
/// it, which no real cache does.
class _InFlightCache extends LayerFrameImageCache {
  _InFlightCache({required super.frameStore});

  final Completer<LayerFrameImage?> inFlight = Completer<LayerFrameImage?>();
  var _handed = false;

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
  }) {
    if (_handed) return Completer<LayerFrameImage?>().future;
    _handed = true;
    return inFlight.future;
  }

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
  }) => null;
}

/// A cache whose SYNCHRONOUS door is shut, with the asynchronous one left
/// exactly as it is.
///
/// That pairing is the device state and not a convenience: after a confirm
/// the new tiles have no pictures, so `prepareSyncOrNull` genuinely returns
/// null, while `prepare` is genuinely in flight and lands a frame or more
/// later. Stubbing `prepare` to null as well would make the async pass drop
/// the held image on its own, and both tests above would then pass with the
/// guard deleted.
class _SyncColdCache extends LayerFrameImageCache {
  _SyncColdCache({required super.frameStore});

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
  }) => null;
}
