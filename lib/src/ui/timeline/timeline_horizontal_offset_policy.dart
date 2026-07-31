/// Resolves the horizontal offset a timeline's scroll CONTROLLER should be
/// corrected to after a viewport resize.
///
/// R9 #3 narrowed this file's job. It used to say it produced "the
/// effective offset that layout and hit testing should share", and the
/// grid duly rendered its ruler at the clamped value — which pinned the
/// ruler at the end of the content while the body slid on through an
/// overscroll, breaking the very alignment the sentence promised.
///
/// The scroll POSITION is what the ruler renders and hit-tests at,
/// overscroll and all: it is by definition the offset the body has. This
/// clamp answers only "is the controller out of range, and where should it
/// jump back to" — a question about the controller, not about paint.
///
/// It has no `ScrollController` side effects. Widget-side correction
/// scheduling must remain in `LayerTimelineGrid`.

library;

import 'dart:math' as math;

class TimelineHorizontalOffsetResolution {
  const TimelineHorizontalOffsetResolution({
    required this.requestedOffset,
    required this.effectiveOffset,
    required this.maxOffset,
  });

  final double requestedOffset;
  final double effectiveOffset;
  final double maxOffset;

  bool get needsCorrection => requestedOffset != effectiveOffset;
}

TimelineHorizontalOffsetResolution resolveTimelineHorizontalOffset({
  required double requestedOffset,
  required double totalContentWidth,
  required double viewportWidth,
}) {
  final normalizedTotalContentWidth = math.max(0.0, totalContentWidth);
  final normalizedViewportWidth = math.max(0.0, viewportWidth);

  final maxOffset = math.max(
    0.0,
    normalizedTotalContentWidth - normalizedViewportWidth,
  );

  final effectiveOffset = requestedOffset.clamp(0.0, maxOffset).toDouble();

  return TimelineHorizontalOffsetResolution(
    requestedOffset: requestedOffset,
    effectiveOffset: effectiveOffset,
    maxOffset: maxOffset,
  );
}
