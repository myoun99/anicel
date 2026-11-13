import 'package:flutter/painting.dart' show Color;

import '../../models/ruler_marker.dart';

/// A ruler marker's ribbon, by the colour it is filed under.
///
/// 🗣️I-169-Q4 (유저 2026-11-13): 「여러 색」 — the six the mock-up drew and
/// the question named, as it drew them. ⛔No red, green or accent: on a
/// ruler those are the cut's end, the ready bar and the playhead.
Color rulerMarkerRibbon(RulerMarkerColor color) => Color(switch (color) {
  RulerMarkerColor.yellow => 0xFFF2C94C,
  RulerMarkerColor.orange => 0xFFF2994A,
  RulerMarkerColor.pink => 0xFFF08FB5,
  RulerMarkerColor.sky => 0xFF6BB8F0,
  RulerMarkerColor.violet => 0xFFB79BF2,
  RulerMarkerColor.white => 0xFFE6E8EA,
});

/// What a ribbon is written in — one dark ink on all six, whatever palette
/// the app wears: the ribbons are their own ground.
const Color rulerMarkerInk = Color(0xFF17191B);
