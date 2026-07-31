import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';
import '../theme/app_theme.dart';
import '../widgets/anchored_popup.dart';
import 'color_palette_strip.dart';
import 'color_wheel_panel.dart';

/// The 「컬러 버튼창」 (R9 #14, the user's name for it): the window the tool
/// rail's SELECTED-COLOUR swatch opens, carrying the colour wheel and the
/// palette as two tabs.
///
/// It replaces the Color dock TAB. The wheel had been a docked panel
/// competing for a whole column of workspace next to the canvas, while the
/// thing the user actually reaches for — the current colour — was not on
/// the tool rail at all. Now the swatch IS the control and the window is
/// where its two ways of picking live.
///
/// It rides [showAnchoredPopup], so where it lands and how it dismisses are
/// the app's one sub-window behaviour (R28 #9).
const double colorButtonWindowWidth = 236;
const double colorButtonWindowHeight = 320;

/// The selected-colour swatch that opens the window — the tool rail's
/// bottom control (R9 #14).
///
/// [diameter] is the rail's own width minus its padding: the swatch is a
/// stylus target, so the rail was sized to hold it rather than the swatch
/// shrunk to fit the rail (the user's rule when #17 was decided).
class SelectedColorButton extends StatelessWidget {
  const SelectedColorButton({
    super.key,
    required this.color,
    required this.backgroundColor,
    required this.palette,
    required this.onColorChanged,
    required this.onBackgroundColorChanged,
    required this.onPaletteChanged,
    this.diameter = 42,
  });

  final int color;
  final int backgroundColor;
  final ColorPaletteState palette;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<int> onBackgroundColorChanged;
  final ValueChanged<ColorPaletteState> onPaletteChanged;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => Tooltip(
        message: 'Colour',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey<String>('tool-color-button'),
            customBorder: const CircleBorder(),
            onTap: () => showColorButtonWindow(
              anchorContext,
              color: color,
              backgroundColor: backgroundColor,
              palette: palette,
              onColorChanged: onColorChanged,
              onBackgroundColorChanged: onBackgroundColorChanged,
              onPaletteChanged: onPaletteChanged,
            ),
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairlineStrong),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showColorButtonWindow(
  BuildContext anchorContext, {
  required int color,
  required int backgroundColor,
  required ColorPaletteState palette,
  required ValueChanged<int> onColorChanged,
  required ValueChanged<int> onBackgroundColorChanged,
  required ValueChanged<ColorPaletteState> onPaletteChanged,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'color-button-window',
    width: colorButtonWindowWidth,
    height: colorButtonWindowHeight,
    builder: (context) => ColorButtonWindow(
      color: color,
      backgroundColor: backgroundColor,
      palette: palette,
      onColorChanged: onColorChanged,
      onBackgroundColorChanged: onBackgroundColorChanged,
      onPaletteChanged: onPaletteChanged,
    ),
  );
}

class ColorButtonWindow extends StatefulWidget {
  const ColorButtonWindow({
    super.key,
    required this.color,
    required this.backgroundColor,
    required this.palette,
    required this.onColorChanged,
    required this.onBackgroundColorChanged,
    required this.onPaletteChanged,
  });

  final int color;
  final int backgroundColor;
  final ColorPaletteState palette;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<int> onBackgroundColorChanged;
  final ValueChanged<ColorPaletteState> onPaletteChanged;

  @override
  State<ColorButtonWindow> createState() => _ColorButtonWindowState();
}

class _ColorButtonWindowState extends State<ColorButtonWindow> {
  /// The window keeps its OWN working copies: it outlives the rebuild of
  /// whatever opened it, and the wheel is dragged live, so reading the
  /// caller's captured values back would snap the drag to where it started.
  late int _color = widget.color;
  late int _background = widget.backgroundColor;
  late ColorPaletteState _palette = widget.palette;
  bool _paletteTab = false;

  void _setColor(int color) {
    setState(() => _color = color);
    widget.onColorChanged(color);
  }

  void _setBackground(int color) {
    setState(() => _background = color);
    widget.onBackgroundColorChanged(color);
  }

  void _setPalette(ColorPaletteState palette) {
    setState(() => _palette = palette);
    widget.onPaletteChanged(palette);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      // The shared popup positions by width alone (height only decides
      // above/below), so the window states its own — the wheel needs a
      // bounded box to expand into.
      child: SizedBox(
        height: colorButtonWindowHeight,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _WindowTab(
                keyValue: 'color-window-tab-wheel',
                label: 'Wheel',
                selected: !_paletteTab,
                onTap: () => setState(() => _paletteTab = false),
              ),
              _WindowTab(
                keyValue: 'color-window-tab-palette',
                label: 'Palette',
                selected: _paletteTab,
                onTap: () => setState(() => _paletteTab = true),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: _paletteTab
                  ? SingleChildScrollView(
                      child: ColorPaletteStrip(
                        palette: _palette,
                        currentColor: _color,
                        onColorSelected: _setColor,
                        onPaletteChanged: _setPalette,
                      ),
                    )
                  : ColorWheelPanel(
                      color: _color,
                      backgroundColor: _background,
                      onColorChanged: _setColor,
                      onBackgroundColorChanged: _setBackground,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowTab extends StatelessWidget {
  const _WindowTab({
    required this.keyValue,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String keyValue;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        key: ValueKey<String>(keyValue),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            // The dock tabs' language: the selected tab wears the body
            // colour and takes an accent top rule.
            color: selected ? colorScheme.surfaceContainerHighest : null,
            border: Border(
              top: BorderSide(
                width: 2,
                color: selected ? colorScheme.primary : Colors.transparent,
              ),
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                // Selection reads by COLOUR only (user rule).
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
