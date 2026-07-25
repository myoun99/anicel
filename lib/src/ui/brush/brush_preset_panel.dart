import 'package:flutter/material.dart';

import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../panels/editor_panel_frame.dart';
import '../panels/panel_scrollbar.dart';
import '../theme/app_theme.dart' show instantMenuAnimation;
import 'brush_preset_reorder.dart';
import 'brush_stroke_preview.dart';
import 'brush_tip_preview.dart';

/// Which row elements the brush list shows; every combination except
/// all-hidden is allowed (the options menu disables the last visible one).
enum _BrushPresetMenuAction {
  toggleIcon,
  toggleStroke,
  toggleName,
  rename,
  delete,
}

/// Label for presets without a [BrushPreset.group] (built-ins, hand-saved).
const String _defaultGroupLabel = 'Default';

/// One flattened list entry: either a group header or a preset row.
class _ListEntry {
  const _ListEntry.header(this.groupValue) : preset = null, isHeader = true;
  const _ListEntry.preset(BrushPreset this.preset)
    : groupValue = null,
      isHeader = false;

  final bool isHeader;

  /// The header's group value (`null` = the default/ungrouped section).
  final String? groupValue;
  final BrushPreset? preset;

  String get headerLabel => groupValue ?? _defaultGroupLabel;
}

/// The brush library panel: one row per preset with a tip icon, a stroke
/// preview, and the preset name — each hideable from the options menu.
///
/// Split out of [BrushSettingsPanel] so the dock reads Clip-Studio-like —
/// brush list on top, tool properties below — while staying icon-first.
/// Tapping a row applies the preset; dragging a row reorders it (dropping
/// under another group's header moves it into that group). Destructive and
/// name-editing actions live behind the header options menu
/// (Photoshop-style) acting on the selected preset.
class BrushPresetPanel extends StatefulWidget {
  const BrushPresetPanel({
    super.key,
    required this.presets,
    this.selectedPresetId,
    this.onPresetApplied,
    this.onPresetSaveRequested,
    this.onPresetDeleted,
    this.onPresetImportRequested,
    this.onPresetRenamed,
    this.onPresetsReordered,
  });

  final List<BrushPreset> presets;

  /// The last-applied preset; its row is highlighted and the options menu
  /// targets it. Tweaking settings afterwards keeps the highlight (the row
  /// is a starting point, not a live equality check).
  final BrushPresetId? selectedPresetId;

  final ValueChanged<BrushPreset>? onPresetApplied;
  final VoidCallback? onPresetSaveRequested;
  final ValueChanged<BrushPresetId>? onPresetDeleted;
  final VoidCallback? onPresetImportRequested;

  /// Called with the selected preset's id and its new (trimmed) name.
  final void Function(BrushPresetId id, String name)? onPresetRenamed;

  /// Called with the full reordered library after a drag (the moved preset
  /// may carry a new group when dropped under another group's header).
  final ValueChanged<List<BrushPreset>>? onPresetsReordered;

  /// Caps the list; beyond this the list scrolls inside the panel instead
  /// of growing the dock.
  static const double _maxListHeight = 312;

  @override
  State<BrushPresetPanel> createState() => _BrushPresetPanelState();
}

class _BrushPresetPanelState extends State<BrushPresetPanel> {
  final ScrollController _scrollController = ScrollController();

  // View options are editor-session UI state local to the panel; they are
  // deliberately not persisted or project data.
  bool _showTipIcon = true;
  bool _showStrokePreview = true;
  bool _showName = true;

  /// Collapsed group labels; groups start expanded.
  final Set<String> _collapsedGroups = <String>{};

  int get _visibleElementCount =>
      (_showTipIcon ? 1 : 0) +
      (_showStrokePreview ? 1 : 0) +
      (_showName ? 1 : 0);

  /// A checked view toggle can be unchecked only while another element
  /// stays visible; rows must never go completely blank.
  bool _canToggleOff(bool currentlyVisible) {
    return !currentlyVisible || _visibleElementCount > 1;
  }

  /// Flattens presets into header + row entries, preserving preset order;
  /// group order follows first appearance. When every preset is ungrouped
  /// the headers are omitted entirely (a lone "Default" header is noise).
  List<_ListEntry> _buildEntries() {
    final groupOrder = <String?>[];
    final buckets = <String?, List<BrushPreset>>{};
    for (final preset in widget.presets) {
      final bucket = buckets[preset.group];
      if (bucket == null) {
        groupOrder.add(preset.group);
        buckets[preset.group] = [preset];
      } else {
        bucket.add(preset);
      }
    }
    if (groupOrder.length == 1 && groupOrder.single == null) {
      return [for (final preset in widget.presets) _ListEntry.preset(preset)];
    }
    return [
      for (final group in groupOrder) ...[
        _ListEntry.header(group),
        if (!_collapsedGroups.contains(group ?? _defaultGroupLabel))
          for (final preset in buckets[group]!) _ListEntry.preset(preset),
      ],
    ];
  }

