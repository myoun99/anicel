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
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// Which selection VARIANT the single Select button activates (R17-U:
  /// rectangle/lasso are one toolbar tool — the variant lives in the tool
  /// settings; the host remembers the last-used one).
  final CanvasTool selectionVariant;

  /// The edge dock width this panel is designed for (fits the compact
  /// tools tab with its close/lock glyphs plus the tool buttons).
  static const double dockWidth = 72;

  @override
  Widget build(BuildContext context) {
    // Left-aligned like a PS tool column: docked into a wide dock the
    // buttons must hug the panel's left edge, not float centered.
    // R26 #31: the library now shares the left wide dock with the tool
    // settings below it, so its column can be shorter than the buttons —
    // it scrolls instead of overflowing.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 6, top: 6),
      child: Column(
        key: const ValueKey<String>('tools-panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolButton(
            keyValue: 'tool-brush-button',
            tooltip: AppText.strings.toolBrushTip,
            icon: Icons.brush_outlined,
            selected: tool == CanvasTool.brush,
            onPressed: () => onToolChanged(CanvasTool.brush),
          ),
          const SizedBox(height: 4),
          _ToolButton(
            keyValue: 'tool-eraser-button',
            tooltip: AppText.strings.toolEraserTip,
            // No dedicated eraser glyph in this icon set; the "magic
            // eraser" wand reads closest.
            icon: Icons.auto_fix_normal,
            selected: tool == CanvasTool.eraser,
            onPressed: () => onToolChanged(CanvasTool.eraser),
          ),
          const SizedBox(height: 4),
          _ToolButton(
            keyValue: 'tool-eyedropper-button',
            tooltip: AppText.strings.toolEyedropperTip,
            icon: Icons.colorize_outlined,
            selected: tool == CanvasTool.eyedropper,
            onPressed: () => onToolChanged(CanvasTool.eyedropper),
          ),
          const SizedBox(height: 4),
          _ToolButton(
            keyValue: 'tool-fill-button',
            tooltip: AppText.strings.toolFillTip,
            icon: Icons.format_color_fill_outlined,
            selected: tool == CanvasTool.fill,
            onPressed: () => onToolChanged(CanvasTool.fill),
          ),
          const SizedBox(height: 4),
          // R17-U: ONE selection tool — the rectangle/lasso variant is a
          // tool SETTING, not a separate toolbar entry (유저 채택 설계).
          _ToolButton(
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
          _ToolButton(
            keyValue: 'tool-move-button',
            tooltip: AppText.strings.toolMoveTip,
            icon: Icons.open_with,
            selected: tool == CanvasTool.move,
            onPressed: () => onToolChanged(CanvasTool.move),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
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
  final VoidCallback onPressed;

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
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        backgroundColor: selected
            ? colorScheme.surfaceContainerHigh
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
