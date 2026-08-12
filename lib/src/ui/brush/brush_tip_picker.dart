import 'package:flutter/material.dart';

import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_mask.dart';
import '../text/app_strings.dart';
import '../widgets/anchored_popup.dart';
import 'brush_tip_preview.dart';

/// Which of a brush's three mask slots a picker drives.
///
/// They are the same TYPE and the same library — Clip Studio treats a brush
/// tip and a paper texture as two categories of one material system — so one
/// picker serves all three rather than three that drift apart.
enum BrushTipRole {
  /// The tip itself: replaces the parametric round/square footprint.
  tip,

  /// A second tip multiplied into the first, breaking it up.
  dual,

  /// Canvas-anchored paper texture, multiplied in after the dabs.
  texture,
}

/// A settings row that shows the current mask and opens the library to
/// change it.
class BrushTipPickerRow extends StatelessWidget {
  const BrushTipPickerRow({
    super.key,
    required this.label,
    required this.role,
    required this.selected,
    required this.tips,
    required this.onPicked,
    this.onImportRequested,
    this.onRenameTip,
    this.onDeleteTip,
  });

  final String label;
  final BrushTipRole role;

  /// The mask currently in this slot; `null` means none — the parametric
  /// tip for [BrushTipRole.tip], nothing at all for the other two.
  final BrushTipMask? selected;

  final List<BrushTipEntry> tips;

  /// Called with the chosen mask, or `null` for the "none" cell.
  final ValueChanged<BrushTipMask?> onPicked;

  /// Opens the add-an-image flow, when the host wires one.
  final VoidCallback? onImportRequested;

  /// Manage the picked tip. Null handlers leave the buttons out entirely
  /// (hosts that only choose, and the built-in tips, which are not the
  /// user's to remove).
  ///
  /// These are the reason the popup no longer closes the moment you pick:
  /// with picking as a dismiss, there was never a moment where a tip was
  /// both chosen and still on screen, so a delete button had nothing to
  /// stand next to.
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.labelSmall)),
          _TipSwatch(
            keyValue: 'brush-tip-picker-${role.name}',
            tooltip: current == null
                ? AppText.strings.brTipNone
                : _nameFor(current.id),
            mask: current,
            onTap: () => _openPicker(context),
          ),
        ],
      ),
    );
  }

  String _nameFor(String id) {
    for (final tip in tips) {
      if (tip.id == id) {
        return tip.name;
      }
    }
    // A preset can reference a tip this library no longer holds; showing the
    // id beats showing nothing, because it says WHAT is missing.
    return id;
  }

  /// The popup only constrains WIDTH — its height argument is placement
  /// math — so the body carries this itself.
  static const double _popupHeight = 268;

  Future<void> _openPicker(BuildContext context) async {
    // The pick is held here and applied when the window goes away
    // (유저 안: "선택인 채로 다른 곳 눌러서 닫으면 적용"). Picking used to BE
    // the dismiss, which left no moment where a tip was both chosen and
    // still on screen — and therefore nowhere for Rename and Delete to
    // live.
    var pending = selected;
    var picked = false;
    await showAnchoredPopup<void>(
      context,
      label: 'brush-tip-picker-popup',
      width: 232,
      height: _popupHeight,
      builder: (popupContext, close) => _BrushTipPickerBody(
        height: _popupHeight,
        role: role,
        tips: tips,
        selectedId: selected?.id,
        onRenameTip: onRenameTip,
        onDeleteTip: onDeleteTip,
        onPicked: (mask) {
          pending = mask;
          picked = true;
        },
        onImportRequested: onImportRequested == null
            ? null
            : () {
                close();
                onImportRequested!();
              },
      ),
    );
    if (picked) {
      onPicked(pending);
    }
  }
}

/// The swatch that stands in for the current mask: its shape, or a hollow
/// slot when there is none.
class _TipSwatch extends StatelessWidget {
  const _TipSwatch({
    required this.keyValue,
    required this.tooltip,
    required this.mask,
    required this.onTap,
  });

  final String keyValue;
  final String tooltip;
  final BrushTipMask? mask;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = mask;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey<String>(keyValue),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: current == null
              ? Icon(
                  Icons.remove,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                )
              : BrushTipMaskPreview(alpha: current.alpha, side: current.size),
        ),
      ),
    );
  }
}

