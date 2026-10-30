/// A camera's work written as MARKS ([SheetMark]) — the one drawing every
/// surface writes it with: the conte's pictures (its panel, PNG and PDF),
/// the canvas, and the export (I-89 ④⑥).
///
/// 🗣️유저 2026-09-30, of the conte's corner trails: 「이 꼭짓점 궤도
/// 그리는건 카메라레이어에서도 나중에 쓸거니까 공용화 잘 해주고」. A surface
/// says WHICH marks it writes — whose frame is drawn — and how large, in its
/// own units; how a frame, a cross and a label are drawn, where they stand
/// and what a label says are decided here, once.
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
  last;

  /// The role of the key at [index] among [count] keys, first to last.
  static CameraKeyRole at(int index, int count) => index == 0
      ? first
      : index == count - 1
      ? last
      : between;
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

/// The crosses a camera's path wears in time on the canvas (I-89 ④, the
/// confirmed spec of 2026-10-10 and its mock, 5판): grey where the playhead
/// has passed, blue where it is yet to go — the one it stands on wears a
/// key between's ink.
const int cameraTickPastArgb = 0xFF8E9093;
const int cameraTickAheadArgb = 0xFF3A78C8;

/// The colour [role] wears: its frame, its cross and its label.
int cameraKeyArgb(CameraKeyRole role) => switch (role) {
  CameraKeyRole.first => cameraInArgb,
  CameraKeyRole.between => cameraBetweenArgb,
  CameraKeyRole.last => cameraOutArgb,
};

/// What a key is called on every surface — the canvas, the export and the
/// conte (유저 2026-10-12: 「카메라 출력궤도랑 완전통일해서 이름없으면
/// 프레임이름+f. 즉 1f 12f 이런식으로」): its [name], else the frame it
/// stands on ([cameraFrameLabel]). ↩️The conte called an unnamed first IN
/// and an unnamed last OUT, the Storyboard Pro rule, and left an unnamed
/// key between bare.
String cameraKeyLabel(String? name, int frameIndex) =>
    name ?? cameraFrameLabel(frameIndex);

/// A frame as a camera's marks write it — as the frame cursor counts it:
/// 1f, 12f.
String cameraFrameLabel(int frameIndex) => '${frameIndex + 1}f';

/// One key as a surface writes it: its cross at its frame's centre, where
/// the camera is, and its [label] at the frame's top-left corner — on every
/// surface alike (유저 2026-10-12: 「아까처럼 중앙에 두자 … 이 궤도 시스템은
/// 콘티용지패널이랑 정확히 동일. 즉 법 통일」). ↩️The conte crossed a named
/// key between alone, at its corner (H55), and its ends not at all. A cross
/// on every key's corner, to stand with its label, was asked for and taken
/// back the same day (「그냥 일단 십자가쪽 왼쪽위로 옮기자」 → 「취소할게」).
class CameraMarkedKey {
  const CameraMarkedKey({
    required this.corners,
    required this.role,
    required this.label,
    this.beside = const [],
  });

  /// The camera's frame at the key, on the surface: top-left first — or
  /// the one point a layer's position stands at, which has no frame to
  /// draw (I-89-Q9).
  final List<Offset> corners;

  final CameraKeyRole role;

  /// What is written at its frame's top-left corner, inside it and turned
  /// with it ([cameraKeyLabel]) — or, a point having no corner to write it
  /// in, beside its cross off the path [beside] it ([cameraCrossLabel]:
  /// I-89-Q9, 유저 2026-10-12 「이름 내가 카메라에서 말한대로
  /// 오른쪽아래,왼쪽아래 이런순으로 두려고 시도」).
  final String label;

  /// Where the path runs either side of a point's cross.
  final List<Offset> beside;
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

  /// How far a label sits inside its frame's corner, along both sides — and
  /// off a point's cross.
  final double labelInset;

  /// These sizes [factor] times over — one surface's in another's units.
  CameraMarkSizes scaledBy(double factor) => CameraMarkSizes(
    frameWidth: frameWidth * factor,
    trailWidth: trailWidth * factor,
    labelSize: labelSize * factor,
    crossArm: crossArm * factor,
    crossWidth: crossWidth * factor,
    labelInset: labelInset * factor,
  );
}

