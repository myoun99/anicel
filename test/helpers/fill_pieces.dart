import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';

import 'surface_rgba_in_place.dart';

/// What a fill's stamp pieces lay, read where the canvas lands them
/// ([BrushStampImage.landingRect]) — a fill and an area arrive as one stamp
/// per run of cel tiles they cover (`FillRange.dabsIn` ·
/// `buildRegionFillDabs`), and a reader that asks 「what lands at this
/// pixel」 or 「how far does it reach」 asks every piece.
///
/// ⚠️On the engine, which is what paints a piece: no byte of its picture is
/// made anywhere else (`_pieceDab`, 2026-11-15). A file reading them opens
/// the engine first (`opensTheEnginesScreens`).

/// [pieces] landed at full strength on a blank cel by the commit's own
/// road ([materializeBrushDabSequenceOnBitmapSurface]) — what their stamps
/// are, whatever opacity they are laid at. Landed once for the list,
/// however many of its pixels are read.
BitmapSurface piecesLanded(List<BrushDab> pieces) =>
    _landed[pieces] ??= materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: _room),
      sequence: BrushDabSequence([
        for (final piece in pieces) piece.copyWith(opacity: 1),
      ]),
    ).surface;

final _landed = Expando<BitmapSurface>();

/// A cel larger than any a test fills, its pasteboard round it.
const _room = CanvasSize(width: 4096, height: 4096);

/// The RGBA the pieces lay at canvas ([x], [y]), transparent where none
/// does.
List<int> piecesRgbaAt(List<BrushDab> pieces, int x, int y) {
  final word = surfaceRgbaInPlace(piecesLanded(pieces), x, y) ?? 0;
  return [word >> 24 & 0xFF, word >> 16 & 0xFF, word >> 8 & 0xFF, word & 0xFF];
}

/// The coverage the pieces lay at canvas ([x], [y]).
int piecesAlphaAt(List<BrushDab> pieces, int x, int y) =>
    piecesRgbaAt(pieces, x, y)[3];

/// The box the pieces cover together, right and bottom exclusive — what
/// one stamp over the whole fill measured as its size.
({int left, int top, int width, int height}) piecesBox(List<BrushDab> pieces) {
  var left = 1 << 30;
  var top = 1 << 30;
  var right = -(1 << 30);
  var bottom = -(1 << 30);
  for (final piece in pieces) {
    final landing = piece.stamp!.landingRect(piece.center);
    if (landing.left < left) left = landing.left;
    if (landing.top < top) top = landing.top;
    if (landing.rightExclusive > right) right = landing.rightExclusive;
    if (landing.bottomExclusive > bottom) bottom = landing.bottomExclusive;
  }
  return (left: left, top: top, width: right - left, height: bottom - top);
}
