import 'dart:math' as math;

/// The END-boundary gap rule every verb that moves a cut's end shares.
///
/// Growth: consume the following cut's gap, then push. Shrink: an ATTACHED
/// next cut (gap 0 at drag start) rides the boundary; a DETACHED one holds
/// its global position — the gap absorbs the shrink.
///
/// It is a top-level rule because BOTH cut-end movers state it, and they no
/// longer share a class: the cut TRIM's trailing edge (`CutTrailTrimDrag`)
/// and the storyboard comma's cut sync (`ExposureEdgeDrag` — a row's last
/// comma moves its cut's end with it, feedback #9). One private method
/// while the two were branches of one object; a copy each is exactly what
/// the clone gate refuses.
int followingGapAfterEndMove({required int baseGap, required int growth}) =>
    growth > 0
    ? math.max(0, baseGap - growth)
    : (baseGap > 0 ? baseGap - growth : 0);
