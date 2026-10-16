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
/// arriving at the key, the RIGHT half the side leaving it — and a star's
/// point for 「급하게」, which AE has no shape of its own for. 🗣️Every shape
/// shares ONE [size]-square box (유저 10-10 「모양의 크기는 동일한 느낌이
/// 좋으니 찬성」), so a diamond's points touch the box's edges — the halves
/// of two shapes could not meet down the middle otherwise.
///
/// ONE outline round both halves — down the left from the top of the
/// middle, back up the right — so there is no edge down the middle where
/// the halves meet: the fill has no seam, and the selection's ring is a
/// thin stroke of the SILHOUETTE (UI-R23 #4), not a bar between the halves.
Path keyMarkPath(KeyMark mark, double size) {
  final unit = size / 12;
  switch (mark) {
    case SidesKeyMark(:final incoming, :final outgoing):
      final path = Path()..moveTo(6 * unit, 0);
      _walkHalf(path, incoming, right: false, unit: unit);
      _walkHalf(path, outgoing, right: true, unit: unit);
      return path..close();
    // The union's ◉ (F-17 · F-367-Q2): the disc of 「부드럽게 지나감」 with a
    // thin ring cut out of it.
    case MixedKeyMark():
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromLTWH(0, 0, size, size))
        ..addOval(_middleCircle(size, _mixedGap))
        ..addOval(_middleCircle(size, _mixedCore));
    // A roving key (I-89 ④ · F-367): a pill lying along the frame axis —
    // as wide as any key, lower than all of them, so 「부드럽게 지나감」's
    // whole disc stays its own.
    case RovingKeyMark():
      final low = size * _rovingHeight;
      return Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, (size - low) / 2, size, low),
          Radius.circular(low / 2),
        ),
      );
  }
}

/// The circle about the middle of the [size]-square box whose radius is
/// [share] of the box.
Rect _middleCircle(double size, double share) =>
    Rect.fromCircle(center: Offset(size / 2, size / 2), radius: size * share);

/// Where a mixed mark's cut ring runs: from its core's edge out to this
/// radius, as a share of its box — a gap of 0.08 of the box.
///
/// 🗣️F-367-Q2 (유저 2026-10-16): 「혼합 ○도 고친다 — 구멍을 메우고 가는 틈만
/// 남긴다(◉)」 · 「혼합키만 속이 비어있으니 그냥 마크 다른걸로」. ↩️It was a ○
/// with a hole of [_mixedCore] — 「중간 비어있어서 글자가 검은색이라
/// 안보이는거같은데」: a key's name went unread over it.
const double _mixedGap = 0.40;

/// The radius of a mixed mark's core, as a share of its box — the old ○'s
/// hole, filled.
const double _mixedCore = 0.32;

/// How high a roving key's pill stands, as a share of its box; its ends are
/// round.
///
/// 🗣️F-367 (유저 2026-10-16 23:12): 「다시 정정. 아티팩트 보니 맘이 바뀜.
/// 로빙키 누운 알약으로」 — ↩️over the 23:10 answer 「그냥 로빙키 그대로 둬도
/// 될듯. ae랑 같은 규칙이니까」. ↩️It was After Effects' dot, half as wide as
/// the box.
const double _rovingHeight = 0.6;

/// Whether [mark] lets what is under it show through its middle — the
/// union's ◉ (F-17 · F-367-Q2), the one mark with a gap in it — so the line
/// between a row's keys stops at its edge rather than run across the gap
/// (`strokeKeysLineClearOf`).
bool keyMarkIsHollow(KeyMark mark) => mark is MixedKeyMark;

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

/// [path] carried round one half's edge on the 12-unit grid the mark is
/// drawn on, from one end of the middle line to the other: the left half
/// top to bottom, the right half — its mirror — bottom to top.
void _walkHalf(
  Path path,
  KeySideKind kind, {
  required bool right,
  required double unit,
}) {
  Offset at(double x, double y) =>
      Offset((right ? 12 - x : x) * unit, y * unit);
  final end = at(6, right ? 0 : 12);
  void through(List<Offset> corners) {
    for (final corner in right ? corners.reversed : corners) {
      path.lineTo(corner.dx, corner.dy);
    }
    path.lineTo(end.dx, end.dy);
  }

  switch (kind) {
    case KeySideKind.linear:
      through([at(0, 6)]);
    case KeySideKind.ease:
      // An hourglass's halves meet at its waist, in the middle.
      through([at(0, 0), at(6, 6), at(0, 12)]);
    case KeySideKind.fast:
      // A diamond's sides drawn in toward its middle: the star's point is
      // sharper than the straight side's, as its speed is past the average.
      through([at(4.5, 4.5), at(0, 6), at(4.5, 7.5)]);
    case KeySideKind.auto:
      // Round the outside, whichever way the half walks.
      path.arcToPoint(
        end,
        radius: Radius.circular(6 * unit),
        clockwise: false,
      );
    case KeySideKind.hold:
      through([at(0, 0), at(0, 12)]);
  }
}
