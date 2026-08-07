import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';
import '../widgets/anchored_popup.dart';
import '../panels/editor_panel_tabs.dart';
import 'color_palette_strip.dart';
import 'color_slot_pair.dart';
import '../brush/tools_panel.dart' show ToolsPanel;
import '../theme/app_theme.dart';
import 'color_rgb_panel.dart';
import 'color_status_bar.dart';
import 'color_wheel_panel.dart';

/// The 「컬러 버튼창」 (R9 #14, the user's name for it): the window the
/// SELECTED-COLOUR swatch opens, carrying the colour wheel, the RGB bars and
/// the palette as three tabs.
///
/// It replaces the Color dock TAB. The wheel had been a docked panel
/// competing for a whole column of workspace next to the canvas, while the
/// thing the user actually reaches for — the current colour — was not on a
/// rail at all. Now the swatch IS the control and the window is where its
/// ways of picking live.
///
/// It rides [PinnedAnchoredPopup] — the app's one sub-window (R28 #9) in its
/// PINNED kind, which is what lets a colour be nudged and tried against a
/// real stroke without the window blinking out.
const double colorButtonWindowWidth = 236;
const double colorButtonWindowHeight = 320;

/// The selected-colour control at the TOP STRIP's right end — the last of
/// the strip's four standing choices (크기 · 불투명도 · 합성모드 · 색).
///
/// It began as the tool rail's bottom control (R9 #14), then the rail-and-
/// strip round moved it up: the rail is what a hand reaches for BETWEEN
/// STROKES, and the strip is for what stands between pieces of work. The
/// swatch is also the reason the rail no longer needs a colour at all — the
/// strip button IS the swatch.
///
/// R10 R5 made it the DUAL swatch: foreground over background. Both were
/// inside the window before, which meant the two colours you paint with were
/// invisible until you opened something. The pair is exactly one 42px button
/// cell, so it drops into the strip beside the blend button without the
/// strip learning a new size.
///
/// ⛔**There is no swap GLYPH** (유저 확정, 두 번 말했다): tapping the back
/// slot already swaps, so a separate button is the same verb twice. The pair
/// is the whole control.
class SelectedColorButton extends StatefulWidget {
  const SelectedColorButton({
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
  State<SelectedColorButton> createState() => _SelectedColorButtonState();
}

class _SelectedColorButtonState extends State<SelectedColorButton> {
  /// The pinned window's switch. It lives in the State because the window
  /// outlives every rebuild of the colour it is showing — which is most
  /// rebuilds this widget gets.
  final OverlayPortalController _window = OverlayPortalController();

  /// Exchanges the two slots — the Photoshop gesture, carried by the BACK
  /// SLOT itself. It lives HERE rather than in the wheel because the pair
  /// does: the swap is what the pair means, and the window may not even be
  /// open.
  void _swap() {
    widget.onColorChanged(widget.backgroundColor);
    widget.onBackgroundColorChanged(widget.color);
  }

  @override
  Widget build(BuildContext context) {
    return PinnedAnchoredPopup(
      controller: _window,
      label: 'color-button-window',
      width: colorButtonWindowWidth,
      height: colorButtonWindowHeight,
      // Built from the LIVE values: the portal rebuilds this whenever the
      // strip rebuilds, so a colour picked with the eyedropper on the canvas
      // reaches the open window. That only became possible — and necessary —
      // when the window stopped closing on the first touch outside it.
      builder: (context, _) => ColorButtonWindow(
        color: widget.color,
        palette: widget.palette,
        onColorChanged: widget.onColorChanged,
        onPaletteChanged: widget.onPaletteChanged,
      ),
      child: Tooltip(
        message: 'Colour',
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: AppShapes.control(ToolsPanel.buttonExtent),
          child: InkWell(
            key: const ValueKey<String>('tool-color-button'),
            customBorder: AppShapes.control(ToolsPanel.buttonExtent),
            // Tap again to close: with no barrier to swallow the gesture,
            // the anchor is the window's switch.
            onTap: _window.toggle,
            // The pair sizes itself to one 42px button cell, which is what
            // the anchor's box has to be: the window is placed against it.
            child: ColorSlotPair(
              keyPrefix: 'tool-color',
              foreground: Color(widget.color),
              background: Color(widget.backgroundColor),
              onBackgroundTap: _swap,
            ),
          ),
        ),
      ),
    );
  }
}

class ColorButtonWindow extends StatefulWidget {
  const ColorButtonWindow({
    super.key,
    required this.color,
    required this.palette,
    required this.onColorChanged,
    required this.onPaletteChanged,
    this.framed = true,
  });

