import 'package:flutter/material.dart';

import '../dashed_path.dart';
import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppColors;
import 'axis_turn.dart';
import 'timeline_cell_style.dart' show timelineBlockCornerRadiusAt;

/// 「아직 없는 것」 — the outline a drop would fill (미디어 배치 라운드 2d-2,
/// the mockup the user approved on 2026-09-11: 점선 강조색 블록).
///
/// It knows NO geometry. The box it paints into is placed by the span
/// layout every other frame-axis overlay is placed by, so a silhouette
/// cannot land on different pixels than the cells it stands over — the
/// frame→pixel arithmetic is written once, where it already was.
///
/// ⚠️Dashed on purpose, and the dash is the whole message: a solid accent
/// rect is what a SELECTION wears (`timelineRangeSelectionBandDecorationAt`),
/// and a drag that has not landed must not look like something that has.
class TimelineSilhouettePainter extends CustomPainter with RepaintOnProps {
  const TimelineSilhouettePainter({required this.frames, required this.axis});

  /// How many frames the box spans, and which way they run: the outline reads
  /// the block corner LAW off its own box ([timelineBlockCornerRadiusAt] — a
  /// cell is the box's along extent over [frames]), so it sits ON the block
  /// shape rather than beside it at every zoom, and a zoom step that resizes
  /// the box re-rounds it.
  ///
  /// ⛔It carried its own 3 — the "block cap the cells wear", written down
  /// once while the cells wore 6, so it never was.
  final int frames;
  final Axis axis;

  /// The dash, in logical pixels. Short enough to read as a dash on a
  /// one-cell block (22px in the mockup) — a longer one draws a single
  /// segment per side there, which is a solid rect with gaps at the
  /// corners.
  static const DashPattern _dashes = DashPattern(on: 4, off: 3);

  // ↩️**THIS WAS THE SECOND DASH WALK IN THE APP, AND DELIBERATELY ITS
  // OWN.** The first was `canvas/selection_ants_painter.dart`'s private
  // `_dashPath`: animated (its phase rides a ticker), white-under-stroked,
  // and about a selection on the canvas. This one is static,
  // single-stroked, and about a block that does not exist yet.
  //
  // Two was not the number that merged them (3의 규칙): pulled together
  // then, the shared thing would have had to carry a phase nobody here
  // wants and a pair of colours nobody there wants. ⛔But the next one WAS
  // the third — written down because noticing it is not something to leave
  // to memory: 「when it comes, the walk (metrics → extract on/off) is what
  // moves」.
  //
  // It came twice — the repeat span's, unnoticed, and then the text tool's
  // resting boxes (R9-rest, 2026-10-06) — and the walk moved, as written:
  // `dashesAlong` (`ui/dashed_path.dart`). What each painter does WITH a
  // dash stayed its own, so no phase and no second colour came here.

  /// ⚠️A RECORD, not a list: a list compares by identity, so a fresh one per
  /// build would repaint this every frame of a drag. The accent is in here
  /// because it is LIVE (UI-R22 #5) — the painter reads it rather than
  /// taking it, so nothing else would notice it changing.
  @override
  Object get props => (frames, axis, AppColors.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || frames <= 0) {
      return;
    }
    final accent = AppColors.accent;
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      timelineBlockCornerRadiusAt(
        cellExtent: extentAlong(axis, size) / frames,
        crossExtent: extentAcross(axis, size),
      ),
      // Inset by the stroke's half-width: a stroke centred on the box edge
      // loses its outer half to the clip, so the dashes read thinner on the
      // outside than the inside. Deflating the ROUNDED box keeps the dashes
      // concentric with the block's own corner.
    ).deflate(0.5);
    canvas.drawRRect(
      box,
      Paint()..color = accent.withValues(alpha: 0.16),
    );
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final dash in dashesAlong(Path()..addRRect(box), _dashes)) {
      canvas.drawPath(dash, stroke);
    }
  }
}
