import 'package:flutter/foundation.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';

/// A geometry handle for tests that pump a row or a painter on their own.
///
/// Production keeps ONE of these per grid in `State`, because its identity is
/// what lets the row memo survive a zoom step (R28 #4); a test that only
/// needs a fixed geometry can mint one inline.
ValueNotifier<TimelineFrameGeometry> testFrameGeometry({
  required double frameCellExtent,
  int frameStartIndex = 0,
  required int frameEndIndexExclusive,
  double leadingFrameSpacerWidth = 0,
  double trailingFrameSpacerWidth = 0,
}) => ValueNotifier(
  TimelineFrameGeometry(
    frameCellExtent: frameCellExtent,
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
    trailingFrameSpacerWidth: trailingFrameSpacerWidth,
  ),
);
