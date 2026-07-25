import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One entry of a [showPanelFlyout] list.
///
/// The app's shared popup-list vocabulary (the FieldSlider of menus): every
/// toolbar menu, legend bulk flyout and split-button dropdown builds from
/// these entries so they all read alike.
sealed class PanelFlyoutEntry {
  const PanelFlyoutEntry();
}

/// Non-interactive section caption.
class PanelFlyoutHeader extends PanelFlyoutEntry {
  const PanelFlyoutHeader(this.label);

  final String label;
}

/// Thin separator between groups.
class PanelFlyoutDivider extends PanelFlyoutEntry {
  const PanelFlyoutDivider();
}

/// A selectable command.
class PanelFlyoutItem extends PanelFlyoutEntry {
  const PanelFlyoutItem({
    required this.keyValue,
    required this.label,
    this.icon,
    this.checked,
    this.danger = false,
    this.enabled = true,
    this.onSelected,
  });

  /// Widget key string — menu items that replaced toolbar buttons reuse the
  /// retired button's key string so tests only gain a menu-open tap.
  final String keyValue;

  final String label;
  final IconData? icon;

  /// Trailing check when true; null means the item is not a toggle.
  final bool? checked;

  /// Destructive styling (delete commands).
  final bool danger;

  final bool enabled;

  /// Runs AFTER the flyout closes.
  final VoidCallback? onSelected;
}

/// Shows the shared flyout anchored under [anchorContext]'s widget and runs
/// the picked item's [PanelFlyoutItem.onSelected] after the menu closes.
///
/// [anchorRect] narrows the anchor to a rect INSIDE that widget, in its
/// local coordinates. PAINTED affordances (the timeline's run-edge property
/// tags) have no box of their own to anchor on, and this keeps them on the
/// one shared popup shell instead of growing a surface-local copy.
///
/// When the space below the anchor can't fit the list, the flyout opens
/// UPWARD instead (its bottom hugging the anchor's top) — the item order
/// never changes (UI-R6 #1); Material's default merely clamped the menu,
/// which read as the list growing bottom-up.
Future<void> showPanelFlyout(
  BuildContext anchorContext, {
  required List<PanelFlyoutEntry> entries,
  Rect? anchorRect,
}) async {
  final button = anchorContext.findRenderObject()! as RenderBox;
  final anchor = anchorRect ?? (Offset.zero & button.size);
  final overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject()!
          as RenderBox;
  // The entry heights are fixed (32/24/6 + the menu's 8+8 padding), so the
  // flyout's height is known before layout.
  var estimatedHeight = 16.0;
  for (final entry in entries) {
    estimatedHeight += switch (entry) {
      PanelFlyoutHeader() => 24.0,
      PanelFlyoutDivider() => 6.0,
      PanelFlyoutItem() => 32.0,
    };
  }
  final anchorTopLeft = button.localToGlobal(anchor.topLeft, ancestor: overlay);
  final anchorBottomLeft = button.localToGlobal(
    anchor.bottomLeft,
    ancestor: overlay,
  );
  final spaceBelow = overlay.size.height - anchorBottomLeft.dy;
  final openUpward =
      estimatedHeight > spaceBelow && anchorTopLeft.dy > spaceBelow;
  final menuAnchorRect = openUpward
      ? Rect.fromLTWH(
          anchorTopLeft.dx,
          anchorTopLeft.dy - estimatedHeight,
          anchor.width,
          estimatedHeight,
        )
      : Rect.fromPoints(
          anchorBottomLeft,
          button.localToGlobal(anchor.bottomRight, ancestor: overlay),
        );
  final position = RelativeRect.fromRect(
    menuAnchorRect,
    Offset.zero & overlay.size,
  );

  final selected = await showMenu<PanelFlyoutItem>(
    context: anchorContext,
    position: position,
    // Instant open/close (R4 #2): the whole list appears in one frame.
    popUpAnimationStyle: instantMenuAnimation,
    items: [
      for (final entry in entries)
        switch (entry) {
          PanelFlyoutHeader(:final label) => PopupMenuItem<PanelFlyoutItem>(
            enabled: false,
            height: 24,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textDim),
            ),
          ),
          PanelFlyoutDivider() =>
            const PopupMenuDivider(height: 6)
                as PopupMenuEntry<PanelFlyoutItem>,
          PanelFlyoutItem() => PopupMenuItem<PanelFlyoutItem>(
            key: ValueKey<String>(entry.keyValue),
            value: entry,
            enabled: entry.enabled,
            height: 32,
            child: Row(
              children: [
                if (entry.icon != null) ...[
                  Icon(
                    entry.icon,
                    size: 16,
                    color: !entry.enabled
                        ? AppColors.textDim.withValues(alpha: 0.5)
                        : entry.danger
                        ? AppColors.danger
                        : AppColors.text,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: !entry.enabled
                          ? AppColors.textDim.withValues(alpha: 0.5)
                          : entry.danger
                          ? AppColors.danger
                          : AppColors.text,
                    ),
                  ),
                ),
                if (entry.checked == true) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 14, color: AppColors.accent),
                ],
              ],
            ),
          ),
        },
    ],
  );
  selected?.onSelected?.call();
}

/// A labeled flyout trigger ('Layer ▾', 'Frame ▾', 'Cut ▾'): compact
/// bordered chip that opens [showPanelFlyout] with lazily built entries.
class PanelFlyoutButton extends StatelessWidget {
  const PanelFlyoutButton({
    super.key,
    required this.label,
    required this.entriesBuilder,
    this.tooltip,
    this.showCaret = true,
    this.fontSize = 12,
    this.labelColor,
    this.fontWeight,
    this.padding = const EdgeInsets.fromLTRB(8, 4, 5, 4),
    this.expand = false,
  });

  final String label;
  final List<PanelFlyoutEntry> Function() entriesBuilder;
  final String? tooltip;

  /// R28 #2: the caret is optional. Slot-width rails (the layer rail's
  /// blend column) drop it and keep the text alone — the border still
  /// says "button", which is the whole point of sharing this widget.
  final bool showCaret;

  final double fontSize;

  /// Null = the standard button ink; callers pass a color to carry state
  /// (the layer rail accents a non-normal mode).
  final Color? labelColor;
  final FontWeight? fontWeight;
  final EdgeInsetsGeometry padding;

  /// Fill the parent's width and CENTER the label instead of hugging it —
  /// how a fixed-width rail column keeps its button centered in the slot.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: expand ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: fontSize,
        color: labelColor ?? AppColors.text,
        fontWeight: fontWeight,
      ),
    );
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showPanelFlyout(context, entries: entriesBuilder()),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (expand) Flexible(child: text) else text,
                if (showCaret) ...[
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.textDim,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) {
      return chip;
    }
    return Tooltip(message: tooltip!, child: chip);
  }
}
