import 'package:flutter/material.dart';

import 'brush_tool_state.dart';
import '../text/app_strings.dart';

/// The Photoshop/Clip-Studio style tool switcher (brush ⇄ eraser): a
/// dockable PANEL whose home is a slim vertical edge dock, so it lives on
/// the left OR right workspace edge (left-handed choice) — or in any wider
/// dock, where its tab shows the panel name. Content only: the hosting
/// dock draws the chrome. Both tools share the brush options (size,
/// hardness, tip) — the eraser only flips the dabs into destination-out.
class ToolsPanel extends StatelessWidget {
  const ToolsPanel({
    super.key,
    required this.tool,
    required this.onToolChanged,
    this.selectionVariant = CanvasTool.selectRect,
    this.historyControls,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// Undo / redo / onion — the things a hand reaches for BETWEEN strokes,
  /// which is what the rail is for. They sit above the tools, separated by a
  /// rule.
  ///
  /// A slot rather than built here so the panel stays session-free: the
  /// host owns the history manager these listen to. Null keeps the rail
  /// tools-only (passive hosts and the panel's own tests).
  final Widget? historyControls;

  /// Which selection VARIANT the single Select button activates (R17-U:
  /// rectangle/lasso are one toolbar tool — the variant lives in the tool
  /// settings; the host remembers the last-used one).
  final CanvasTool selectionVariant;

  /// The edge dock width this panel is designed for.
  ///
  /// R9 #17: 72 → 48, a third of the rail's width back to the canvas. The
  /// tool BUTTONS are what the old number was padding out; the compact
  /// tab strip scrolls, so its close/lock glyphs cost the rail nothing.
  /// 48 was chosen to HOLD a 42px stylus target rather than shrink the
  /// target to fit (the user's rule); the rail-and-strip round then handed
  /// the colour swatch to the top strip, and 42 is still the cell.
  static const double dockWidth = 48;

  /// The rail's button box: a stylus-sized square that fits [dockWidth]
  /// with the panel's own padding.
  static const double buttonExtent = 42;

  @override
  Widget build(BuildContext context) {
    // Left-aligned like a PS tool column: docked into a wide dock the
    // buttons must hug the panel's left edge, not float centered.
    // R26 #31: the library now shares the left wide dock with the tool
    // settings below it, so its column can be shorter than the buttons —
    // it scrolls instead of overflowing.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 3, top: 6, bottom: 6),
      child: Column(
        key: const ValueKey<String>('tools-panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (historyControls != null) ...[
            historyControls!,
            const SizedBox(height: 8),
            Divider(
              height: 1,
              thickness: 1,
              indent: 2,
              endIndent: 2,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 8),
          ],
          RailButton(
            keyValue: 'tool-brush-button',
            tooltip: AppText.strings.toolBrushTip,
            icon: Icons.brush_outlined,
            selected: tool == CanvasTool.brush,
            onPressed: () => onToolChanged(CanvasTool.brush),
          ),
          const SizedBox(height: 4),
          RailButton(
            keyValue: 'tool-eraser-button',
            tooltip: AppText.strings.toolEraserTip,
            // No dedicated eraser glyph in this icon set; the "magic
            // eraser" wand reads closest.
            icon: Icons.auto_fix_normal,
            selected: tool == CanvasTool.eraser,
            onPressed: () => onToolChanged(CanvasTool.eraser),
          ),
          const SizedBox(height: 4),
          RailButton(
            keyValue: 'tool-eyedropper-button',
            tooltip: AppText.strings.toolEyedropperTip,
            icon: Icons.colorize_outlined,
            selected: tool == CanvasTool.eyedropper,
            onPressed: () => onToolChanged(CanvasTool.eyedropper),
          ),
          const SizedBox(height: 4),
          RailButton(
            keyValue: 'tool-fill-button',
            tooltip: AppText.strings.toolFillTip,
            icon: Icons.format_color_fill_outlined,
            selected: tool == CanvasTool.fill,
            onPressed: () => onToolChanged(CanvasTool.fill),
          ),
          const SizedBox(height: 4),
          // R17-U: ONE selection tool — the rectangle/lasso variant is a
          // tool SETTING, not a separate toolbar entry (유저 채택 설계).
          RailButton(
            keyValue: 'tool-select-button',
            tooltip: AppText.strings.toolSelectTip,
            icon: Icons.highlight_alt_outlined,
            selected: tool == CanvasTool.selectRect || tool == CanvasTool.lasso,
            onPressed: () => onToolChanged(
              tool == CanvasTool.selectRect || tool == CanvasTool.lasso
                  ? tool
                  : selectionVariant,
            ),
          ),
          const SizedBox(height: 4),
          RailButton(
            keyValue: 'tool-move-button',
            tooltip: AppText.strings.toolMoveTip,
            icon: Icons.open_with,
            selected: tool == CanvasTool.move,
            onPressed: () => onToolChanged(CanvasTool.move),
          ),
          // 유저 확정 (rail-and-strip): 「컬러 스와치는 레일에서 빠진다」 —
          // the top strip's colour button IS the swatch, so keeping one here
          // would be two places to read the same colour. The rail is
          // history + onion + the six tools, and that is all.
        ],
      ),
    );
  }
}

/// One button on the tool rail: a stylus-sized square that says its state
/// with colour, not size.
///
/// Public because the rail is no longer only tools — undo, redo and the
/// onion toggle are handed in by the host and have to be the SAME button,
/// or the column stops reading as one grid.
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.keyValue,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String keyValue;
  final String tooltip;
  final IconData icon;
  final bool selected;

  /// Null disables the button — a tool is always available, but undo and
  /// redo are not, and they wear this same square.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey<String>(keyValue),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 20,
      isSelected: selected,
      padding: EdgeInsets.zero,
      // R9 #17: a tight box, so the slim rail holds the button instead of
      // the button dictating a 72px rail. Still 42 across — the stylus
      // target the rail was narrowed AROUND, not below.
      constraints: const BoxConstraints.tightFor(
        width: ToolsPanel.buttonExtent,
        height: ToolsPanel.buttonExtent,
      ),
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        backgroundColor: selected
            ? colorScheme.surfaceContainerHigh
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        // The 42px box IS the tap target (R9 #17) — M3's automatic 48px
        // inflation is what made the rail need 72.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size.square(ToolsPanel.buttonExtent),
        fixedSize: const Size.square(ToolsPanel.buttonExtent),
      ),
    );
  }
}
