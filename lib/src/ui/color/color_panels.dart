import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';
import 'color_palettes.dart';
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

  /// What [kind] costs in a group that cannot shrink: the status bar every
  /// kind shares and, under the wheel and the RGB bars, the default palette
  /// (I-131) — with the bars themselves, the one picker with nothing that
  /// can give, and the wheel's margin. Null for the palette, which scrolls
  /// its own.
  ///
  /// Published so the dock that hands out heights can honour it. The status
  /// bar is asked where the panel is shown: it grows with the OS text size.
  static double? contentExtentIn(BuildContext context, ColorPickerKind kind) {
    final fixed =
        PaletteUnderPicker.maxExtent + ColorStatusBar.heightIn(context);
    return switch (kind) {
      ColorPickerKind.wheel => ColorWheelPanel.inset * 2 + fixed,
      ColorPickerKind.rgb =>
        ColorRgbPanel.contentHeight + _pickerPadding + fixed,
      ColorPickerKind.palette => null,
    };
  }

  /// What every kind needs ACROSS: the readout laid out whole. Its cells are
  /// fixed on purpose (the digits must not move), so a group narrower than
  /// this scrolls sideways rather than cutting the blue channel off — and
  /// the readout widens with the OS text size.
  static double minContentWidthIn(BuildContext context) =>
      ColorStatusBar.naturalWidthIn(context);

  static const double _pickerPadding = 8 + 10;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _picker()),
        // I-131-Q2: 「고르개와 상태 바 사이에 기본 팔레트가 늘 「작게」로
        // 선다」 — under the two pickers, not in the palette panel, which
        // shows every palette itself.
        if (kind != ColorPickerKind.palette)
          PaletteUnderPicker(
            palettes: palette,
            color: color,
            onColorChanged: onColorChanged,
            onPalettesChanged: onPaletteChanged,
          ),
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
        return ColorPalettesPanel(
          palettes: palette,
          color: color,
          onColorChanged: onColorChanged,
          onPalettesChanged: onPaletteChanged,
        );
    }
  }
}