class _BrushTipPickerBody extends StatefulWidget {
  const _BrushTipPickerBody({
    required this.height,
    required this.role,
    required this.tips,
    required this.selectedId,
    required this.onPicked,
    required this.onImportRequested,
    required this.onRenameTip,
    required this.onDeleteTip,
  });

  final double height;
  final BrushTipRole role;
  final List<BrushTipEntry> tips;
  final String? selectedId;
  final ValueChanged<BrushTipMask?> onPicked;
  final VoidCallback? onImportRequested;
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  @override
  State<_BrushTipPickerBody> createState() => _BrushTipPickerBodyState();
}

class _BrushTipPickerBodyState extends State<_BrushTipPickerBody> {
  late String? _pickedId = widget.selectedId;

  BrushTipEntry? get _pickedTip {
    final id = _pickedId;
    if (id == null) {
      return null;
    }
    for (final tip in widget.tips) {
      if (tip.id == id) {
        return tip;
      }
    }
    return null;
  }

  void _pick(String? id, BrushTipMask? mask) {
    setState(() => _pickedId = id);
    widget.onPicked(mask);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = widget.height;
    final tips = widget.tips;
    final selectedId = _pickedId;
    final onImportRequested = widget.onImportRequested;
    final managed = _pickedTip;
    final onRename = widget.onRenameTip;
    final onDelete = widget.onDeleteTip;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // The window's one margin, minus the bottom — the grid below
            // supplies the gap and lines its own sides up with this.
            padding: AnchoredPopupText.bodyPadding.copyWith(bottom: 0),
            child: AnchoredPopupHeader(
              title: AppText.strings.brBrushTip,
              trailing: onImportRequested == null
                  ? null
                  : IconButton(
                      key: const ValueKey<String>('brush-tip-picker-add'),
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 16,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: AppText.strings.brAddTipImage,
                      onPressed: onImportRequested,
                    ),
            ),
          ),
          Expanded(
            child: GridView.count(
              key: const ValueKey<String>('brush-tip-picker-grid'),
              crossAxisCount: 5,
              // Lined up with the header above rather than 4px inside it,
              // and carrying the gap under it — the header's own bottom is
              // zero so that this one number decides the distance.
              padding: EdgeInsets.fromLTRB(
                AnchoredPopupText.bodyPadding.left,
                AnchoredPopupText.titleGap,
                AnchoredPopupText.bodyPadding.right,
                0,
              ),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                _PickerCell(
                  keyValue: 'brush-tip-cell-none',
                  tooltip: AppText.strings.brTipNone,
                  selected: selectedId == null,
                  onTap: () => _pick(null, null),
                  child: Icon(
                    Icons.remove,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final tip in tips)
                  _PickerCell(
                    keyValue: 'brush-tip-cell-${tip.id}',
                    tooltip: tip.name,
                    selected: tip.id == selectedId,
                    // A tip whose image has not landed yet cannot be applied —
                    // its thumbnail is a preview, not the mask.
                    onTap: tip.mask == null
                        ? null
                        : () => _pick(tip.id, tip.mask),
                    child: BrushTipMaskPreview(
                      alpha: tip.mask?.alpha ?? tip.thumbnail,
                      side: tip.mask?.size ?? brushTipThumbnailSide,
                    ),
                  ),
              ],
            ),
          ),
          // Manage the tip that is currently picked. Absent entirely when
          // the host wires no handlers, and dead when what is picked is
          // "none" or a built-in — those are not the user's to remove.
          if (onRename != null || onDelete != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AnchoredPopupText.bodyPadding.left,
                4,
                AnchoredPopupText.bodyPadding.right,
                AnchoredPopupText.bodyPadding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      managed?.name ?? AppText.strings.brTipNone,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onRename != null)
                    IconButton(
                      key: const ValueKey<String>('brush-tip-rename'),
                      icon: const Icon(Icons.drive_file_rename_outline, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: AppText.strings.brRenameTip,
                      onPressed: managed == null
                          ? null
                          : () => onRename(managed),
                    ),
                  if (onDelete != null)
                    IconButton(
                      key: const ValueKey<String>('brush-tip-delete'),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: AppText.strings.brDeleteTip,
                      onPressed: managed == null
                          ? null
                          : () => onDelete(managed),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerCell extends StatelessWidget {
  const _PickerCell({
    required this.keyValue,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String keyValue;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey<String>(keyValue),
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                // Selection reads from the border colour alone — no check
                // glyph, which would shift the grid.
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(2),
            child: child,
          ),
        ),
      ),
    );
  }
}
