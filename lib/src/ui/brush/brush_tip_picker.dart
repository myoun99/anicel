import '../widgets/app_tooltip.dart';
import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';

import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_mask.dart';
import '../text/app_strings.dart';
import '../widgets/anchored_popup.dart';
import 'brush_tip_preview.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;
import '../widgets/field_slider.dart' show FieldSlider;
import '../widgets/instant_tap_region.dart';
import 'brush_preset_reorder_grid.dart' show BrushPresetReorderGrid;
import 'tool_setting_rows.dart' show ToolSettingRow;

/// Which of a brush's three mask slots a picker drives.
///
/// They are the same TYPE and the same library — Clip Studio treats a brush
/// tip and a paper texture as two categories of one material system — so one
/// picker serves all three rather than three that drift apart.
enum BrushTipRole {
  /// The tips themselves: they replace the parametric round footprint, and
  /// there may be several, which the dabs take in turn (F-176-Q3).
  tip,

  /// A second tip multiplied into the first, breaking it up.
  dual,

  /// Canvas-anchored paper texture, multiplied in after the dabs.
  texture;

  /// Whether the slot holds a LIST — the brush's tips — rather than one
  /// mask at most.
  bool get takesSeveral => this == tip;
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

  /// The masks in this slot, in the order the dabs take them — one at most
  /// but for [BrushTipRole.tip]. None is the parametric tip for
  /// [BrushTipRole.tip] and nothing at all for the other two.
  final List<BrushTipMask> selected;

  final List<BrushTipEntry> tips;

  /// Called with the slot's masks as picked — empty for the "none" cell.
  final ValueChanged<List<BrushTipMask>> onPicked;

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

