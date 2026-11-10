import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import '../../../core/rgba_premultiply.dart';
import '../../../core/sync_image_upload.dart';
import '../../../models/bitmap_tile.dart';
import '../../../models/dirty_region.dart';
import '../../../models/tile_coord.dart';
import '../../../services/bitmap_surface_geometry.dart' show tilesOfRegion;
import '../deferred_image_disposal.dart';
import '../display_resample.dart' show drawImageRectOnThePixelGrid;
import '../landing_preview.dart';
import '../selection_float_overlay.dart';

/// THE TEXT IN HAND AS THE CANVAS FLOATS IT (F-344): its pixels over the
/// hole its lifting left in its cel, as far as a hand has carried them, and
/// the cel's texts above it over those, as they stand.
///
/// 🗣️유저 2026-10-12: 「텍스트도구, 잡고 이동할때나 변형할때나 너무 느림.
/// 변형로직같은거 참고/재사용하면서 라이브 빠르게 움직이도록 구조개편」. Each of
/// the two IS a lifted selection's float — its pure move — so the hole is
/// made once, when the text is taken in hand, and a move of the hand moves
/// these pixels and nothing else. No plate is cut again, and no tile is
/// stamped or pictured again.
///
/// 🚨WHAT IS SEEN IS WHAT LANDS. A text moved by whole pixels lands as its
/// plate moved (`CelTextSession.showMoved`), which is [held]'s pixels at
/// its offset. The texts above it are over it on the cel, so they are over
/// it here too.
///
/// ⚠️BUT NOT TO THE BYTE WHERE IT LIES OVER INK: its partly clear pixels
/// are blended here where the landing stamps them — one apart at most, the
/// cost of the transform tool's float too (measured,
/// `a_carried_text_shows_what_it_lands_as_test`). On a row with a colour
/// key each of the two would be keyed by itself, where the landing keys
/// the text with the ink under it — so there the canvas floats
/// [CelTextLanding] instead (F-344-Q3).
@immutable
class CelTextFloat implements LandingPreview {
  const CelTextFloat({required this.held, required this.above});

  /// The text in hand: the pixels of its plate where it was set — through
  /// its row's keys, as its cel shows them — carried as far as a hand has
  /// carried them.
  final SelectionFloatPaint held;

  /// The texts of the cel above the one in hand, where they stand — none
  /// for a text that is new, which goes on top.
  final SelectionFloatPaint? above;

  @override
  Rect get drawnWorldRect {
    final under = held.drawnWorldRect;
    final over = above?.drawnWorldRect ?? Rect.zero;
    if (over.isEmpty) {
      return under.isEmpty ? Rect.zero : under;
    }
    return under.isEmpty ? over : under.expandToInclude(over);
  }

  @override
  void paintInto(Canvas canvas, {required double pixelRatio}) {
    held.paintInto(canvas, pixelRatio: pixelRatio);
    above?.paintInto(canvas, pixelRatio: pixelRatio);
  }

  @override
  List<HeldTiles> get heldTiles => [...held.heldTiles, ...?above?.heldTiles];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextFloat && other.held == held && other.above == above;

  @override
  int get hashCode => Object.hash(held, above);
}

/// THE TEXT IN HAND ON A ROW THAT KEYS ITS COLOURS (F-344-Q3): what its
/// cel will show where the text's ink lies once it lands — made by the
/// landing's own code (`celTextLandingAsShown`) — drawn over the cel
/// without it IN PLACE OF what that shows there.
///
/// 🗣️유저 2026-10-15: 「놓을 때와 같은 코드로 — 완전히 같게」 — the same
/// bytes before the text is let go of and after, at every zoom (F-240
/// halves this as it halves the landed tiles). The cost was put to 유저
/// with the answer: the region is made again at every move of the hand,
/// so a large text drags slower on such a row than on another.
///
/// 🚨IT REPLACES, it does not blend ([BlendMode.src]): the region is the
/// cel there, texts, ink and keys, and whatever the cel without the text
/// drew under it is not part of it. That is safe because a row with a
/// landing preview never draws straight onto what is below it — its
/// painter says its draws overlap (`BitmapSurfacePainter
/// .drawsDisjointCoverage`), so the stack gives the row a buffer of its
/// own (`the_layer_rides_the_draws_test`) — and the painter of the row
/// being drawn on lays no paper in it: the stack lays the paper under
/// every row.
///
/// A selection's float lands as the same thing, on such a row, wherever its
/// own pixels are not what its landing shows (`FloatLandsOn.landingShown`,
/// transform-float-skips-colour-key).
///
/// ⚠️[picture] is let go of by whoever shows this, once it shows it no
/// more ([letGo]).
class CelTextLanding implements LandingPreview {
  CelTextLanding({
    required Image picture,
    required this.tiles,
    required this.left,
    required this.top,
  }) : _picture = picture,
       _width = picture.width,
       _height = picture.height,
       _straight = null;

