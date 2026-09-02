/// How far the timeline's frame axis may zoom, in pixels per frame — the
/// one place the panel, its view cluster and anything else that clamps a
/// zoom read the same numbers.
///
/// A leaf on purpose: the view cluster used to read these off
/// `TimelinePanel`, which builds the cluster, and the two files imported
/// each other (Round 4 of the audit, 2026-09-03).
abstract final class TimelineZoomLimits {
  static const double minPixelsPerFrame = 2.4;
  static const double maxPixelsPerFrame = 96;
  static const double defaultPixelsPerFrame = 24;
}