  /// A row of the tool settings' grid, the tip at the end of the control
  /// column where a swatch stands (tool-settings-panel-tidy, 유저 2026-10-10:
  /// 「정돈된 행/열」). ↩️It wrote its own line of a name and the button.
  ///
  /// The swatch is the FIRST tip — the one picture of the brush that its
  /// cursor shows too; its tooltip names them all.
  @override
  Widget build(BuildContext context) {
    return ToolSettingRow.atEnd(
      label: label,
      child: _TipSwatch(
        keyValue: 'brush-tip-picker-${role.name}',
        tooltip: selected.isEmpty
            ? AppText.strings.brTipNone
            : [for (final mask in selected) _nameFor(mask.id)].join(', '),
        mask: selected.firstOrNull,
        onTap: () => _openPicker(context),
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
  /// math — so the body carries this itself. The tips' slot is taller by
  /// the strip that holds their order.
  static const double _popupHeight = 268;

  double get _heightOfPopup =>
      _popupHeight + (role.takesSeveral ? _turnStripHeight : 0);

  Future<void> _openPicker(BuildContext context) async {
    // The pick is held here and applied when the window goes away
    // (유저 안: "선택인 채로 다른 곳 눌러서 닫으면 적용"). Picking used to BE
    // the dismiss, which left no moment where a tip was both chosen and
    // still on screen — and therefore nowhere for Rename and Delete to
    // live.
    var pending = selected;
    var picked = false;
    final height = _heightOfPopup;
    await showAnchoredPopup<void>(
      context,
      label: 'brush-tip-picker-popup',
      width: 232,
      height: height,
      builder: (popupContext, close) => _BrushTipPickerBody(
        height: height,
        role: role,
        tips: tips,
        selected: selected,
        onRenameTip: onRenameTip,
        onDeleteTip: onDeleteTip,
        onPicked: (masks) {
          pending = masks;
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
    return AppTooltip(
      message: tooltip,
      child: ControlPressClaim(
        onPressed: onTap,
        child: InkWell(
          key: ValueKey<String>(keyValue),
          onTap: silentPress(onTap),
          customBorder: AppShapes.container(AppShapes.wellRadius),
          // One row high, as every control of the grid it stands in is.
          child: Container(
            width: FieldSlider.defaultHeight,
            height: FieldSlider.defaultHeight,
            decoration: ShapeDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: AppShapes.container(
                AppShapes.wellRadius,
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
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
      ),
    );
  }
}

/// One cell of the strip that holds a brush's tips in their order, square.
const double _turnCellExtent = 40;

/// The strip in the tips' popup: two rows of its cells under the gap the
/// header leaves, scrolling past them.
const double _turnStripHeight =
    AnchoredPopupText.titleGap + 2 * _turnCellExtent;

/// One tip in the brush's order, under a key of its own — the same tip
/// taken twice is still two cells to drag.
typedef _Turn = ({int key, BrushTipMask mask});

class _BrushTipPickerBody extends StatefulWidget {
  const _BrushTipPickerBody({
    required this.height,
    required this.role,
    required this.tips,
    required this.selected,
    required this.onPicked,
    required this.onImportRequested,
    required this.onRenameTip,
    required this.onDeleteTip,
  });

  final double height;
  final BrushTipRole role;
  final List<BrushTipEntry> tips;
  final List<BrushTipMask> selected;
  final ValueChanged<List<BrushTipMask>> onPicked;
  final VoidCallback? onImportRequested;
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  @override
  State<_BrushTipPickerBody> createState() => _BrushTipPickerBodyState();
}

class _BrushTipPickerBodyState extends State<_BrushTipPickerBody> {
  int _turnKeys = 0;

  /// The slot as picked so far, in order.
  late List<_Turn> _picked = [
    for (final mask in widget.selected) _turnOf(mask),
  ];

  /// The tip the manage row acts on: the one pressed last.
  late String? _managedId = widget.selected.firstOrNull?.id;

  _Turn _turnOf(BrushTipMask mask) {
    _turnKeys += 1;
    return (key: _turnKeys, mask: mask);
  }

  BrushTipEntry? get _managedTip {
    final id = _managedId;
    return id == null
        ? null
        : widget.tips.where((tip) => tip.id == id).firstOrNull;
  }

  bool _holds(String id) => _picked.any((turn) => turn.mask.id == id);

  /// A library cell pressed — [mask] null for the "none" cell. The tips'
  /// slot takes a pressed tip IN, or back OUT wherever it stands when it
  /// holds it already (F-176-Q3: several tips); a one-mask slot takes it
  /// instead of what it held.
  void _press(String? id, BrushTipMask? mask) {
    setState(() {
      _managedId = id;
      if (mask == null) {
        _picked = [];
      } else if (!widget.role.takesSeveral) {
        _picked = [_turnOf(mask)];
      } else if (_holds(mask.id)) {
        _picked = [
          for (final turn in _picked)
            if (turn.mask.id != mask.id) turn,
        ];
      } else {
        _picked = [..._picked, _turnOf(mask)];
      }
    });
    _report();
  }

  /// A tip in the strip dragged from [from] to the target [to] — a position
  /// in the list without it (`reorder_target.dart`).
  void _reorder(int? from, int to) {
    if (from == null) {
      return;
    }
    setState(() {
      final moved = _picked[from];
      _picked = [..._picked]
        ..removeAt(from)
        ..insert(to, moved);
    });
    _report();
  }

  void _report() => widget.onPicked([for (final turn in _picked) turn.mask]);

  /// The brush's tips in the order its dabs take them — drag one to move it
  /// (F-176-Q3 「끌어서 순서」), press one to manage it below.
  ///
  /// ⚠️THE PRESET LIST'S OWN GRID ([BrushPresetReorderGrid]): its cells lift
  /// once the press leaves them (F-138) and land by the one reorder law, so
  /// a tip moves the way a brush does.
  Widget _strip(ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AnchoredPopupText.bodyPadding.left,
        AnchoredPopupText.titleGap,
        AnchoredPopupText.bodyPadding.right,
        0,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colorScheme.surfaceContainerHighest,
          shape: AppShapes.container(
            AppShapes.wellRadius,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: SizedBox(
          key: const ValueKey<String>('brush-tip-turns'),
          height: _turnStripHeight - AnchoredPopupText.titleGap,
          child: BrushPresetReorderGrid(
            itemCount: _picked.length,
            cellHeight: _turnCellExtent,
            cellTargetWidth: _turnCellExtent,
            maxColumns: null,
            itemKey: (index) =>
                ValueKey<String>('brush-tip-turn-${_picked[index].key}'),
            itemBuilder: (context, index) {
              final turn = _picked[index];
              return Padding(
                padding: const EdgeInsets.all(2),
                child: _TurnCell(
                  index: index,
                  tooltip:
                      widget.tips
                          .where((tip) => tip.id == turn.mask.id)
                          .firstOrNull
                          ?.name ??
                      turn.mask.id,
                  selected: turn.mask.id == _managedId,
                  onTap: () => setState(() => _managedId = turn.mask.id),
                  mask: turn.mask,
                ),
              );
            },
            onReorder: _reorder,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = widget.height;
    final tips = widget.tips;
    final onImportRequested = widget.onImportRequested;
    final managed = _managedTip;
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
                  : AppIconButton(
                      keyValue: 'brush-tip-picker-add',
                      tooltip: AppText.strings.brAddTipImage,
                      size: AppIconButtonSize.dense,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: onImportRequested,
                    ),
            ),
          ),
          if (widget.role.takesSeveral) _strip(theme.colorScheme),
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
                  selected: _picked.isEmpty,
                  onTap: () => _press(null, null),
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
                    selected: _holds(tip.id),
                    // A tip whose image has not landed yet cannot be applied —
                    // its thumbnail is a preview, not the mask.
                    onTap: tip.mask == null
                        ? null
                        : () => _press(tip.id, tip.mask),
                    child: BrushTipMaskPreview(
                      alpha: tip.mask?.alpha ?? tip.thumbnail,
                      side: tip.mask?.size ?? brushTipThumbnailSide,
                    ),
                  ),
              ],
            ),
          ),
          // Manage the tip pressed last. Absent entirely when the host wires
          // no handlers, and dead when that was "none" or a built-in — those
          // are not the user's to remove.
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
                    AppIconButton(
                      keyValue: 'brush-tip-rename',
                      tooltip: AppText.strings.brRenameTip,
                      size: AppIconButtonSize.dense,
                      icon: const Icon(Icons.drive_file_rename_outline),
                      onPressed: managed == null
                          ? null
                          : () => onRename(managed),
                    ),
                  if (onDelete != null)
                    AppIconButton(
                      keyValue: 'brush-tip-delete',
                      tooltip: AppText.strings.brDeleteTip,
                      size: AppIconButtonSize.dense,
                      icon: const Icon(Icons.delete_outline),
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
    return AppTooltip(
      message: tooltip,
      child: Material(
        color: _cellFill(colorScheme, selected: selected),
        shape: AppShapes.container(AppShapes.wellRadius),
        child: ControlPressClaim(
          onPressed: onTap,
          child: InkWell(
            key: ValueKey<String>(keyValue),
            onTap: silentPress(onTap),
            customBorder: AppShapes.container(AppShapes.wellRadius),
            child: Container(
              decoration: _cellFrame(colorScheme, selected: selected),
              padding: const EdgeInsets.all(2),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tip in the strip: pressed, it is the one the manage row acts on;
/// dragged, it moves.
///
/// 🚨PRESSED THE WAY A BRUSH IN THE LIST IS ([InstantTapRegion]), NOT CLAIMED
/// like the library's cells: a claim's absorbers sit inside the cell and take
/// the arena on the first move, so the grid's drag would never start — the
/// lesson the preset row taught first (`brush-preset-chip-` in
/// `every_button_claims_its_press_test`).
class _TurnCell extends StatelessWidget {
  const _TurnCell({
    required this.index,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.mask,
  });

  final int index;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final BrushTipMask mask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppTooltip(
      message: tooltip,
      child: InstantTapRegion(
        onTap: (_) => onTap(),
        child: Material(
          color: _cellFill(colorScheme, selected: selected),
          shape: AppShapes.container(AppShapes.wellRadius),
          child: InkWell(
            key: ValueKey<String>('brush-tip-turn-at-$index'),
            // Its ripple only — the press is [InstantTapRegion]'s.
            onTap: silentPress(onTap),
            customBorder: AppShapes.container(AppShapes.wellRadius),
            child: Container(
              decoration: _cellFrame(colorScheme, selected: selected),
              padding: const EdgeInsets.all(2),
              child: BrushTipMaskPreview(alpha: mask.alpha, side: mask.size),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cell's fill, for either grid.
Color _cellFill(ColorScheme colorScheme, {required bool selected}) =>
    selected ? colorScheme.surfaceContainerHigh : Colors.transparent;

/// A cell's frame, for either grid. Selection reads from the border colour,
/// not a glyph, which would shift the grid.
ShapeDecoration _cellFrame(ColorScheme colorScheme, {required bool selected}) =>
    ShapeDecoration(
      shape: AppShapes.container(
        AppShapes.wellRadius,
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
    );