  /// [tiles] — where a landing left them, over [region] — shown as they
  /// stand: nothing of them comes off the engine to be carried, and a
  /// picture of [straight] is made only for a canvas that asks ([picture]).
  ///
  /// 🔬A float on a posed row is its landing, made again at each place a
  /// hand carries it to, and read back here it was a GPU wait a tile: about
  /// 187 a frame on S5_BA's paper, a whole-paper float dragged at 360–480 ms
  /// a frame (Surface Pro 11, 검증/서피스 11-10, flip lane).
  CelTextLanding.standing(
    DirtyRegion region,
    this.tiles,
    Uint8List Function() straight,
  ) : _picture = null,
      _width = region.width,
      _height = region.height,
      _straight = straight,
      left = region.left,
      top = region.top;

  /// The picture of [straight] — rgba of [region], a row its width —
  /// through the door every tile takes ([pictureOf]), so its bytes are the
  /// bytes the landed tiles are pictured to; and those bytes as tiles.
  factory CelTextLanding.of(DirtyRegion region, Uint8List straight) =>
      CelTextLanding(
        picture: pictureOf(
          _StraightRows(straight, region.width, region.height),
        ),
        tiles: tilesOfRegion(region, straight),
        left: region.left,
        top: region.top,
      );

  final int _width;
  final int _height;
  final Uint8List Function()? _straight;
  Image? _picture;

  Image get picture => _picture ??= pictureOf(
    _StraightRows(_straight!(), _width, _height),
  );

  /// [picture]'s bytes as tiles, where they stand: what the engine lays
  /// ([heldTiles]).
  final Map<TileCoord, BitmapTile> tiles;
  final int left;
  final int top;

  static final Paint _replacing = Paint()
    ..blendMode = BlendMode.src
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  @override
  Rect get drawnWorldRect => Rect.fromLTWH(
    left.toDouble(),
    top.toDouble(),
    _width.toDouble(),
    _height.toDouble(),
  );

  /// Its edge cut on the grid, as the coordinates it stands over are
  /// (`drawImageRectOnThePixelGrid`).
  @override
  void paintInto(Canvas canvas, {required double pixelRatio}) {
    final size = Size(picture.width.toDouble(), picture.height.toDouble());
    drawImageRectOnThePixelGrid(
      canvas,
      picture,
      Offset.zero & size,
      Offset(left.toDouble(), top.toDouble()) & size,
      filterQuality: FilterQuality.none,
      pixelRatio: pixelRatio,
      paint: _replacing,
    );
  }

  @override
  List<HeldTiles> get heldTiles => [
    (
      tiles: tiles,
      dx: 0,
      dy: 0,
      laying: LaidReplacing(drawnWorldRect),
    ),
  ];

  /// Lets [picture] go — past the frames that may still draw it
  /// ([DeferredImageDisposer]).
  void letGo() {
    if (_picture case final made?) {
      DeferredImageDisposer.instance.retire(made);
    }
  }
}

/// Straight rgba rows held in a list, as the picture door reads them.
class _StraightRows implements PictureBytes {
  _StraightRows(this._straight, this.width, this.height);

  final Uint8List _straight;

  @override
  final int width;

  @override
  final int height;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) => use(_straight);

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(premultipliedRgbaCopy(_straight));
}