  void _onMenuSelected(_BrushPresetMenuAction action) {
    switch (action) {
      case _BrushPresetMenuAction.toggleIcon:
        setState(() => _showTipIcon = !_showTipIcon);
      case _BrushPresetMenuAction.toggleStroke:
        setState(() => _showStrokePreview = !_showStrokePreview);
      case _BrushPresetMenuAction.toggleName:
        setState(() => _showName = !_showName);
      case _BrushPresetMenuAction.rename:
        _renameSelectedPreset();
      case _BrushPresetMenuAction.delete:
        final selectedId = widget.selectedPresetId;
        if (selectedId != null) {
          widget.onPresetDeleted!(selectedId);
        }
    }
  }

  Future<void> _renameSelectedPreset() async {
    final selectedId = widget.selectedPresetId;
    final onRenamed = widget.onPresetRenamed;
    if (selectedId == null || onRenamed == null) {
      return;
    }
    BrushPreset? selected;
    for (final preset in widget.presets) {
      if (preset.id == selectedId) {
        selected = preset;
        break;
      }
    }
    if (selected == null) {
      return;
    }

    final nextName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameBrushPresetDialog(initialName: selected!.name),
    );
    if (!mounted || nextName == null) {
      return;
    }
    onRenamed(selectedId, nextName);
  }

  /// Maps a drag in the flattened entry list onto the library move: the
  /// entry before the drop position decides the target group and anchor.
  /// [newIndex] is already adjusted for the removed item (onReorderItem
  /// semantics).
  void _handleReorder(List<_ListEntry> entries, int oldIndex, int newIndex) {
    final onReordered = widget.onPresetsReordered;
    final moved = oldIndex < entries.length ? entries[oldIndex].preset : null;
    if (onReordered == null || moved == null) {
      return;
    }
    final without = [...entries]..removeAt(oldIndex);
    final clampedIndex = newIndex.clamp(0, without.length);
    final previous = clampedIndex > 0 ? without[clampedIndex - 1] : null;
    final next = clampedIndex < without.length ? without[clampedIndex] : null;

    String? targetGroup;
    BrushPresetId? insertBeforeId;
    if (previous == null) {
      if (next == null) {
        return;
      }
      // Dropped at the very top: join whatever comes first.
      targetGroup = next.isHeader ? next.groupValue : next.preset!.group;
      insertBeforeId = next.isHeader
          ? _firstMemberId(next.groupValue, excluding: moved.id)
          : next.preset!.id;
    } else if (!previous.isHeader) {
      // Right after another preset: same group, before the next member of
      // that group (or appended when the group ends here).
      targetGroup = previous.preset!.group;
      final nextPreset = next?.preset;
      insertBeforeId = (nextPreset != null && nextPreset.group == targetGroup)
          ? nextPreset.id
          : null;
    } else {
      // Right under a header: become the group's first member (works for
      // collapsed groups too — members need not be visible).
      targetGroup = previous.groupValue;
      insertBeforeId = _firstMemberId(targetGroup, excluding: moved.id);
    }

    onReordered(
      moveBrushPresetInLibrary(
        presets: widget.presets,
        movedId: moved.id,
        targetGroup: targetGroup,
        insertBeforeId: insertBeforeId,
      ),
    );
  }

  BrushPresetId? _firstMemberId(String? group, {BrushPresetId? excluding}) {
    for (final preset in widget.presets) {
      if (preset.group == group && preset.id != excluding) {
        return preset.id;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = _buildEntries();
    final reorderable = widget.onPresetsReordered != null;
    return EditorPanelFrame(
      title: 'Brushes',
      bodyPadding: const EdgeInsets.all(5),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onPresetImportRequested != null)
            IconButton(
              key: const ValueKey<String>('brush-preset-import-button'),
              icon: const Icon(Icons.file_open_outlined, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Import brushes (.abr, .sut, .sutg)',
              onPressed: widget.onPresetImportRequested,
            ),
          if (widget.onPresetSaveRequested != null)
            IconButton(
              key: const ValueKey<String>('brush-preset-save-button'),
              icon: const Icon(Icons.add, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Save current settings as preset',
              onPressed: widget.onPresetSaveRequested,
            ),
          PopupMenuButton<_BrushPresetMenuAction>(
            key: const ValueKey<String>('brush-preset-menu-button'),
            tooltip: 'Brush options',
            popUpAnimationStyle: instantMenuAnimation,
            icon: const Icon(Icons.more_vert, size: 16),
            padding: EdgeInsets.zero,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<_BrushPresetMenuAction>(
                key: const ValueKey<String>('brush-preset-view-icon-toggle'),
                value: _BrushPresetMenuAction.toggleIcon,
                height: 34,
                checked: _showTipIcon,
                enabled: _canToggleOff(_showTipIcon),
                child: const Text('Tip icon'),
              ),
              CheckedPopupMenuItem<_BrushPresetMenuAction>(
                key: const ValueKey<String>('brush-preset-view-stroke-toggle'),
                value: _BrushPresetMenuAction.toggleStroke,
                height: 34,
                checked: _showStrokePreview,
                enabled: _canToggleOff(_showStrokePreview),
                child: const Text('Stroke preview'),
              ),
              CheckedPopupMenuItem<_BrushPresetMenuAction>(
                key: const ValueKey<String>('brush-preset-view-name-toggle'),
                value: _BrushPresetMenuAction.toggleName,
                height: 34,
                checked: _showName,
                enabled: _canToggleOff(_showName),
                child: const Text('Name'),
              ),
              if (widget.onPresetRenamed != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem<_BrushPresetMenuAction>(
                  key: const ValueKey<String>('brush-preset-menu-rename'),
                  value: _BrushPresetMenuAction.rename,
                  height: 34,
                  enabled: widget.selectedPresetId != null,
                  child: const Text('Rename selected brush'),
                ),
              ],
              if (widget.onPresetDeleted != null) ...[
                if (widget.onPresetRenamed == null) const PopupMenuDivider(),
                PopupMenuItem<_BrushPresetMenuAction>(
                  key: const ValueKey<String>('brush-preset-menu-delete'),
                  value: _BrushPresetMenuAction.delete,
                  height: 34,
                  enabled: widget.selectedPresetId != null,
                  child: const Text('Delete selected brush'),
                ),
              ],
            ],
          ),
        ],
      ),
      child: widget.presets.isEmpty
          ? SizedBox(
              height: 56,
              child: Center(
                child: Icon(
                  Icons.brush_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: BrushPresetPanel._maxListHeight,
              ),
              child: PanelScrollbar(
                controller: _scrollController,
                child: ReorderableListView.builder(
                  key: const ValueKey<String>('brush-preset-list'),
                  scrollController: _scrollController,
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(right: panelScrollbarGutter),
                  itemCount: entries.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _handleReorder(entries, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    if (entry.isHeader) {
                      final label = entry.headerLabel;
                      return KeyedSubtree(
                        key: ValueKey<String>(
                          'brush-preset-entry-header-$label',
                        ),
                        child: _BrushGroupHeader(
                          label: label,
                          collapsed: _collapsedGroups.contains(label),
                          onToggle: () {
                            setState(() {
                              if (!_collapsedGroups.remove(label)) {
                                _collapsedGroups.add(label);
                              }
                            });
                          },
                        ),
                      );
                    }
                    final preset = entry.preset!;
                    final row = _BrushPresetRow(
                      preset: preset,
                      selected: preset.id == widget.selectedPresetId,
                      onApplied: widget.onPresetApplied,
                      showTipIcon: _showTipIcon,
                      showStrokePreview: _showStrokePreview,
                      showName: _showName,
                    );
                    return KeyedSubtree(
                      key: ValueKey<String>(
                        'brush-preset-entry-${preset.id.value}',
                      ),
                      child: reorderable
                          ? ReorderableDragStartListener(
                              index: index,
                              child: row,
                            )
                          : row,
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// A flat collapsible group header (chevron + name), Clip-Studio-like.
class _BrushGroupHeader extends StatelessWidget {
  const _BrushGroupHeader({
    required this.label,
    required this.collapsed,
    required this.onToggle,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey<String>('brush-preset-group-$label'),
      onTap: onToggle,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 15,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameBrushPresetDialog extends StatelessWidget {
  const _RenameBrushPresetDialog({required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: const ValueKey<String>('brush-preset-rename-dialog'),
      title: 'Rename brush',
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: 'Brush name',
      initialValue: initialName,
      confirmLabel: 'Rename',
      emptyError: 'Brush name cannot be empty.',
      fieldKey: const ValueKey<String>('brush-preset-rename-text-field'),
      cancelKey: const ValueKey<String>('brush-preset-rename-cancel-button'),
      confirmKey: const ValueKey<String>('brush-preset-rename-ok-button'),
    );
  }
}

class _BrushPresetRow extends StatelessWidget {
  const _BrushPresetRow({
    required this.preset,
    required this.selected,
    required this.onApplied,
    required this.showTipIcon,
    required this.showStrokePreview,
    required this.showName,
  });

  final BrushPreset preset;
  final bool selected;
  final ValueChanged<BrushPreset>? onApplied;
  final bool showTipIcon;
  final bool showStrokePreview;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          // Key kept from the former chip UI so existing flows/tests hold.
          key: ValueKey<String>('brush-preset-chip-${preset.id.value}'),
          borderRadius: BorderRadius.circular(6),
          onTap: onApplied == null ? null : () => onApplied!(preset),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: 5,
                  child: selected
                      ? Center(
                          child: Container(
                            width: 2,
                            height: 22,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        )
                      : null,
                ),
                if (showTipIcon) ...[
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: BrushTipPreview(settings: preset.settings),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: _rowBody(colorScheme)),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowBody(ColorScheme colorScheme) {
    final nameColor = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    if (!showStrokePreview) {
      if (!showName) {
        return const SizedBox.shrink();
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: nameColor),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: BrushStrokePreview(settings: preset.settings),
        ),
        if (showName)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 132),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color:
                    (selected
                            ? colorScheme.surfaceContainerHigh
                            : colorScheme.surface)
                        .withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: nameColor),
              ),
            ),
          ),
      ],
    );
  }
}
