import 'package:flutter/material.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../panels/editor_panel_frame.dart';
import '../panels/panel_scrollbar.dart';
import '../theme/app_theme.dart' show instantMenuAnimation;
import '../widgets/app_window.dart';
import 'brush_preset_reorder.dart';
import 'brush_stroke_preview.dart';
import 'brush_tip_preview.dart';

/// Which row elements the brush list shows (every combination except
/// all-hidden is allowed — the options menu disables the last visible one),
/// plus the library-wide actions.
enum _BrushPresetMenuAction {
  toggleIcon,
  toggleStroke,
  toggleName,
  newGroup,
  rename,
  delete,
  reset,
}

/// The per-group header menu.
enum _BrushGroupMenuAction { rename, delete }

/// Label for the root section holding presets that belong to no group.
const String _rootSectionLabel = 'Default';

/// One flattened list entry: either a group header or a preset row.
class _ListEntry {
  /// A `null` [group] is the root section's header.
  const _ListEntry.header(this.group) : preset = null, isHeader = true;
  const _ListEntry.preset(BrushPreset this.preset)
    : group = null,
      isHeader = false;

  final bool isHeader;
  final BrushGroup? group;
  final BrushPreset? preset;
}

/// The brush library panel: one row per preset with a tip icon, a stroke
/// preview, and the preset name — each hideable from the options menu.
///
/// Split out of [BrushSettingsPanel] so the dock reads Clip-Studio-like —
/// brush list on top, tool properties below — while staying icon-first.
/// Tapping a row applies the preset; dragging a row reorders it (dropping
/// under a group's header moves it into that group) and dragging a HEADER
/// reorders the groups themselves. Destructive and name-editing actions live
/// behind the header options menu (Photoshop-style) acting on the selected
/// preset, and behind each group header's own menu for the group.
class BrushPresetPanel extends StatefulWidget {
  const BrushPresetPanel({
    super.key,
    required this.presets,
    this.groups = const <BrushGroup>[],
    this.selectedPresetId,
    this.onPresetApplied,
    this.onPresetSaveRequested,
    this.onPresetDeleted,
    this.onPresetImportRequested,
    this.onPresetRenamed,
    this.onPresetsReordered,
    this.onGroupCreated,
    this.onGroupRenamed,
    this.onGroupDeleted,
    this.onGroupCollapseChanged,
    this.onGroupsReordered,
    this.onLibraryReset,
  });

  final List<BrushPreset> presets;

  /// Library groups in display order. The root section (presets with no
  /// group) always sorts last, and when there are no groups at all the list
  /// renders headerless.
  final List<BrushGroup> groups;

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

  /// Called with the full reordered preset list after a row drag (the moved
  /// preset may carry a new group when dropped under another group's header).
  final ValueChanged<List<BrushPreset>>? onPresetsReordered;

  /// Called with the new group's name.
  final ValueChanged<String>? onGroupCreated;

  final void Function(BrushGroupId id, String name)? onGroupRenamed;

  /// Deletes the group AND every preset inside it (the panel confirms first,
  /// naming the count).
  final ValueChanged<BrushGroupId>? onGroupDeleted;

  final void Function(BrushGroupId id, bool collapsed)? onGroupCollapseChanged;

  /// Called with the full reordered group list after a header drag.
  final ValueChanged<List<BrushGroup>>? onGroupsReordered;

  /// Throws the library away and re-seeds the built-ins (confirmed first).
  final VoidCallback? onLibraryReset;

  /// Caps the list; beyond this the list scrolls inside the panel instead
  /// of growing the dock.
  static const double _maxListHeight = 312;

  @override
  State<BrushPresetPanel> createState() => _BrushPresetPanelState();
}

class _BrushPresetPanelState extends State<BrushPresetPanel> {
  final ScrollController _scrollController = ScrollController();

