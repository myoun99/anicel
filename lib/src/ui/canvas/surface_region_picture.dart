import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/rgba_premultiply.dart';
import '../../core/sync_image_upload.dart';
import '../../models/bitmap_surface.dart';
import '../../models/dirty_region.dart';
import '../../models/tiles_covering.dart';
import '../../native/qa_native_engine.dart';
import '../../services/brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;

/// A fresh picture of [surface]'s pixels over [region], through the one door
/// ([pictureOf]): every tile the region covers where it sits, transparent
/// where the surface holds none. The caller's to dispose.
///
/// What a compose draws for a block of tiles that have no picture
/// (`tileBlocksOf`): one texture where a picture a tile was a texture each.
ui.Image surfaceRegionPicture(BitmapSurface surface, DirtyRegion region) =>
    pictureOf(SurfaceRegionBytes(surface, region));

/// [surface]'s pixels over [region] as the door reads them.
///
/// STRAIGHT: the region's own bytes as the surface holds them
/// ([bitmapSurfaceRegionPixels]). PREMULTIPLIED: every tile the region
/// covers ([tilesCovering]) premultiplied out of its own memory into the
/// engine's scratch at its place, one call a tile
/// ([QaNativeEngine.premultiplyRgbaRows]) — or, with no engine, the straight
/// bytes premultiplied where they lie ([premultiplyRgbaInPlace]). The same
/// bytes either way: the kernel is the Dart rounding's twin (parity-pinned).
class SurfaceRegionBytes implements PictureBytes {
  SurfaceRegionBytes(this.surface, this.region);

  final BitmapSurface surface;
  final DirtyRegion region;

  @override
  int get width => region.rightExclusive - region.left;

  @override
  int get height => region.bottomExclusive - region.top;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      use(bitmapSurfaceRegionPixels(surface, region));

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final native = QaNativeEngine.instance;
    if (native == null) {
      final bytes = bitmapSurfaceRegionPixels(surface, region);
      premultiplyRgbaInPlace(bytes);
      return use(bytes);
    }
    final byteLength = width * height * 4;
    final target = native.tilesPictureScratch(byteLength);
    final covered = tilesCovering(surface, region).toList();
    var coveredPixels = 0;
    for (final tile in covered) {
      coveredPixels +=
          (tile.rightExclusive - tile.left) * (tile.bottomExclusive - tile.top);
    }
    if (coveredPixels < width * height) {
      // The scratch still holds the last picture: where no tile lands, the
      // region is transparent.
      native.zeroBytes(target, byteLength);
    }
    for (final tile in covered) {
      premultiplyInto(native, tile, target);
    }
    return use(target.asTypedList(byteLength));
  }

  /// [tile]'s part of the region premultiplied out of its own memory into
  /// [target] where it lies in the region — its rows, the region's width a
  /// row. A step of [readPremultiplied], and of a compose past the wall,
  /// which premultiplies into memory of its own
  /// (`composePositionedSurfaceImage`).
  void premultiplyInto(
    QaNativeEngine native,
    CoveredTile tile,
    Pointer<Uint8> target,
  ) {
    final tileSize = surface.tileSize;
    tile.tile.readPixels(
      (pointer, _) => native.premultiplyRgbaRows(
        from: (
          start:
              pointer +
              ((tile.top - tile.worldTop) * tileSize +
                      (tile.left - tile.worldLeft)) *
                  4,
          stride: tileSize * 4,
        ),
        into: (
          start:
              target +
              ((tile.top - region.top) * width + (tile.left - region.left)) *
                  4,
          stride: width * 4,
        ),
        width: tile.rightExclusive - tile.left,
        rows: tile.bottomExclusive - tile.top,
      ),
    );
  }
}
