import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/rail_glyph_button.dart';
import 'axis_turn.dart';
import 'layer_label_controls.dart'
    show RailSwipeColumnPointer, layerGraphSlotWidth, layerLanePinSlotWidth;
import 'layer_rail_columns.dart' show railSlotBox;

/// Which of the header graph's two toggles (I-89 ③).
enum LaneGraphToggleKind {
  /// A group's graph on or off — on a Transform or effect header, and on
  /// the camera row, the row being its own Transform group (㉙).
  graph,

  /// A member lane pinned to every open graph, its own group's or another's
  /// — AE's graph editor set.
  pin,
}

/// THE HEADER GRAPH'S TOGGLES (I-89 ③) — the one widget every row that
/// wears one mounts, in both grids, so the rows cannot come to read
/// differently: an icon in its slot, on in accent ink (선택 표시는 색상만),
/// and a swipe column on every rail that mounts it, as every rail toggle is
/// (I-1, 「버튼이면 다 가능하도록」).
class LaneGraphToggle extends StatelessWidget {
  const LaneGraphToggle({
    super.key,
    required this.kind,
    required this.name,
    required this.axis,
    required this.on,
    required this.onToggle,
  });

  final LaneGraphToggleKind kind;
  /// What a finder calls the toggle — its [RailGlyphButton.name].
  final String name;
  final Axis axis;
  final bool on;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final (icon, slot, tooltip) = switch (kind) {
      LaneGraphToggleKind.graph => (
        Icons.show_chart,
        layerGraphSlotWidth,
        on ? strings.railLaneGraphOn : strings.railLaneGraph,
      ),
      LaneGraphToggleKind.pin => (
        Icons.push_pin,
        layerLanePinSlotWidth,
        on ? strings.railLanePinOn : strings.railLanePin,
      ),
    };
    return acrossBox(
      axis,
      26,
      child: RailSwipeColumnPointer(
        child: RailGlyphButton(
          name: name,
          tooltip: tooltip,
          size: railSlotBox(axis, slot: slot, across: 26, iconSize: 15),
          isSelected: on,
          glyph: RailIconGlyph(icon),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
