import 'package:anicel/src/models/brush_dab.dart';

/// What a fill's stamp pieces lay, read where the canvas lands them
/// ([BrushStampImage.landingRect]) — a fill and an area arrive as one stamp
/// per cel tile they cover (`buildFillDabs` · `buildRegionFillDabs`), and a
/// reader that asks 「what lands at this pixel」 or 「how far does it reach」
/// asks every piece.

/// The RGBA the pieces lay at canvas ([x], [y]): the one piece that covers
/// it, or transparent where none does.
List<int> piecesRgbaAt(List<BrushDab> pieces, int x, int y) {
  for (final piece in pieces) {
    final stamp = piece.stamp!;
    final landing = stamp.landingRect(piece.center);
    final lx = x - landing.left;
    final ly = y - landing.top;
    if (lx < 0 || ly < 0 || lx >= stamp.width || ly >= stamp.height) {
      continue;
    }
    final at = (ly * stamp.width + lx) * 4;
    return stamp.rgba.sublist(at, at + 4);
  }
  return const [0, 0, 0, 0];
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
