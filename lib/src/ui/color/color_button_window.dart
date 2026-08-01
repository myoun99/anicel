import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../services/color_palette_file_service.dart';
import '../widgets/anchored_popup.dart';
import '../panels/editor_panel_tabs.dart';
import 'color_palette_strip.dart';
import 'color_slot_pair.dart';
import 'color_rgb_panel.dart';
import 'color_status_bar.dart';
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

/// The selected-colour control that opens the window — the tool rail's
/// bottom control (R9 #14).
///
/// R10 R5 made it the DUAL swatch: foreground over background, with a
/// swap glyph under it. Both were inside the window before, which meant
/// the two colours you paint with were invisible until you opened
/// something, while the rail — where a hand rests — showed one flat
/// circle. The pair is exactly the rail's 42px button cell, so nothing
/// about the rail had to change to hold it.
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

  /// Exchanges the two slots. It lives HERE rather than in the wheel
  /// because the pair does: the swap is what the pair means, and the
  /// window may not even be open.
  void _swap() {
    onColorChanged(backgroundColor);
    onBackgroundColorChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Colour',
            child: Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                key: const ValueKey<String>('tool-color-button'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => showColorButtonWindow(
                  anchorContext,
                  color: color,
                  backgroundColor: backgroundColor,
                  palette: palette,
                  onColorChanged: onColorChanged,
                  onBackgroundColorChanged: onBackgroundColorChanged,
                  onPaletteChanged: onPaletteChanged,
                ),
                // The pair's own extent IS the rail cell; `diameter` is
                // kept as the floor so a host that sizes the rail
                // differently still gets a square that fits.
                child: SizedBox(
                  width: math.max(diameter, ColorSlotPair.extent),
                  height: math.max(diameter, ColorSlotPair.extent),
                  child: Center(
                    child: ColorSlotPair(
                      keyPrefix: 'tool-color',
                      foreground: Color(color),
                      background: Color(backgroundColor),
                      onBackgroundTap: _swap,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The swap glyph under the pair (the user's placement): the same
          // verb as tapping the back slot, said in a way you can find.
          SizedBox(
            height: 16,
            child: IconButton(
              key: const ValueKey<String>('tool-color-swap-button'),
              tooltip: 'Swap Colors',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 16),
              iconSize: 13,
              icon: const Icon(Icons.swap_horiz),
              onPressed: _swap,
            ),
          ),
        ],
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

  /// R10 R5: the tab is an ID, not a bool, because the tab LIST is data
  /// now — the user is building toward AE-style plugins that add tabs, and
  /// a plugin cannot add a case to a boolean.
  String _tabId = 'wheel';

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
        // LAYOUT B (the user's): tabs / content / a status bar shared by
        // every tab, so "what colour am I on" never moves when you switch
        // how you are picking it.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EditorPanelTabs(
                tabs: _tabs,
                activeTabId: _tabId,
                onTabSelected: (id) => setState(() => _tabId = id),
                // Icon-only: at 236px three labelled tabs would not fit,
                // and the dock's own narrow groups already read this way.
                compact: true,
              ),
            ),
            ColorStatusBar(color: _color, onColorChanged: _setColor),
          ],
        ),
      ),
    );
  }

  /// The window's tabs AS DATA — the shape [EditorPanelTabs] already
  /// takes, and the shape a plugin can append to.
  List<EditorPanelTab> get _tabs => [
    EditorPanelTab(
      id: 'wheel',
      label: 'Wheel',
      icon: Icons.color_lens_outlined,
      buttonKey: const ValueKey<String>('color-window-tab-wheel'),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: ColorWheelPanel(
          color: _color,
          backgroundColor: _background,
          onColorChanged: _setColor,
          onBackgroundColorChanged: _setBackground,
        ),
      ),
    ),
    EditorPanelTab(
      id: 'rgb',
      label: 'RGB',
      icon: Icons.tune,
      buttonKey: const ValueKey<String>('color-window-tab-rgb'),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: ColorRgbPanel(color: _color, onColorChanged: _setColor),
      ),
    ),
    EditorPanelTab(
      id: 'palette',
      label: 'Palette',
      icon: Icons.grid_view_outlined,
      buttonKey: const ValueKey<String>('color-window-tab-palette'),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        // The scroll view belongs to the TAB, not to the window: the
        // wheel and the RGB bars must not scroll.
        child: SingleChildScrollView(
          child: ColorPaletteStrip(
            palette: _palette,
            currentColor: _color,
            onColorSelected: _setColor,
            onPaletteChanged: _setPalette,
          ),
        ),
      ),
    ),
  ];
}
