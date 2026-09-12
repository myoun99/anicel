import 'package:flutter/material.dart';

import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppColors;

/// 「아직 없는 것」 — the outline a drop would fill (미디어 배치 라운드 2d-2,
/// the mockup the user approved on 2026-09-11: 점선 강조색 블록).
///
/// It knows NO geometry. The box it paints into is placed by the span
/// layout every other frame-axis overlay is placed by, so a silhouette
/// cannot land on different pixels than the cells it stands over — the
/// frame→pixel arithmetic is written once, where it already was.
///
/// ⚠️Dashed on purpose, and the dash is the whole message: a solid accent
/// rect is what a SELECTION wears (`timelineRangeSelectionBandDecoration`),
/// and a drag that has not landed must not look like something that has.
class TimelineSilhouettePainter extends CustomPainter with RepaintOnProps {
  const TimelineSilhouettePainter({this.radius = 3});

  /// The block cap the cells wear, so the outline sits ON the block shape
  /// rather than beside it.
  final double radius;

  /// The dash, in logical pixels. Short enough to read as a dash on a
  /// one-cell block (22px in the mockup) — a longer one draws a single
  /// segment per side there, which is a solid rect with gaps at the
  /// corners.
  static const double _on = 4;
  static const double _off = 3;

  /// ⚠️**THE SECOND DASH WALK IN THIS APP, AND IT IS DELIBERATE.** The first
  /// is `canvas/selection_ants_painter.dart`'s private `_dashPath`: animated
  /// (its phase rides a ticker), white-under-stroked, and about a selection
  /// on the canvas. This one is static, single-stroked, and about a block
  /// that does not exist yet.
  ///
  /// Two is not the number that merges them (3의 규칙): pulled together now,
  /// the shared thing would have to carry a phase nobody here wants and a
  /// pair of colours nobody there wants. ⛔But the next one IS the third —
  /// written down because noticing it is not something to leave to memory.
  /// When it comes, the walk (metrics → extract on/off) is what moves.

  /// ⚠️A RECORD, not a list: a list compares by identity, so a fresh one per
  /// build would repaint this every frame of a drag. The accent is in here
  /// because it is LIVE (UI-R22 #5) — the painter reads it rather than
  /// taking it, so nothing else would notice it changing.
  @override
  Object get props => (radius, AppColors.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final accent = AppColors.accent;
    final box = RRect.fromRectAndRadius(
      // Inset by the stroke's half-width: a stroke centred on the box edge
      // loses its outer half to the clip, so the dashes read thinner on the
      // outside than the inside.
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      box,
      Paint()..color = accent.withValues(alpha: 0.16),
    );
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _on).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), stroke);
        distance += _on + _off;
      }
    }
  }
}
