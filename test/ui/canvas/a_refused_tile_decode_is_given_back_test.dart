import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// 🚨★★★**A REFUSED TILE DECODE IS GIVEN BACK — AND WHAT IT HELD WAS AN
/// ANSWER TO TWO QUESTIONS AT ONCE.**
///
/// `_inFlight` was an `Expando` with ONE write and ZERO clears; `git log -S`
/// finds no commit that ever removed one. Success worked only because every
/// reader tests the image map first, so ABSENT meant both 「nobody has
/// asked」 and 「the last ask was refused」 — and
/// `ui.decodeImageFromPixels` never invokes its callback on a refusal, so a
/// refused tile kept a marker nothing could retire. It was then
/// unrequestable, un-adoptable AND un-uploadable: a canvas tile blank for
/// the life of the tile object that even the in-frame synchronous upload
/// stood aside for. Downstream, `allDecoded` never came true, the settle
/// window's two-second give-up dropped the stand-in, and a tile-shaped
/// patch of the finished stroke reverted to pre-stroke pixels — the exact
/// failure the settle machinery exists to prevent.
///
/// 🚨EVERY MACHINE THAT RUNS THIS TEST DECODES SUCCESSFULLY. Windows runs
/// Skia in every build, CI included, and a genuine refusal wants an
/// allocation to fail on a small device. `BitmapTile` also validates its own
/// pixel length, so the lying-descriptor fixture that reaches
/// `uploadRawRgba` in `straight_rgba_image_test.dart` cannot be built here.
/// So the refusal comes through [debugRawRgbaUploader], for the same reason
/// `tile_image_sync_upload_test.dart` states for its own injection point:
/// the alternative is a suite that exercises this path by watching it
/// succeed.
void main() {
  BitmapTile inkedTile({int x = 0, int y = 0}) => writeRgbaColorToBitmapTile(
    tile: BitmapTile.blank(coord: TileCoord(x: x, y: y), size: 2),
    x: 0,
    y: 0,
    color: RgbaColor(r: 200, g: 100, b: 50, a: 128),
  );

  ui.Image aSolidImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 2, 2),
      Paint()..color = const Color(0xFF00FF00),
    );
    return recorder.endRecording().toImageSync(2, 2);
  }

  /// The engine, standing in — [refuse] decides which way it answers.
  void installUploader({required bool refuse, List<int>? sizes}) {
    debugRawRgbaUploader =
        (
          Uint8List rgba, {
          required int width,
          required int height,
          int? targetWidth,
          int? targetHeight,
        }) {
          sizes?.add(width);
          if (refuse) {
            return Future<ui.Image>.error(
              StateError('the engine refused this upload'),
            );
          }
          return Future<ui.Image>.value(aSolidImage());
        };
  }

  tearDown(() => debugRawRgbaUploader = null);

  /// ⛔THE INSTRUMENT FIRST. Every assertion below is about what happens
  /// after a refusal, and a seam that never ran, or a cache that never
  /// asked, would make all of them vacuously true.
  test('the premise: the seam is consulted, and a decode that succeeds '
      'still fills the tile', () async {
    final cache = BitmapTileImageCache();
    final asked = <int>[];
    installUploader(refuse: false, sizes: asked);
    final tile = inkedTile();

    expect(cache.needsDecodeStart(tile), isTrue);
    cache.ensureDecoded(tile);
    await pumpEventQueue();

    expect(asked, [2], reason: 'the cache went through the seam, once');
    expect(cache.imageFor(tile), isNotNull, reason: 'and the tile filled');
    expect(cache.needsDecodeStart(tile), isFalse);
  });

  test('🚨a refused tile is not asked again — and every door that can still '
      'FILL it is open', () async {
    final cache = BitmapTileImageCache();
    final captured = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => captured.add(details.exception);

    final asked = <int>[];
    installUploader(refuse: true, sizes: asked);
    final tile = inkedTile();
    cache.ensureDecoded(tile);
    await pumpEventQueue();

    // A second paint's worth of starts, to prove the refusal is REMEMBERED
    // rather than simply forgotten — a marker cleared to nothing would ask
    // again here, which is the media viewer's hot loop wearing this hat.
    cache.ensureDecoded(tile);
    await pumpEventQueue();

    FlutterError.onError = previous;

    expect(asked, [2], reason: 'refused once, asked once — not a loop');
    expect(cache.imageFor(tile), isNull);
    expect(captured, isNotEmpty, reason: 'and the refusal is not hidden');

    // 🚨★★★THE RECOVERY. Both guards used to stand aside for ANY marker;
    // the one they were written for is a decode that WILL land, and a
    // refused one never will. Standing aside for it threw away the pen-up
    // handoff's image — the very picture the live overlay had already
    // decoded from these exact bytes — and left nothing able to fill the
    // tile at all.
    final handedOver = aSolidImage();
    cache.adoptDecoded(tile, handedOver);
    expect(
      cache.imageFor(tile),
      same(handedOver),
      reason: 'the pen-up handoff fills a refused tile',
    );
  });

  test('🚨the synchronous in-frame upload also fills a refused tile', () async {
    final cache = BitmapTileImageCache();
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    installUploader(refuse: true);
    final tile = inkedTile();
    cache.ensureDecoded(tile);
    await pumpEventQueue();

    // The sync path is Impeller-only and this machine is Skia, so it has
    // its own injection point — the same argument, one layer down.
    debugSyncImageUploadOverride = (pixels, width, height) => aSolidImage();
    final uploaded = cache.adoptSyncUpload(tile);
    debugSyncImageUploadOverride = null;
    FlutterError.onError = previous;

    expect(
      uploaded,
      isNotNull,
      reason: 'on a device that can upload inside the frame, a refused tile '
          'is exactly the case that most needs it',
    );
    expect(cache.imageFor(tile), isNotNull);
  });

  test('🚨a refusal NOTIFIES, so the tiles queued behind it still drain', () async {
    // ⛔The refused tile has nothing new to draw — but starts are budgeted,
    // and 「completions notify → repaint → the next chunk starts」 is the
    // only thing that walks a thousand-tile cel forward. A whole chunk
    // refusing during a transient squeeze would otherwise stop the cel
    // converging until some unrelated widget happened to repaint.
    final cache = BitmapTileImageCache();
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    var notifications = 0;
    cache.addListener(() => notifications += 1);

    installUploader(refuse: false);
    cache.ensureDecoded(inkedTile(x: 0));
    await pumpEventQueue();
    final afterSuccess = notifications;

    installUploader(refuse: true);
    cache.ensureDecoded(inkedTile(x: 1));
    await pumpEventQueue();

    FlutterError.onError = previous;

    expect(
      afterSuccess,
      1,
      reason: 'instrument: a landing notifies — if this is 0 the listener '
          'is not wired and the assertion below would pass on nothing',
    );
    expect(
      notifications,
      2,
      reason: 'and so does a refusal, for the chunk behind it',
    );
  });
}
