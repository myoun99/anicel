import 'dart:math' as math;
import 'dart:ui';

/// HOW A LINE IS DASHED: [on] of line and then [off] of none, the pattern
/// slid [phase] back along the line.
class DashPattern {
  const DashPattern({required this.on, required this.off, this.phase = 0});

  final double on;
  final double off;

  /// How far the pattern has slid back along the line, for dashes that
  /// march: the first dash starts `-phase` on from a contour's start, taken
  /// into the pattern's own length.
  ///
  /// ⚠️What that leaves of a dash BEFORE the start is not drawn: a marching
  /// line opens each contour on a gap that closes as it marches. The ants
  /// always have, and a walk that drew that piece would change them.
  final double phase;

  /// One dash and the gap after it.
  double get period => on + off;

  /// This pattern, slid [phase] back.
  DashPattern marchedBy(double phase) =>
      DashPattern(on: on, off: off, phase: phase);
}

/// THE DASHES OF A LINE: [source] walked contour by contour as [dashes]
/// says, each dash a path of its own.
///
/// 🚨ONE WALK. Three painters each walked a path this way by hand — the
/// selection's ants, the timeline's repeat span and its drop silhouette —
/// and the text tool's resting boxes would have been the fourth (R9-rest,
/// 2026-10-06; the same algorithm written apart is a copy, whatever its
/// text looks like). They differ in what they do WITH a dash — stroke each,
/// or gather them into one path — and in nothing about where a dash is, so
/// where a dash is, is what is here.
Iterable<Path> dashesAlong(Path source, DashPattern dashes) sync* {
  for (final metric in source.computeMetrics()) {
    for (
      var start = -dashes.phase % dashes.period;
      start < metric.length;
      start += dashes.period
    ) {
      yield metric.extractPath(
        start,
        math.min(start + dashes.on, metric.length),
      );
    }
  }
}

/// Draws [outline] as a dashed line that reads on ANY artwork: white along
/// the whole of it, and over that its [dashes] in [color].
///
/// 🗣️유저 (F-65): 「흰색바탕에 검정 개미가 지나가도록. **앞으로 개미행렬은 이
/// 공통 ui를 사용**」 — the white is what keeps the dashes readable on dark
/// artwork and the dashes what keep the white readable on light: the pair
/// is the line, not the dash alone. The selection's ants are this with
/// black dashes that march; a line that stands still has no phase.
void paintDashedOutline(
  Canvas canvas,
  Path outline, {
  required Color color,
  required DashPattern dashes,
}) {
  Paint stroke(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = color;
  canvas.drawPath(outline, stroke(const Color(0xFFFFFFFF)));
  final dashed = Path();
  for (final dash in dashesAlong(outline, dashes)) {
    dashed.addPath(dash, Offset.zero);
  }
  canvas.drawPath(dashed, stroke(color));
}
