/// A camera's work written as MARKS ([SheetMark]) — the one drawing every
/// surface writes it with: the conte's pictures (its panel, PNG and PDF),
/// the canvas, and the export (I-89 ④⑥).
///
/// 🗣️유저 2026-09-30, of the conte's corner trails: 「이 꼭짓점 궤도
/// 그리는건 카메라레이어에서도 나중에 쓸거니까 공용화 잘 해주고」. A surface
/// says WHICH marks it writes — whose frame is drawn, where a cross stands,
/// what a label says — and how large, in its own units; how a frame, a
/// cross and a label are drawn is decided here, once.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'sheet_marks.dart';
import 'sheet_paint_layer.dart';

/// Where a key stands among the keys a surface writes — the colour it
/// wears.
enum CameraKeyRole {
  /// The first: IN's green.
  first,

  /// One between the first and the last: the sheet's black.
  between,

  /// The last: OUT's red.
  last,
}

/// A camera's first key, frame and label — Storyboard Pro's IN green; its
/// last key wears OUT's red (유저 2026-09-29: 「스토리보드 프로는 인을
/// 초록색으로 실루엣이나 텍스트 그리고, 아웃을 빨간색이야」).
const int cameraInArgb = 0xFF3B6D11;
const int cameraOutArgb = 0xFFA32D2D;

/// A key between the first and the last: its name and its cross, in the
/// sheet's own black (유저 2026-10-01, H55: 「작고 검정색으로? 그리고 그
/// 색으로 키 색도 바꾸고」) — the canvas's 먹색 too (유저 2026-10-11).
/// ↩️The name was 0xFF5F5E5A, the grey the trails still wear.
const int cameraBetweenArgb = 0xFF101010;

/// The trail a camera draws: a grey at half its strength (유저 2026-09-30,
/// H47: 「꼭짓점 궤도 좀 더 연하게.(불투명도 낮추는방식)」) — every printer
/// keeps the alpha, the PDF's too. ⚠️Its own grey, no longer a key
/// between's ink at half strength: that ink went black (H55), and the
/// trails stay as light as H47 made them.
const int cameraTrailArgb = 0x805F5E5A;

/// The colour [role] wears: its frame, its cross and its label.
int cameraKeyArgb(CameraKeyRole role) => switch (role) {
  CameraKeyRole.first => cameraInArgb,
  CameraKeyRole.between => cameraBetweenArgb,
  CameraKeyRole.last => cameraOutArgb,
};

/// Where a key's cross stands, if it wears one.
enum CameraKeyCross {
  none,

  /// On its frame's top-left corner, with its label.
  corner,

  /// On its frame's centre — where the camera is.
  centre,
}

/// One key as a surface writes it.
class CameraMarkedKey {
  const CameraMarkedKey({
    required this.corners,
    required this.role,
    required this.framed,
    this.cross = CameraKeyCross.none,
    this.label,
  });

  /// The camera's frame at the key, on the surface: top-left first.
  final List<Offset> corners;

  final CameraKeyRole role;

  /// Whether its frame is drawn.
  final bool framed;

  final CameraKeyCross cross;

  /// What is written at its frame's top-left corner, turned with it — or
  /// nothing.
  final String? label;
}

/// How large a surface writes a camera's marks, in its own units.
class CameraMarkSizes {
  const CameraMarkSizes({
    required this.frameWidth,
    required this.trailWidth,
    required this.labelSize,
    required this.crossArm,
    required this.crossWidth,
    required this.labelInset,
  });

  final double frameWidth;
  final double trailWidth;
  final double labelSize;

  /// How far each arm of a key's cross reaches from where it stands.
  final double crossArm;
  final double crossWidth;

  /// How far a label sits inside its frame's corner, along both sides.
  final double labelInset;
}

/// [trails], and over them each of [keys]: its frame, its cross and its
/// label — at [sizes], in [layer].
Iterable<SheetMark> cameraWorkMarks({
  required Iterable<List<Offset>> trails,
  required Iterable<CameraMarkedKey> keys,
  required CameraMarkSizes sizes,
  required SheetPaintLayer layer,
}) sync* {
  for (final trail in trails) {
    yield SheetStroke(
      layer,
      points: trail,
      argb: cameraTrailArgb,
      width: sizes.trailWidth,
    );
  }
  for (final key in keys) {
    final argb = cameraKeyArgb(key.role);
    if (key.framed) {
      yield SheetStroke(
        layer,
        points: key.corners,
        argb: argb,
        width: sizes.frameWidth,
        closed: true,
      );
    }
    final at = switch (key.cross) {
      CameraKeyCross.none => null,
      CameraKeyCross.corner => key.corners[0],
      CameraKeyCross.centre => cameraFrameCentre(key.corners),
    };
    if (at != null) {
      yield* cameraCrossMarks(
        key.corners,
        at: at,
        argb: argb,
        arm: sizes.crossArm,
        width: sizes.crossWidth,
        layer: layer,
      );
    }
    if (key.label case final label?) {
      yield _label(label, key.corners, argb, sizes, layer);
    }
  }
}

/// The middle of the frame [corners] draw — where the camera is.
Offset cameraFrameCentre(List<Offset> corners) =>
    (corners[0] + corners[2]) / 2;

/// A cross at [at], square to the frame [corners] draw — it turns with the
/// frame as the label does: two strokes, each reaching [arm] either way.
Iterable<SheetStroke> cameraCrossMarks(
  List<Offset> corners, {
  required Offset at,
  required int argb,
  required double arm,
  required double width,
  required SheetPaintLayer layer,
}) sync* {
  final (:right, :down, turn: _) = _frameAxes(corners);
  for (final axis in [right, down]) {
    yield SheetStroke(
      layer,
      points: [at - axis * arm, at + axis * arm],
      argb: argb,
      width: width,
    );
  }
}

/// Which way the frame [corners] draw runs from its top-left corner —
/// along its top side ([right]) and down its left ([down]), at [turn]
/// radians — for what stands square to a turned frame.
({Offset right, Offset down, double turn}) _frameAxes(List<Offset> corners) {
  final along = corners[1] - corners[0];
  final turn = math.atan2(along.dy, along.dx);
  return (
    right: Offset(math.cos(turn), math.sin(turn)),
    down: Offset(-math.sin(turn), math.cos(turn)),
    turn: turn,
  );
}

/// [label] at the top-left corner of the frame [corners] draw, inside it
/// and turned with it.
SheetWords _label(
  String label,
  List<Offset> corners,
  int argb,
  CameraMarkSizes sizes,
  SheetPaintLayer layer,
) {
  final along = corners[1] - corners[0];
  final (:right, :down, :turn) = _frameAxes(corners);
  final at = corners[0] + (right + down) * sizes.labelInset;
  return SheetWords(
    layer,
    text: label,
    slot: Rect.fromLTWH(
      at.dx,
      at.dy,
      math.max(0, along.distance - 2 * sizes.labelInset),
      sizes.labelSize * 1.25,
    ),
    size: sizes.labelSize,
    argb: argb,
    bold: true,
    fit: SheetWordsFit.oneLine,
    turn: turn,
  );
}