  // View options are editor-session UI state local to the panel; they are
  // deliberately not persisted or project data. Group fold state, by
  // contrast, lives on the group entity and IS persisted — only the root
  // section, which has no entity to hold it, folds locally.
  bool _showTipIcon = true;
  bool _showStrokePreview = true;
  bool _showName = true;
  bool _rootCollapsed = false;

  int get _visibleElementCount =>
      (_showTipIcon ? 1 : 0) +
      (_showStrokePreview ? 1 : 0) +
      (_showName ? 1 : 0);

  /// A checked view toggle can be unchecked only while another element
  /// stays visible; rows must never go completely blank.
  bool _canToggleOff(bool currentlyVisible) {
    return !currentlyVisible || _visibleElementCount > 1;
  }

  /// The group a preset displays under, treating an id no group carries as
  /// "root" so a stale reference can never hide a preset entirely.
  BrushGroupId? _ownerGroupId(BrushPreset preset) {
    final groupId = preset.groupId;
    if (groupId == null) {
      return null;
    }
    return widget.groups.any((group) => group.id == groupId) ? groupId : null;
  }

  /// The group that owns an ENTRY: a header owns its own group, a row owns
  /// its preset's. `null` is the root section.
  BrushGroupId? _entryGroupId(_ListEntry entry) =>
      entry.isHeader ? entry.group?.id : _ownerGroupId(entry.preset!);

  /// Flattens the library into header + row entries. Groups come first in
  /// their own order, then the root section; when there are no groups the
  /// headers are omitted entirely (a lone "Default" header is noise).
  List<_ListEntry> _buildEntries() {
    if (widget.groups.isEmpty) {
      return [for (final preset in widget.presets) _ListEntry.preset(preset)];
    }
    final entries = <_ListEntry>[];
    for (final group in widget.groups) {
      entries.add(_ListEntry.header(group));
      if (!group.collapsed) {
        for (final preset in widget.presets) {
          if (_ownerGroupId(preset) == group.id) {
            entries.add(_ListEntry.preset(preset));
          }
        }
      }
    }
    final rootPresets = [
      for (final preset in widget.presets)
        if (_ownerGroupId(preset) == null) preset,
    ];
    if (rootPresets.isNotEmpty) {
      entries.add(const _ListEntry.header(null));
      if (!_rootCollapsed) {
        for (final preset in rootPresets) {
          entries.add(_ListEntry.preset(preset));
        }
      }
    }
    return entries;
  }

  void _onMenuSelected(_BrushPresetMenuAction action) {
    switch (action) {
      case _BrushPresetMenuAction.toggleIcon:
        setState(() => _showTipIcon = !_showTipIcon);
      case _BrushPresetMenuAction.toggleStroke:
        setState(() => _showStrokePreview = !_showStrokePreview);
      case _BrushPresetMenuAction.toggleName:
        setState(() => _showName = !_showName);
      case _BrushPresetMenuAction.newGroup:
        _createGroup();
      case _BrushPresetMenuAction.rename:
        _renameSelectedPreset();
      case _BrushPresetMenuAction.delete:
        final selectedId = widget.selectedPresetId;
        if (selectedId != null) {
          widget.onPresetDeleted!(selectedId);
        }
      case _BrushPresetMenuAction.reset:
        _resetLibrary();
    }
  }

