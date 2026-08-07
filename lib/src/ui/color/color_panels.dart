import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';
import 'color_palette_strip.dart';
import 'color_rgb_panel.dart';
import 'color_status_bar.dart';
import 'color_wheel_panel.dart';

/// Which way of picking a colour a [ColorPickerPanel] is.
///
/// ⛔These are PANELS, not tabs of a panel (유저, R2 #8). The picker used to
/// be one panel carrying Wheel / RGB / Palette as three tabs of its own —
/// so a rail group's icon strip sat directly above a second icon strip
/// belonging to the thing inside it, and "which panel am I in" and "how am
/// I picking" were asked in the same place twice. Each way of picking is a
/// panel now; the group's strip is the only strip, and moving the palette
/// somewhere else is an ordinary tab drag rather than an impossibility.
enum ColorPickerKind { wheel, rgb, palette }

/// One colour panel: a way of picking, over the reading they all share.
///
/// The status bar (hex, and whatever else comes to live there) is the same
/// widget under every kind — 공통 로직 (유저) — so "what colour am I on"
/// never moves when you switch panels.
class ColorPickerPanel extends StatelessWidget {
  const ColorPickerPanel({
    super.key,
    required this.kind,
    required this.color,
    required this.palette,
    required this.onColorChanged,
    required this.onPaletteChanged,
  });

  final ColorPickerKind kind;

  /// CONTROLLED: the eyedropper, a preset and a recent colour recorded on
  /// stroke commit all have to land here while the panel is open. Live
  /// dragging does not snap back because [ColorWheelPanel] already ignores
  /// the echo of its own last emission.
  final int color;
  final ColorPaletteState palette;

  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _picker()),
        ColorStatusBar(color: color, onColorChanged: onColorChanged),
      ],
    );
  }

  Widget _picker() {
    switch (kind) {
      case ColorPickerKind.wheel:
        return ColorWheelPanel(color: color, onColorChanged: onColorChanged);
      case ColorPickerKind.rgb:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: ColorRgbPanel(color: color, onColorChanged: onColorChanged),
        );
      case ColorPickerKind.palette:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          // The scroll view belongs to the PALETTE, not to the panel frame:
          // the wheel and the RGB bars must not scroll.
          child: SingleChildScrollView(
            child: ColorPaletteStrip(
              palette: palette,
              currentColor: color,
              onColorSelected: onColorChanged,
              onPaletteChanged: onPaletteChanged,
            ),
          ),
        );
    }
  }
}
