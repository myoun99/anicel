import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The のりしろ boundary in the row BODY — the same mark
/// [TimelineRulerNoriShiroBoundary] draws in the ruler, minus the letters.
///
/// 🚨Why this exists at all: the ruler-only line read as a stub that stopped
/// at the header (user 2026-08-11 — 「룰러에서 끊기니까」). The red cut-end line
/// has always been a ruler/body pair for exactly this reason
/// ([TimelineRulerCutEndBoundary] + [TimelineBodyCutEndBoundary]), and a
/// length mark has to be as readable as the end mark it sits beside.
///
/// Stack order matters: mount this AFTER the outside-cut wash so the line sits
/// on top of it, and give the wash the DRAWN end as its start — のりしろ frames
/// are drawn material, so the "outside the cut" shading belongs behind this
/// line rather than over it.
class TimelineBodyNoriShiroBoundary extends StatelessWidget {
  const TimelineBodyNoriShiroBoundary({
    super.key = const ValueKey<String>('timeline-norishiro-boundary'),
    required this.left,
    required this.cutEnd,
    this.axis = Axis.horizontal,
  });

  /// Main-axis offset of the DRAWN end — where the line goes.
  final double left;

  /// Main-axis offset of the cut's END. Nothing is drawn when the two are
  /// equal: no transition span crosses this boundary, so there is no length to
  /// state.
  final double cutEnd;

  /// The frame axis direction: a vertical line in the horizontal timeline, a
  /// horizontal line in the X-sheet.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (left <= cutEnd) {
      return const SizedBox.shrink();
    }
    final line = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.noriShiro),
      ),
    );
    if (axis == Axis.vertical) {
      return Positioned(top: left, left: 0, right: 0, height: 2, child: line);
    }
    return Positioned(left: left, top: 0, bottom: 0, width: 2, child: line);
  }
}