  Future<void> _createGroup() async {
    final onCreated = widget.onGroupCreated;
    if (onCreated == null) {
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _BrushNameDialog(
        keyPrefix: 'brush-preset-group-new',
        title: 'New brush group',
        titleIcon: Icons.create_new_folder_outlined,
        fieldLabel: 'Group name',
        initialName: 'New Group',
        confirmLabel: 'Create',
        emptyError: 'Group name cannot be empty.',
      ),
    );
    if (!mounted || name == null) {
      return;
    }
    onCreated(name);
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
      builder: (context) => _BrushNameDialog(
        keyPrefix: 'brush-preset-rename',
        title: 'Rename brush',
        titleIcon: Icons.drive_file_rename_outline,
        fieldLabel: 'Brush name',
        initialName: selected!.name,
        confirmLabel: 'Rename',
        emptyError: 'Brush name cannot be empty.',
      ),
    );
    if (!mounted || nextName == null) {
      return;
    }
    onRenamed(selectedId, nextName);
  }

  Future<void> _renameGroup(BrushGroup group) async {
    final onRenamed = widget.onGroupRenamed;
    if (onRenamed == null) {
      return;
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => _BrushNameDialog(
        keyPrefix: 'brush-preset-group-rename',
        title: 'Rename group',
        titleIcon: Icons.drive_file_rename_outline,
        fieldLabel: 'Group name',
        initialName: group.name,
        confirmLabel: 'Rename',
        emptyError: 'Group name cannot be empty.',
      ),
    );
    if (!mounted || nextName == null) {
      return;
    }
    onRenamed(group.id, nextName);
  }

  Future<void> _deleteGroup(BrushGroup group) async {
    final onDeleted = widget.onGroupDeleted;
    if (onDeleted == null) {
      return;
    }
    final memberCount = widget.presets
        .where((preset) => _ownerGroupId(preset) == group.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('brush-preset-group-delete-dialog'),
        title: 'Delete group',
        titleIcon: Icons.delete_outline,
        message: memberCount == 0
            ? 'Delete the empty group "${group.name}"?'
            : 'Delete "${group.name}" and the $memberCount '
                  '${memberCount == 1 ? 'brush' : 'brushes'} inside it?',
        actions: [
          AppWindowAction(
            label: 'Cancel',
            actionKey: const ValueKey<String>(
              'brush-preset-group-delete-cancel-button',
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: 'Delete',
            actionKey: const ValueKey<String>(
              'brush-preset-group-delete-confirm-button',
            ),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    onDeleted(group.id);
  }

  Future<void> _resetLibrary() async {
    final onReset = widget.onLibraryReset;
    if (onReset == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('brush-preset-reset-dialog'),
        title: 'Reset brush library',
        titleIcon: Icons.restart_alt,
        message:
            'Replace the whole library — every group, imported pack and '
            'saved brush — with the built-in brushes?',
        actions: [
          AppWindowAction(
            label: 'Cancel',
            actionKey: const ValueKey<String>(
              'brush-preset-reset-cancel-button',
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: 'Reset',
            actionKey: const ValueKey<String>(
              'brush-preset-reset-confirm-button',
            ),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    onReset();
  }

  void _toggleGroupCollapsed(BrushGroup? group) {
    if (group == null) {
      setState(() => _rootCollapsed = !_rootCollapsed);
      return;
    }
    widget.onGroupCollapseChanged?.call(group.id, !group.collapsed);
  }

  /// Maps a drag in the flattened entry list onto the library move. Dragging
  /// a ROW moves a preset (the entry before the drop decides its group and
  /// anchor); dragging a HEADER moves the whole group. [newIndex] is already
  /// adjusted for the removed item (onReorderItem semantics).
  void _handleReorder(List<_ListEntry> entries, int oldIndex, int newIndex) {
    if (oldIndex >= entries.length) {
      return;
    }
    final entry = entries[oldIndex];
    final without = [...entries]..removeAt(oldIndex);
    final clampedIndex = newIndex.clamp(0, without.length);
    if (entry.isHeader) {
      _moveGroup(entry.group, without, clampedIndex);
      return;
    }
    _movePreset(entry.preset!, without, clampedIndex);
  }

  /// Reorders groups: the moved group lands before the first group that
  /// still sits at or after the drop position. The moved group's own members
  /// stay in the flattened list while its header is dragged, so they are
  /// skipped; the root section owns no group, so dropping into it appends.
  void _moveGroup(BrushGroup? moved, List<_ListEntry> without, int dropIndex) {
    final onReordered = widget.onGroupsReordered;
    if (moved == null || onReordered == null) {
      return;
    }
    BrushGroupId? anchor;
    for (var index = dropIndex; index < without.length; index += 1) {
      final owner = _entryGroupId(without[index]);
      if (owner != null && owner != moved.id) {
        anchor = owner;
        break;
      }
    }
    onReordered(
      moveBrushGroupInLibrary(
        groups: widget.groups,
        movedId: moved.id,
        insertBeforeId: anchor,
      ),
    );
  }

  void _movePreset(BrushPreset moved, List<_ListEntry> without, int dropIndex) {
    final onReordered = widget.onPresetsReordered;
    if (onReordered == null) {
      return;
    }
    final previous = dropIndex > 0 ? without[dropIndex - 1] : null;
    final next = dropIndex < without.length ? without[dropIndex] : null;

    BrushGroupId? targetGroupId;
    BrushPresetId? insertBeforeId;
    if (previous == null) {
      if (next == null) {
        return;
      }
      // Dropped at the very top: join whatever comes first.
      targetGroupId = _entryGroupId(next);
      insertBeforeId = next.isHeader
          ? _firstMemberId(targetGroupId, excluding: moved.id)
          : next.preset!.id;
    } else if (!previous.isHeader) {
      // Right after another preset: same group, before the next member of
      // that group (or appended when the group ends here).
      targetGroupId = _ownerGroupId(previous.preset!);
      final nextPreset = next?.preset;
      insertBeforeId =
          (nextPreset != null && _ownerGroupId(nextPreset) == targetGroupId)
          ? nextPreset.id
          : null;
    } else {
      // Right under a header: become the group's first member (works for
      // collapsed groups too — members need not be visible).
      targetGroupId = previous.group?.id;
      insertBeforeId = _firstMemberId(targetGroupId, excluding: moved.id);
    }

    onReordered(
      moveBrushPresetInLibrary(
        presets: widget.presets,
        movedId: moved.id,
        targetGroupId: targetGroupId,
        insertBeforeId: insertBeforeId,
      ),
    );
  }

  BrushPresetId? _firstMemberId(
    BrushGroupId? groupId, {
    BrushPresetId? excluding,
  }) {
    for (final preset in widget.presets) {
      if (_ownerGroupId(preset) == groupId && preset.id != excluding) {
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

  List<PopupMenuEntry<_BrushPresetMenuAction>> _menuItems() {
    final actions = <PopupMenuEntry<_BrushPresetMenuAction>>[
      if (widget.onGroupCreated != null)
        const PopupMenuItem<_BrushPresetMenuAction>(
          key: ValueKey<String>('brush-preset-menu-new-group'),
          value: _BrushPresetMenuAction.newGroup,
          height: 34,
          child: Text('New group'),
        ),
      if (widget.onPresetRenamed != null)
        PopupMenuItem<_BrushPresetMenuAction>(
          key: const ValueKey<String>('brush-preset-menu-rename'),
          value: _BrushPresetMenuAction.rename,
          height: 34,
          enabled: widget.selectedPresetId != null,
          child: const Text('Rename selected brush'),
        ),
      if (widget.onPresetDeleted != null)
        PopupMenuItem<_BrushPresetMenuAction>(
          key: const ValueKey<String>('brush-preset-menu-delete'),
          value: _BrushPresetMenuAction.delete,
          height: 34,
          enabled: widget.selectedPresetId != null,
          child: const Text('Delete selected brush'),
        ),
      if (widget.onLibraryReset != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem<_BrushPresetMenuAction>(
          key: ValueKey<String>('brush-preset-menu-reset'),
          value: _BrushPresetMenuAction.reset,
          height: 34,
          child: Text('Reset brush library'),
        ),
      ],
    ];
    return [
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
      if (actions.isNotEmpty) const PopupMenuDivider(),
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = _buildEntries();
    final reorderable = widget.onPresetsReordered != null;
    final groupsReorderable = widget.onGroupsReordered != null;
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
            itemBuilder: (context) => _menuItems(),
          ),
        ],
      ),
      child: entries.isEmpty
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
                      final group = entry.group;
                      final header = _BrushGroupHeader(
                        keyValue:
                            'brush-preset-group-${group?.id.value ?? 'root'}',
                        label: group?.name ?? _rootSectionLabel,
                        collapsed: group?.collapsed ?? _rootCollapsed,
                        onToggle: () => _toggleGroupCollapsed(group),
                        onRename: group == null || widget.onGroupRenamed == null
                            ? null
                            : () => _renameGroup(group),
                        onDelete: group == null || widget.onGroupDeleted == null
                            ? null
                            : () => _deleteGroup(group),
                      );
                      return KeyedSubtree(
                        key: ValueKey<String>(
                          'brush-preset-entry-header-'
                          '${group?.id.value ?? 'root'}',
                        ),
                        // The root section has no entity and always sorts
                        // last, so only real group headers drag.
                        child: groupsReorderable && group != null
                            ? ReorderableDragStartListener(
                                index: index,
                                child: header,
                              )
                            : header,
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

/// A flat collapsible group header (chevron + name), Clip-Studio-like, with
/// the group's own rename/delete menu when those are wired.
class _BrushGroupHeader extends StatelessWidget {
  const _BrushGroupHeader({
    required this.keyValue,
    required this.label,
    required this.collapsed,
    required this.onToggle,
    this.onRename,
    this.onDelete,
  });

  final String keyValue;
  final String label;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMenu = onRename != null || onDelete != null;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey<String>(keyValue),
              onTap: onToggle,
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
          ),
          if (hasMenu)
            PopupMenuButton<_BrushGroupMenuAction>(
              key: ValueKey<String>('$keyValue-menu'),
              tooltip: 'Group options',
              popUpAnimationStyle: instantMenuAnimation,
              icon: Icon(
                Icons.more_horiz,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              iconSize: 14,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelected: (action) {
                switch (action) {
                  case _BrushGroupMenuAction.rename:
                    onRename!();
                  case _BrushGroupMenuAction.delete:
                    onDelete!();
                }
              },
              itemBuilder: (context) => [
                if (onRename != null)
                  const PopupMenuItem<_BrushGroupMenuAction>(
                    key: ValueKey<String>('brush-preset-group-menu-rename'),
                    value: _BrushGroupMenuAction.rename,
                    height: 34,
                    child: Text('Rename group'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem<_BrushGroupMenuAction>(
                    key: ValueKey<String>('brush-preset-group-menu-delete'),
                    value: _BrushGroupMenuAction.delete,
                    height: 34,
                    child: Text('Delete group'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The one name-entry window the panel's three naming flows share (preset
/// rename, group rename, new group); [keyPrefix] names its widget keys.
class _BrushNameDialog extends StatelessWidget {
  const _BrushNameDialog({
    required this.keyPrefix,
    required this.title,
    required this.titleIcon,
    required this.fieldLabel,
    required this.initialName,
    required this.confirmLabel,
    required this.emptyError,
  });

  final String keyPrefix;
  final String title;
  final IconData titleIcon;
  final String fieldLabel;
  final String initialName;
  final String confirmLabel;
  final String emptyError;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: ValueKey<String>('$keyPrefix-dialog'),
      title: title,
      titleIcon: titleIcon,
      fieldLabel: fieldLabel,
      initialValue: initialName,
      confirmLabel: confirmLabel,
      emptyError: emptyError,
      fieldKey: ValueKey<String>('$keyPrefix-text-field'),
      cancelKey: ValueKey<String>('$keyPrefix-cancel-button'),
      confirmKey: ValueKey<String>('$keyPrefix-ok-button'),
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
