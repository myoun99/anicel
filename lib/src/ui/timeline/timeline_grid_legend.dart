import 'package:flutter/foundation.dart';

import 'timeline_legend_menus.dart';
import 'timeline_section_policy.dart';

/// What a timeline panel tells the legend over its grid's rail — the verbs,
/// and the states its cells wear — whichever of its two grids it stands up:
/// the timeline's rail lying down or the x-sheet's corner stood up
/// ([TimelineGridLegendRail] makes the header from it, for both).
///
/// 🗣️F-408 ② (유저 2026-10-19): 「다른 레전드 행도 점검하면서 법 통일」.
/// ↩️The x-sheet's corner was told none of it (R10 R6, 08-01 — no decision
/// says so), so its legend opened no flyout and a key pressed nothing there.
final class TimelineGridLegend {
  const TimelineGridLegend({
    this.verbs,
    this.onMenus,
    this.onToggleSection,
    this.visibilitySoloEnabled = false,
    this.displayedOpacity = 1.0,
    this.displayedOnionSkinOn = false,
  });

  /// The rail legend's bulk commands; null renders a display-only legend.
  final LayerLegendCallbacks? verbs;

  /// Told the menus the legend header opens each time it is built — what a
  /// key presses one of (I-40, `RailLegends`).
  final ValueChanged<TimelineLegendMenus?>? onMenus;

  /// Folds/unfolds a hideable section (the legend corner's sections cell).
  final ValueChanged<TimelineSection>? onToggleSection;

  /// Whether the visibility solo mode is engaged (legend eye state color).
  final bool visibilitySoloEnabled;

  /// The master bar's resting value (the LAST committed sweep, UI-R6 #2).
  final double displayedOpacity;

  /// Whether every displayed drawing layer is ghosting (UI-R17 #5).
  final bool displayedOnionSkinOn;
}
