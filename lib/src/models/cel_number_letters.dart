import 'canvas_point.dart';
import 'frame.dart' show celNumberOrMark;
import 'layer_kind.dart';

/// What a CEL NUMBER fx writes at one frame (I-65): [text] in [color], the
/// middle of its letters' box at [center] on the row's paper, [scale] times
/// the text tool's letter size along each axis. The row's placement lays it
/// where the row lies, so it moves with the picture (I-65-Q2 a: 「그림과
/// 함께 움직인다」).
class CelNumberLetters {
  CelNumberLetters({
    required this.text,
    required this.color,
    required this.center,
    required this.scale,
  });

  final String text;

  /// Opaque ARGB.
  final int color;
  final CanvasPoint center;
  final CanvasPoint scale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelNumberLetters &&
          other.text == text &&
          other.color == color &&
          other.center == center &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(text, color, center, scale);

  @override
  String toString() =>
      'CelNumberLetters($text, ${color.toRadixString(16)}, $center, $scale)';
}

/// What a cel number writes over a drawing named [drawingName] on a row
/// named [rowName] of [kind]: the row's name and the drawing's number run
/// together — 「A」 and 「1」 write 「A1」 — the drawing's number as its
/// block's head says it ([celNumberOrMark]): an unnamed animation drawing
/// writes the in-between mark, 「A○」, and an unnamed drawing of any other
/// kind nothing after the row's name.
///
/// 🗣️I-65-Q1 a (유저 2026-10-24): 「레이어 이름 + 셀 번호(A1) — 이름 없는
/// 그림은 A●」. ↩️「A●」 until F-469 (10-25 「기본마크, 앞으로 마크1 사용 …
/// 다른곳도 같은곳있으면 확인해서 법 통일」): the mark is the unnamed head's,
/// `unnamedDrawingMark`.
String celNumberText({
  required String rowName,
  required String? drawingName,
  required LayerKind kind,
}) => '$rowName${celNumberOrMark(drawingName, kind: kind)}';
