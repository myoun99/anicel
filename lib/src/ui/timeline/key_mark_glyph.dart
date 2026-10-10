import 'dart:typed_data';
import 'dart:ui';

import '../../models/key_mark.dart';
import '../../models/key_side.dart' show KeySideKind;

/// THE ONE DRAWING OF A KEY MARK (I-89 ②) — every key on the frame axis
/// wears it: the lanes, the group headers' unions, the camera rows of the
/// timeline and the storyboard, and the flip window.
///
/// After Effects' shapes, a half for each side (유저 10-10 「ae식
/// 반반등은 검증된 업계기준이라 아주 마음에들어」): the LEFT half is the side
/// arriving at the key, the RIGHT half the side leaving it. 🗣️All four
/// share ONE [size]-square box (유저 10-10 「모양의 크기는 동일한 느낌이
/// 좋으니 찬성」), so a diamond's points touch the box's edges — the halves
/// of two shapes could not meet down the middle otherwise.
///
/// ONE path for both halves, so the fill has no seam down the middle where
/// two antialiased edges would meet.
Path keyMarkPath(KeyMark mark, double size) {
  final unit = size / 12;
  return switch (mark) {
    SidesKeyMark(:final incoming, :final outgoing) =>
      Path()
        ..addPath(_half(incoming, right: false, unit: unit), Offset.zero)
        ..addPath(_half(outgoing, right: true, unit: unit), Offset.zero),
    // The union's ○ (F-17): the disc of 「부드럽게 지나감」 left hollow.
    MixedKeyMark() =>
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromLTWH(0, 0, size, size))
        ..addOval(
          Rect.fromCircle(
            center: Offset(size / 2, size / 2),
            radius: size * _mixedHole,
          ),
        ),
  };
}

/// How much of a mixed mark is hole: the radius of its inside, as a share
/// of its box.
const double _mixedHole = 0.32;

/// A quarter turn clockwise of the [size]-square box about its middle —
/// (x, y) to (size − y, x), its left edge onto its top.
Float64List _quarterTurn(double size) =>
    Float64List.fromList([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, size, 0, 0, 1]);

/// [mark] filled with [color] in the [size]-square box centred on
/// [center] — rung inside its edge with [ring] when that is given, the
/// lane selection's accent, as a plate's border is laid inside it.
///
/// [standing] turns it a quarter clockwise, as the X-sheet is the timeline
/// turned on its side: the half for the side arriving faces the frames
/// before the key, up the sheet — as the flip window's standing view, which
/// turns the timeline's whole layout, draws it too.
void paintKeyMark(
  Canvas canvas,
  KeyMark mark, {
  required Offset center,
  required double size,
  required bool standing,
  required Color color,
  ({Color color, double width})? ring,
}) {
  final laid = keyMarkPath(mark, size);
  final path = (standing ? laid.transform(_quarterTurn(size)) : laid).shift(
    center - Offset(size / 2, size / 2),
  );
  canvas.drawPath(path, Paint()..color = color);
  if (ring == null) {
    return;
  }
  canvas
    ..save()
    ..clipPath(path)
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        // Twice the width, half of it clipped away: the ring lies INSIDE.
        ..strokeWidth = ring.width * 2
        ..color = ring.color,
    )
    ..restore();
}

/// One side's HALF of a mark, alone, in the [size]-square box centred on
/// [center] — the left half for the side arriving at a key, the right for
/// the side [leaving] it: the key window's choice of a side wears the half
/// that kind draws on the frame axis (I-89 ②).
void paintKeySideMark(
  Canvas canvas,
  KeySideKind kind, {
  required bool leaving,
  required Offset center,
  required double size,
  required Color color,
}) => canvas.drawPath(
  _half(
    kind,
    right: leaving,
    unit: size / 12,
  ).shift(center - Offset(size / 2, size / 2)),
  Paint()..color = color,
);

/// One half on the 12-unit grid the mark is drawn on, [right] mirrored
/// about the middle.
Path _half(KeySideKind kind, {required bool right, required double unit}) {
  Offset at(double x, double y) =>
      Offset((right ? 12 - x : x) * unit, y * unit);
  Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
  return switch (kind) {
    KeySideKind.linear => polygon([at(6, 0), at(0, 6), at(6, 12)]),
    KeySideKind.ease =>
      polygon([at(0, 0), at(6, 0), at(6, 6)])
        ..addPolygon([at(0, 12), at(6, 12), at(6, 6)], true),
    KeySideKind.auto =>
      Path()
        ..moveTo(6 * unit, 0)
        ..arcToPoint(
          Offset(6 * unit, 12 * unit),
          radius: Radius.circular(6 * unit),
          clockwise: right,
        )
        ..close(),
    KeySideKind.hold => polygon([at(0, 0), at(6, 0), at(6, 12), at(0, 12)]),
  };
}