  /// Whether to wear a popup's frame — elevation, a rounded plate and a
  /// height of its own. False when the picker is a rail PANEL: the group
  /// already draws the surface and hands down the height.
  final bool framed;

  /// CONTROLLED, both of them: the window used to keep working copies so it
  /// could outlive the rebuild of whatever opened it. The pinned popup
  /// rebuilds with its anchor now, so a copy would only be a way to go
  /// stale — the eyedropper, a preset, a recent colour recorded on stroke
  /// commit all have to land here while the window is open. Live dragging
  /// does not snap back because [ColorWheelPanel] already ignores the echo
  /// of its own last emission.
  final int color;
  final ColorPaletteState palette;

  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPaletteChanged;

  // R10 R5: the BACKGROUND slot is the strip button's, so the window no
  // longer carries it — not as state, not as a parameter, not as a
  // callback threaded through a picker that never touches it.

  @override
  State<ColorButtonWindow> createState() => _ColorButtonWindowState();
}

class _ColorButtonWindowState extends State<ColorButtonWindow> {
  /// R10 R5: the tab is an ID, not a bool, because the tab LIST is data
  /// now — the user is building toward AE-style plugins that add tabs, and
  /// a plugin cannot add a case to a boolean.
  ///
  /// The only state left here: which tab, which nothing outside the window
  /// has an opinion about.
  String _tabId = 'wheel';

  @override
  Widget build(BuildContext context) {
    if (!widget.framed) {
      return _body();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainerHigh,
      shape: AppShapes.container(AppShapes.windowRadius),
      clipBehavior: Clip.antiAlias,
      // The shared popup positions by width alone (height only decides
      // above/below), so the window states its own — the wheel needs a
      // bounded box to expand into.
      child: SizedBox(
        height: colorButtonWindowHeight,
        child: _body(),
      ),
    );
  }

  /// LAYOUT B (the user's): tabs / content / a status bar shared by every
  /// tab, so "what colour am I on" never moves when you switch how you are
  /// picking it.
  ///
  /// Shared with the rail PANEL, which is the same thing without a popup's
  /// elevation and without a height of its own — it takes the height the
  /// group hands it.
  Widget _body() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: EditorPanelTabs(
          tabs: _tabs,
          activeTabId: _tabId,
          onTabSelected: (id) => setState(() => _tabId = id),
          // Icon-only: at 236px three labelled tabs would not fit, and the
          // dock's own narrow groups already read this way.
          compact: true,
        ),
      ),
      ColorStatusBar(
        color: widget.color,
        onColorChanged: widget.onColorChanged,
      ),
    ],
  );

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
          color: widget.color,
          onColorChanged: widget.onColorChanged,
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
        child: ColorRgbPanel(
          color: widget.color,
          onColorChanged: widget.onColorChanged,
        ),
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
            palette: widget.palette,
            currentColor: widget.color,
            onColorSelected: widget.onColorChanged,
            onPaletteChanged: widget.onPaletteChanged,
          ),
        ),
      ),
    ),
  ];
}

/// The colour picker AS A PANEL — the same wheel/RGB/palette tabs and the
/// same status bar, laid out in whatever height a rail group gives it.
///
/// 컬러 창은 상단띠에서 오른쪽 서브띠 맨 위로 (유저 확정): it used to open
/// downward out of a strip button, which made it the one surface in the app
/// that opened along a different axis from everything else. As a rail group
/// it opens sideways like every other panel, and it costs the top strip
/// nothing.
class ColorPickerPanel extends StatelessWidget {
  const ColorPickerPanel({
    super.key,
    required this.color,
    required this.palette,
    required this.onColorChanged,
    required this.onPaletteChanged,
  });

  final int color;
  final ColorPaletteState palette;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    // The window widget already IS this content plus a popup's chrome, so
    // the panel is that content with the chrome asked for and refused —
    // one implementation of the picker, two frames around it.
    return ColorButtonWindow(
      key: const ValueKey<String>('color-picker-panel'),
      framed: false,
      color: color,
      palette: palette,
      onColorChanged: onColorChanged,
      onPaletteChanged: onPaletteChanged,
    );
  }
}