/// [trails], and over them each of [keys]: its frame, its cross and its
/// label — at [sizes], in [layer]. A key is all three on every surface
/// (I-82), so no surface can write one without its frame.
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
    if (!cameraPlaceIsAPoint(key.corners)) {
      yield SheetStroke(
        layer,
        points: key.corners,
        argb: argb,
        width: sizes.frameWidth,
        closed: true,
      );
    }
    final at = cameraFrameCentre(key.corners);
    yield* cameraCrossMarks(
      key.corners,
      at: at,
      argb: argb,
      arm: sizes.crossArm,
      width: sizes.crossWidth,
      layer: layer,
    );
    yield cameraPlaceIsAPoint(key.corners)
        ? cameraCrossLabel(
            key.label,
            key.corners,
            at: at,
            taken: key.beside,
            argb: argb,
            size: sizes.labelSize,
            gap: sizes.labelInset,
            layer: layer,
          )
        : _label(key.label, key.corners, argb, sizes, layer);
  }
}

/// Whether [corners] are one point — a layer's position, where a camera
/// has its frame (I-89-Q9).
bool cameraPlaceIsAPoint(List<Offset> corners) => corners.length == 1;

/// The middle of the frame [corners] draw — where the camera is — or the
/// point they are.
Offset cameraFrameCentre(List<Offset> corners) => cameraPlaceIsAPoint(corners)
    ? corners.single
    : (corners[0] + corners[2]) / 2;

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

/// The quarters about a cross a label may stand in, square to its frame,
/// in the order a label takes the first free one (유저 2026-10-12: 「십자가
/// 오른쪽아래,왼쪽아래,오른쪽위,왼쪽위 우선순위는 이 순서대로 빈공간에」).
const List<({bool left, bool above})> _labelQuarters = [
  (left: false, above: false),
  (left: true, above: false),
  (left: false, above: true),
  (left: true, above: true),
];

/// How wide a label's slot beside a cross is, in letters of its size: room
/// for a frame like 「120f」. Words that outrun it are clipped.
const double _crossLabelLetters = 4;

/// [label] beside the cross at [at], square to the frame [corners] draw
/// and turned with it, in the first quarter about the cross where none of
/// [taken] lies — the crosses either side of it along the camera's path,
/// so the label stands off the way the path runs ([_labelQuarters]). With
/// every quarter taken, it stands below and right. [gap] keeps it off the
/// cross's arms. [after] labels already stand beside the cross, in the
/// first quarters this order gives: this one takes the quarter after
/// theirs, a taken one once the free run out (a named point's frame,
/// beside its name — I-89-Q9).
SheetWords cameraCrossLabel(
  String label,
  List<Offset> corners, {
  required Offset at,
  required Iterable<Offset> taken,
  required int argb,
  required double size,
  required double gap,
  required SheetPaintLayer layer,
  int after = 0,
}) {
  final (:right, :down, :turn) = _frameAxes(corners);
  bool holds(({bool left, bool above}) quarter, Offset point) {
    final x = _dot(point - at, right);
    final y = _dot(point - at, down);
    return (quarter.left ? x < 0 : x > 0) && (quarter.above ? y < 0 : y > 0);
  }

  bool free(({bool left, bool above}) quarter) =>
      !taken.any((point) => holds(quarter, point));
  // The free quarters in turn, then the taken ones: a label after others
  // never stands on theirs.
  final quarters = [
    ..._labelQuarters.where(free),
    ..._labelQuarters.where((quarter) => !free(quarter)),
  ];
  final quarter = quarters[after % quarters.length];
  final width = size * _crossLabelLetters;
  final height = size * 1.25;
  final origin =
      at +
      right * (quarter.left ? -(gap + width) : gap) +
      down * (quarter.above ? -(gap + height) : gap);
  return SheetWords(
    layer,
    text: label,
    slot: Rect.fromLTWH(origin.dx, origin.dy, width, height),
    size: size,
    argb: argb,
    bold: true,
    h: quarter.left ? SheetAlign.end : SheetAlign.start,
    v: quarter.above ? SheetAlign.end : SheetAlign.start,
    fit: SheetWordsFit.oneLine,
    turn: turn,
  );
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Which way the frame [corners] draw runs from its top-left corner —
/// along its top side ([right]) and down its left ([down]), at [turn]
/// radians — for what stands square to a turned frame. A point stands
/// square to the surface, as After Effects marks a motion path's keys.
({Offset right, Offset down, double turn}) _frameAxes(List<Offset> corners) {
  if (cameraPlaceIsAPoint(corners)) {
    return (right: const Offset(1, 0), down: const Offset(0, 1), turn: 0);
  }
  final along = corners[1] - corners[0];
  final turn = math.atan2(along.dy, along.dx);
  return (
    right: Offset(math.cos(turn), math.sin(turn)),
    down: Offset(-math.sin(turn), math.cos(turn)),
    turn: turn,
  );
}

/// [label] at the top-left corner of the frame [corners] draw, inside it
/// and turned with it — on the trail that corner draws.
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
