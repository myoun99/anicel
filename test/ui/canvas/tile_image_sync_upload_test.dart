import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// The synchronous bytes-to-image upload — the one thing composition
/// cannot do, and therefore the only route to the cases still open: a
/// confirm whose resample has not landed, a lift's start frame, a tile
/// nothing has ever decoded. All three have BYTES and no picture, and no
/// image operand to compose from.
///
/// 🚨 EVERY MACHINE THAT RUNS THIS TEST ANSWERS "NO".
/// `decodeImageFromPixelsSync` is Impeller only and Windows runs Skia in
/// every build, CI included. So the engine call is behind an injection
/// point and these tests drive that, because the alternative is a suite
/// that exercises this path by watching it return null — which is what
/// "we shipped an untested path" looks like from the inside.
void main() {
  BitmapTile inkedTile() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 2);
    // Partial alpha on purpose: the bytes handed to the uploader must be
    // PREMULTIPLIED, and at alpha 255 premultiplied and straight agree,
    // so an opaque fixture could not tell the two apart.
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 0,
      y: 0,
      color: RgbaColor(r: 200, g: 100, b: 50, a: 128),
    );
    return tile;
  }

  ui.Image aSolidImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 2, 2),
      Paint()..color = const Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    picture.dispose();
    return image;
  }

  tearDown(() {
    debugSyncImageUploadOverride = null;
  });

  test('an engine without it changes nothing', () {
    final cache = BitmapTileImageCache();
    final tile = inkedTile();

    // No override: the real probe runs, and on every machine this suite
    // runs on it answers no.
    expect(syncImageUploadSupported, isFalse);
    expect(cache.adoptSyncUpload(tile), isNull);
    expect(
      cache.imageFor(tile),
      isNull,
      reason: 'a refused upload must leave the tile exactly as it was',
    );
    expect(
      cache.needsDecodeStart(tile),
      isTrue,
      reason: 'and the asynchronous decode must still be the plan',
    );
  });

  test('an uploaded picture is TRUTH, not a stand-in', () {
    final cache = BitmapTileImageCache();
    final tile = inkedTile();
    debugSyncImageUploadOverride = (_, _, _) => aSolidImage();

    final image = cache.adoptSyncUpload(tile);

    expect(image, isNotNull);
    expect(identical(cache.imageFor(tile), image), isTrue);
    expect(
      cache.hasProvisional(tile),
      isFalse,
      reason:
          'these are the tile own bytes — there is nothing to replace '
          'later, which is the whole difference from a composed picture',
    );
    expect(
      cache.needsDecodeStart(tile),
      isFalse,
      reason: 'and no second decode of the same bytes',
    );
  });

  test('what it uploads is exactly what the asynchronous decoder would '
      'have been given', () {
    // The claim that makes adoption safe. If these bytes differed from
    // the ones `ensureDecoded` hands the decoder, the picture would not
    // be the tile and adopting it would pin a wrong one forever.
    final cache = BitmapTileImageCache();
    final tile = inkedTile();
    late Uint8List seen;
    debugSyncImageUploadOverride = (pixels, _, _) {
      // Copied INSIDE the call: the scratch may be a window onto native
      // memory that is released the moment the call returns.
      seen = Uint8List.fromList(pixels);
      return aSolidImage();
    };

    cache.adoptSyncUpload(tile);

    final expected = BitmapTileImageCache.premultipliedTileUpload(tile);
    expect(seen, expected.view);
    expected.free();
    // Anti-vacuity: premultiplied is not straight here, so "same bytes"
    // is a statement about premultiplication and not just about copying.
    expect(
      seen[0],
      isNot(200),
      reason: 'a fixture whose straight and premultiplied bytes agree '
          'would make the comparison above prove nothing',
    );
  });

  test('it retires a stand-in and stands aside for a decode already in '
      'flight', () {
    final cache = BitmapTileImageCache();
    debugSyncImageUploadOverride = (_, _, _) => aSolidImage();

    final standingIn = inkedTile();
    cache.putProvisional(standingIn, aSolidImage());
    cache.adoptSyncUpload(standingIn);
    expect(cache.imageFor(standingIn), isNotNull);
    expect(
      cache.hasProvisional(standingIn),
      isFalse,
      reason: 'truth arrived, so the approximation has to go with it',
    );

    final decoding = BitmapTile.blank(coord: TileCoord(x: 1, y: 0), size: 2);
    cache.ensureDecoded(decoding);
    expect(
      cache.adoptSyncUpload(decoding),
      isNull,
      reason:
          'the in-flight decode lands later and overwrites the entry, so '
          'uploading here would leak the image it displaced',
    );
  });

  test('an engine that throws is asked once, not once per tile', () {
    final cache = BitmapTileImageCache();
    var calls = 0;
    debugSyncImageUploadOverride = (_, _, _) {
      calls += 1;
      // Skia throws a bare String — not an Exception, which is why the
      // catch in the cache is unqualified.
      throw 'Image::decodeImageFromPixelsSync is not implemented';
    };

    expect(cache.adoptSyncUpload(inkedTile()), isNull);
    expect(calls, 1);

    // The override is still installed, but the throw was the answer.
    expect(cache.adoptSyncUpload(inkedTile()), isNull);
    expect(
      calls,
      1,
      reason:
          'a per-tile retry would pay the premultiply and the throw on '
          'every undrawable coordinate of every paint',
    );
  });
}
