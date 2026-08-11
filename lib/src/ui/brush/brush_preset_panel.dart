import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_icon.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../panels/editor_panel_frame.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_window.dart';
import '../widgets/instant_tap_region.dart';
import '../widgets/panel_flyout.dart';
import 'brush_preset_reorder.dart';
import 'brush_stroke_preview.dart';
import 'brush_tip_preview.dart';
import '../text/app_strings.dart';

/// Which row elements the brush list shows (every combination except
/// all-hidden is allowed — the options menu disables the last visible one),
/// plus the library-wide actions.
enum _BrushPresetMenuAction {
  toggleIcon,
  toggleStroke,
  toggleName,
  toggleRailIcon,
  toggleRailName,
  newGroup,
  renameGroup,
  deleteGroup,
  rename,
  delete,
  reset,
}

// ⛔The per-tab ⋯ menu is gone (유저, R4 #10: 그 시스템 삭제. 그냥 심플하게
// 그룹 버튼 하나만. 대신 그 패널의 ⋯쪽 설정에 기존 기능인 현재 브러시그룹
// 삭제/리네임 추가). Its verbs live in the panel's own options menu now and
// act on the OPEN group — see `_menuItems`.
//
// ⚠️It was NOT the cause of R4 #11. Dropping it was tried as a fix first and
// measured: the rail still went red. The crash is a live tooltip being
// re-parented, and it is fixed separately in `_dismissTooltipsOnPress`.

/// Label for the root section holding presets that belong to no group.
const String _rootSectionLabel = 'Default';

/// The brush library panel: a rail of group TABS down the left, and the open
/// group's brushes beside it — one row per preset with a tip icon, a stroke
/// preview and the name, each hideable from the options menu.
///
/// Groups used to be headers inside the list, which meant every group cost
/// the brushes a row. A rail costs them no height at all, and it is what
/// scales here: a 260px panel fits about three tabs across the top but a
/// dozen down the side.
///
/// Rail and list are SIBLINGS, each scrolling itself. Neither is nested in
/// the other and the panel opts out of the frame's own scrolling, so with
/// scrollbars always visible there is never a question of which one the
/// wheel is driving — and the tabs stay put however far the list is
/// scrolled.
///
/// Tapping a row applies its preset; dragging one reorders it within the
/// open group. Dragging one ONTO a tab and holding opens that tab, so it can
/// be dropped anywhere inside — a tab that only accepted a drop would lose
/// the ordering.
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
    this.onGroupEdited,
    this.onGroupDeleted,
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

  /// Saves a group's name AND face together — the rail's double tap and
  /// the tab menu both land here.
  final void Function(BrushGroupId id, String name, BrushGroupIcon? icon)?
  onGroupEdited;

  /// Deletes the group AND every preset inside it (the panel confirms first,
  /// naming the count).
  final ValueChanged<BrushGroupId>? onGroupDeleted;

  /// Called with the full reordered group list after a tab drag.
  final ValueChanged<List<BrushGroup>>? onGroupsReordered;

  /// Throws the library away and re-seeds the built-ins (confirmed first).
  final VoidCallback? onLibraryReset;

  /// List height when the panel is laid out somewhere with no height of its
  /// own — a widget test pumping it inside a scroll view. Docked, the
  /// section's height wins and the list takes all of it.
  static const double _fallbackListHeight = 312;

  @override
  State<BrushPresetPanel> createState() => _BrushPresetPanelState();
}

class _BrushPresetPanelState extends State<BrushPresetPanel> {
  final ScrollController _scrollController = ScrollController();

  /// The rail's own scroller. Rail and list are SIBLINGS, each scrolling
  /// itself: neither is nested in the other, so there is never a question of
  /// which one the wheel is driving, and the tabs stay put however far the
  /// brush list is scrolled.
  final ScrollController _railController = ScrollController();

  /// Locates the rail for the pointer arithmetic that springs tabs open.
  /// Per-STATE, not a library global: two panels can be on screen at once,
  /// and a shared GlobalKey would have them fighting over one element.
  final GlobalKey _railKey = GlobalKey();

  // View options are editor-session UI state local to the panel; they are
  // deliberately not persisted or project data. The open TAB is the same
  // kind of thing — on a fresh launch it follows the selected brush, which
  // is a better answer than whatever was open last time.
  bool _showTipIcon = true;
  bool _showStrokePreview = true;
  bool _showName = true;

  /// The open tab; `null` is the root section (presets in no group). Unset
  /// until the user picks one, so the panel can follow the selection.
  BrushGroupId? _activeGroupId;
  bool _tabChosen = false;

  /// A preset is mid-drag: the rail watches the pointer so hovering a tab
  /// opens it, the way a spring-loaded folder does.
  bool _dragging = false;

  /// True while a rail tab is being dragged.
  ///
  /// A `Tooltip` is an `OverlayPortal`, and reordering re-parents items
  /// through the inactive list by global key. If autoscroll brings one back
  /// while the panel's `LayoutBuilder` is mid-layout, the portal tries to
  /// add itself to the overlay right then and trips
  /// "a _RenderLayoutBuilder was mutated in performLayout" — which takes the
  /// whole rail red. Dropping the tooltips for the duration of a drag leaves
  /// nothing in the item that reaches for the overlay.
  ///
  /// 🚨유저, R4 #11: 브러시그룹을 드래그로 옮기면 2번째 버튼부터 끝까지
  /// 빨간 에러 뜨고 콘솔에 무한 에러.
  ///
  /// ★This flag was only ever HALF the guard, and the missing half is
  /// [_dismissTooltips]. It stops a tooltip from being BORN during a drag;
  /// it does nothing about one that was ALREADY UP when the drag started —
  /// which is the common case, because the hand that drags a tab has been
  /// resting on it. That live overlay entry is what gets re-parented
  /// mid-layout. Measured, not reasoned: dropping the ⋯ menu did not fix
  /// it, and neither did keeping the tooltip widget mounted; only having no
  /// LIVE tooltip at drag start did.
  bool _railDragging = false;

  /// Wraps a reorderable item so PRESSING it takes any open tooltip down.
  ///
  /// ⚠️Pointer DOWN, not `onReorderStart`. Measured: dismissing from
  /// `onReorderStart` only changes which form of the assert fires — by then
  /// the list is already inside the machinery that re-parents items, and
  /// removing an overlay entry there is itself the illegal mutation. Pointer
  /// down is a plain gesture callback with no layout in flight, and it is
  /// also simply when a tooltip should go: the hand has stopped hovering and
  /// started doing.
  ///
  /// A `Listener` consumes nothing, so the drag recogniser underneath is
  /// untouched.
  Widget _dismissTooltipsOnPress(Widget child) => Listener(
    onPointerDown: (_) => Tooltip.dismissAllToolTips(),
    child: child,
  );
  BrushGroupId? _springTarget;
  bool _springTargetIsRoot = false;
  Timer? _springTimer;

  int get _visibleElementCount =>
      (_showTipIcon ? 1 : 0) +
      (_showStrokePreview ? 1 : 0) +
      (_showName ? 1 : 0);

  /// A checked view toggle can be unchecked only while another element
  /// stays visible; rows must never go completely blank.
  bool _canToggleOff(bool currentlyVisible) {
    return !currentlyVisible || _visibleElementCount > 1;
  }

  /// The rail's own two, on the same rule: a tab must show something.
  ///
  /// These are view preferences, not library data — a brush library handed
  /// to someone else must not carry how you like your rail. They belong
  /// with panel layout and shortcuts in the workspace file, and go there
  /// when that lands; until then they live for the session like the three
  /// row toggles above.
  bool _railShowIcon = true;
  bool _railShowName = false;

  bool _canToggleOffRail(bool currentlyVisible) {
    return !currentlyVisible ||
        (_railShowIcon ? 1 : 0) + (_railShowName ? 1 : 0) > 1;
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

  /// Whether the root section gets a tab: only when something is actually
  /// in it. A library whose brushes are all filed shows no leftovers tab.
  bool get _hasRootTab =>
      widget.presets.any((preset) => _ownerGroupId(preset) == null);

  /// The group the rail is standing in, or null for the ROOT section.
  ///
  /// The panel's group verbs act on this — the tab you are looking at is the
  /// group you mean (유저, R4 #10). Root is not a group, so they stand down
  /// there rather than pretending.
  BrushGroup? get _openGroup {
    final id = _openGroupId;
    if (id == null) {
      return null;
    }
    for (final group in widget.groups) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  /// The rail's tabs, in order: the groups as the library lists them, then
  /// the root section last — folders first, loose items after, the way a
  /// file tree reads.
  ///
  /// A library with no groups shows NO rail: a lone "Default" tab would be a
  /// control with nothing to choose between, taking width from the brushes.
  List<BrushGroup?> get _tabs => widget.groups.isEmpty
      ? const <BrushGroup?>[]
      : [...widget.groups, if (_hasRootTab) null];

  /// The open tab. Until the user picks one this follows the SELECTED brush,
  /// so opening the panel lands on the group you are painting from.
  BrushGroupId? get _openGroupId {
    if (_tabChosen) {
      return _activeGroupId;
    }
    final selectedId = widget.selectedPresetId;
    if (selectedId != null) {
      for (final preset in widget.presets) {
        if (preset.id == selectedId) {
          return _ownerGroupId(preset);
        }
      }
    }
    return widget.groups.isEmpty ? null : widget.groups.first.id;
  }

  /// The presets on screen: one tab's worth.
  List<BrushPreset> get _visiblePresets {
    final open = _openGroupId;
    return [
      for (final preset in widget.presets)
        if (_ownerGroupId(preset) == open) preset,
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
      case _BrushPresetMenuAction.toggleRailIcon:
        setState(() => _railShowIcon = !_railShowIcon);
      case _BrushPresetMenuAction.toggleRailName:
        setState(() => _railShowName = !_railShowName);
      case _BrushPresetMenuAction.newGroup:
        _createGroup();
      case _BrushPresetMenuAction.renameGroup:
        final group = _openGroup;
        if (group != null) {
          _editGroup(group);
        }
      case _BrushPresetMenuAction.deleteGroup:
        final group = _openGroup;
        if (group != null) {
          _deleteGroup(group);
        }
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

  /// The group's name and face, edited together.
  ///
  /// One editor with two ways in — a double tap on the tab, and the tab's
  /// own menu — rather than a rename dialog and an icon dialog in a row.
  Future<void> _editGroup(BrushGroup group) async {
    final onEdited = widget.onGroupEdited;
    if (onEdited == null) {
      return;
    }
    var icon = group.icon;
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => _BrushNameDialog(
          keyPrefix: 'brush-preset-group-rename',
          title: AppText.strings.brEditGroup,
          titleIcon: Icons.drive_file_rename_outline,
          fieldLabel: 'Group name',
          initialName: group.name,
          confirmLabel: 'Save',
          emptyError: 'Group name cannot be empty.',
          extra: _GroupIconPicker(
            selected: icon,
            onPicked: (picked) => setLocal(() => icon = picked),
          ),
        ),
      ),
    );
    if (!mounted || nextName == null) {
      return;
    }
    onEdited(group.id, nextName, icon);
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
        title: AppText.strings.brDeleteGroup,
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
        title: AppText.strings.brResetLibrary,
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

  void _openTab(BrushGroupId? groupId) {
    if (_tabChosen && _activeGroupId == groupId) {
      return;
    }
    setState(() {
      _tabChosen = true;
      _activeGroupId = groupId;
    });
  }

  /// Moves a group in the rail. The rail is a plain list of tabs, so a tab
  /// drag is an ordinary reorder — no headers, no members riding along.
  void _handleTabReorder(int oldIndex, int newIndex) {
    final onReordered = widget.onGroupsReordered;
    final tabs = _tabs;
    if (onReordered == null || oldIndex >= tabs.length) {
      return;
    }
    final moved = tabs[oldIndex];
    if (moved == null) {
      // The root section is not a group and always sorts last.
      return;
    }
    final clamped = newIndex.clamp(0, tabs.length - 1);
    final anchor = clamped < widget.groups.length
        ? widget.groups[clamped]
        : null;
    onReordered(
      moveBrushGroupInLibrary(
        groups: widget.groups,
        movedId: moved.id,
        insertBeforeId: anchor?.id == moved.id ? null : anchor?.id,
      ),
    );
  }

  /// Reorders inside the open tab. One tab shows one group, so a row drag
  /// can only ever be a move WITHIN it — crossing groups is what the
  /// spring-loaded tabs are for.
  void _handleReorder(List<BrushPreset> visible, int oldIndex, int newIndex) {
    final onReordered = widget.onPresetsReordered;
    if (onReordered == null || oldIndex >= visible.length) {
      return;
    }
    final moved = visible[oldIndex];
    final without = [...visible]..removeAt(oldIndex);
    final clamped = newIndex.clamp(0, without.length);
    onReordered(
      moveBrushPresetInLibrary(
        presets: widget.presets,
        movedId: moved.id,
        targetGroupId: _openGroupId,
        insertBeforeId: clamped < without.length ? without[clamped].id : null,
      ),
    );
  }

  /// Opens whichever tab the dragged brush is hovering, after a beat.
  ///
  /// A reorder drag is not a [Draggable], so the tabs cannot be drop targets
  /// — the pointer keeps reporting to the row that was picked up. The rail
  /// therefore reads the pointer itself: tabs are a fixed height, so the
  /// offset alone says which one is under it.
  void _updateSpringTarget(Offset globalPosition) {
    if (!_dragging) {
      return;
    }
    final box = _railKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final local = box.globalToLocal(globalPosition);
    final tabs = _tabs;
    if (!box.size.contains(local)) {
      _cancelSpring();
      return;
    }
    final offset =
        local.dy + (_railController.hasClients ? _railController.offset : 0.0);
    final index = offset ~/ _BrushGroupTab.extent;
    if (index < 0 || index >= tabs.length) {
      _cancelSpring();
      return;
    }
    final target = tabs[index];
    final isRoot = target == null;
    if (_springTimer != null &&
        _springTarget == target?.id &&
        _springTargetIsRoot == isRoot) {
      return;
    }
    _springTimer?.cancel();
    _springTarget = target?.id;
    _springTargetIsRoot = isRoot;
    // Long enough that dragging ACROSS the rail does not flip through every
    // tab on the way, short enough to feel like an invitation.
    _springTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _dragging) {
        _openTab(_springTarget);
      }
    });
  }

  void _cancelSpring() {
    _springTimer?.cancel();
    _springTimer = null;
    _springTarget = null;
    _springTargetIsRoot = false;
  }

  @override
  void dispose() {
    _springTimer?.cancel();
    _railController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The options menu, in the app's shared flyout vocabulary (R6 #4).
  ///
  /// It used to build `PopupMenuItem`s by hand at `height: 34`, which is
  /// nobody's number: [showPanelFlyout] lays its rows out at 32 and every
  /// other menu in the app came from there. The toggles were
  /// `CheckedPopupMenuItem`s besides, so their check sat on the LEFT and
  /// indented five rows away from the six beside them, while the flyout's
  /// own check sits on the right.
  List<PanelFlyoutEntry> _menuItems() {
    PanelFlyoutItem item(
      String keyValue,
      String label,
      _BrushPresetMenuAction action, {
      bool enabled = true,
      bool? checked,
    }) => PanelFlyoutItem(
      keyValue: keyValue,
      label: label,
      enabled: enabled,
      checked: checked,
      onSelected: () => _onMenuSelected(action),
    );

    final actions = <PanelFlyoutEntry>[
      if (widget.onGroupCreated != null)
        item(
          'brush-preset-menu-new-group',
          AppText.strings.brNewGroup,
          _BrushPresetMenuAction.newGroup,
        ),
      // The OPEN group's own two verbs (유저, R4 #10). They used to live on
      // a ⋯ in the corner of every 26px tab, which meant every tab carried a
      // second, smaller button whose whole job was to be missed.
      //
      // Disabled on the root section, which is not a group and has no name
      // to change and nothing to delete.
      if (widget.onGroupEdited != null)
        item(
          'brush-preset-menu-rename-group',
          AppText.strings.brRenameGroup,
          _BrushPresetMenuAction.renameGroup,
          enabled: _openGroup != null,
        ),
      if (widget.onGroupDeleted != null)
        item(
          'brush-preset-menu-delete-group',
          AppText.strings.brDeleteGroup,
          _BrushPresetMenuAction.deleteGroup,
          enabled: _openGroup != null,
        ),
      if (widget.onPresetRenamed != null)
        item(
          'brush-preset-menu-rename',
          AppText.strings.brRenameSelected,
          _BrushPresetMenuAction.rename,
          enabled: widget.selectedPresetId != null,
        ),
      if (widget.onPresetDeleted != null)
        item(
          'brush-preset-menu-delete',
          AppText.strings.brDeleteSelected,
          _BrushPresetMenuAction.delete,
          enabled: widget.selectedPresetId != null,
        ),
      if (widget.onLibraryReset != null) ...[
        const PanelFlyoutDivider(),
        item(
          'brush-preset-menu-reset',
          AppText.strings.brResetLibrary,
          _BrushPresetMenuAction.reset,
        ),
      ],
    ];
    return [
      item(
        'brush-preset-view-icon-toggle',
        AppText.strings.brTipIcon,
        _BrushPresetMenuAction.toggleIcon,
        checked: _showTipIcon,
        enabled: _canToggleOff(_showTipIcon),
      ),
      item(
        'brush-preset-view-stroke-toggle',
        AppText.strings.brStrokePreview,
        _BrushPresetMenuAction.toggleStroke,
        checked: _showStrokePreview,
        enabled: _canToggleOff(_showStrokePreview),
      ),
      item(
        'brush-preset-view-name-toggle',
        'Name',
        _BrushPresetMenuAction.toggleName,
        checked: _showName,
        enabled: _canToggleOff(_showName),
      ),
      const PanelFlyoutDivider(),
      item(
        'brush-preset-rail-icon-toggle',
        AppText.strings.brFolderIcon,
        _BrushPresetMenuAction.toggleRailIcon,
        checked: _railShowIcon,
        enabled: _canToggleOffRail(_railShowIcon),
      ),
      item(
        'brush-preset-rail-name-toggle',
        AppText.strings.brFolderName,
        _BrushPresetMenuAction.toggleRailName,
        checked: _railShowName,
        enabled: _canToggleOffRail(_railShowName),
      ),
      if (actions.isNotEmpty) const PanelFlyoutDivider(),
      ...actions,
    ];
  }

  /// The tab rail: a list of groups down the left edge.
  ///
  /// It costs the brush list no HEIGHT at all, which is the point — adding
  /// a group used to take a row away from the brushes. A 260px panel fits
  /// about three tabs across the top but a dozen down the side, so in this
  /// panel's proportions the rail is also what scales.
  Widget _buildRail() {
    final tabs = _tabs;
    final open = _openGroupId;
    final reorderable = widget.onGroupsReordered != null;
    return SizedBox(
      key: _railKey,
      // The tab's own width, nothing added: the rail's scrollbar is laid
      // over the tabs and only while they overflow, so the rail no longer
      // pays a lane's width for a bar that is usually not there.
      width: _railShowName ? _BrushGroupTab.namedWidth : _BrushGroupTab.extent,
      // The bar comes from `AppScrollBehavior` now — same widget, same
      // rules — so asking for one here would only be a second.
      child: ReorderableListView.builder(
        key: const ValueKey<String>('brush-preset-tab-rail'),
        scrollController: _railController,
        buildDefaultDragHandles: false,
        itemCount: tabs.length,
        onReorderStart: (_) => setState(() => _railDragging = true),
        onReorderEnd: (_) => setState(() => _railDragging = false),
        onReorderItem: _handleTabReorder,
        itemBuilder: (context, index) {
          final group = tabs[index];
          final tab = _BrushGroupTab(
            keyValue: 'brush-preset-tab-${group?.id.value ?? 'root'}',
            label: group?.name ?? _rootSectionLabel,
            icon: group?.icon,
            showIcon: _railShowIcon,
            showName: _railShowName,
            showTooltip: !_railDragging,
            onEdit: group == null || widget.onGroupEdited == null
                ? null
                : () => _editGroup(group),
            // The tab wears its group's first brush, so a chalk group
            // looks chalky and no one has to pick an icon.
            preview: _firstPresetIn(group?.id),
            selected: group?.id == open,
            onTap: () => _openTab(group?.id),
          );
          return KeyedSubtree(
            key: ValueKey<String>(
              'brush-preset-tab-entry-${group?.id.value ?? 'root'}',
            ),
            // The root section is not a group and always sorts last, so
            // only real tabs drag.
            child: reorderable && group != null
                ? _dismissTooltipsOnPress(
                    ReorderableDragStartListener(index: index, child: tab),
                  )
                : tab,
          );
        },
      ),
    );
  }

  /// The open tab's brushes.
  Widget _buildList(List<BrushPreset> visible, bool reorderable) {
    // Same as the rail above: the app's behaviour is the only bar.
    return ReorderableListView.builder(
      key: const ValueKey<String>('brush-preset-list'),
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorderStart: (_) => _dragging = true,
      onReorderEnd: (_) {
        _dragging = false;
        _cancelSpring();
      },
      onReorderItem: (oldIndex, newIndex) =>
          _handleReorder(visible, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final preset = visible[index];
        final row = _BrushPresetRow(
          preset: preset,
          selected: preset.id == widget.selectedPresetId,
          onApplied: widget.onPresetApplied,
          showTipIcon: _showTipIcon,
          showStrokePreview: _showStrokePreview,
          showName: _showName,
        );
        return KeyedSubtree(
          key: ValueKey<String>('brush-preset-entry-${preset.id.value}'),
          // The rows carry tooltips too, and a row drag re-parents them
          // exactly the same way (유저, R4 #11 — same defect, other list).
          child: reorderable
              ? _dismissTooltipsOnPress(
                  ReorderableDragStartListener(index: index, child: row),
                )
              : row,
        );
      },
    );
  }

  BrushPreset? _firstPresetIn(BrushGroupId? groupId) {
    for (final preset in widget.presets) {
      if (_ownerGroupId(preset) == groupId) {
        return preset;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visible = _visiblePresets;
    final reorderable = widget.onPresetsReordered != null;
    return Listener(
      // Watches the pointer only to spring the tabs open: a reorder drag
      // reports to the row it picked up, never to what is under it now.
      behavior: HitTestBehavior.translucent,
      onPointerMove: (event) => _updateSpringTarget(event.position),
      onPointerUp: (_) => _cancelSpring(),
      child: _buildFrame(context, colorScheme, visible, reorderable),
    );
  }

  Widget _buildFrame(
    BuildContext context,
    ColorScheme colorScheme,
    List<BrushPreset> visible,
    bool reorderable,
  ) {
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
              tooltip: AppText.strings.brImportBrushes,
              onPressed: widget.onPresetImportRequested,
            ),
          if (widget.onPresetSaveRequested != null)
            IconButton(
              key: const ValueKey<String>('brush-preset-save-button'),
              // 「＋가 있는 모든 곳, 공통적으로」 — the glyph, not the button.
              icon: Icon(
                Icons.add,
                size: 16,
                color: AppColors.addGlyph(
                  enabled: widget.onPresetSaveRequested != null,
                ),
              ),
              visualDensity: VisualDensity.compact,
              tooltip: AppText.strings.brSaveAsPreset,
              onPressed: widget.onPresetSaveRequested,
            ),
          PanelFlyoutTrigger(
            key: const ValueKey<String>('brush-preset-menu-button'),
            tooltip: AppText.strings.brBrushOptions,
            entriesBuilder: _menuItems,
            child: const Icon(Icons.more_vert, size: 16),
          ),
        ],
      ),
      // The panel owns its scrolling — two of them, side by side — so the
      // frame must not wrap it in a third.
      bodyScrolls: false,
      child: widget.presets.isEmpty && widget.groups.isEmpty
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
          : LayoutBuilder(
              builder: (context, constraints) {
                // Docked, the section hands down a real height and the list
                // takes all of it. Somewhere unbounded — a panel pumped
                // inside a scroll view — it falls back to a fixed extent
                // rather than trying to be infinitely tall.
                final height = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : BrushPresetPanel._fallbackListHeight;
                return SizedBox(
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_tabs.isNotEmpty) _buildRail(),
                      Expanded(child: _buildList(visible, reorderable)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// One tab in the rail: the group's first brush as its face, its name as the
/// tooltip, and its own rename/delete menu behind a long press.
///
/// A rotated label was the obvious alternative and a bad one — Korean and
/// Japanese group names do not read sideways. The brush the group starts
/// with says more anyway.
class _BrushGroupTab extends StatelessWidget {
  const _BrushGroupTab({
    required this.keyValue,
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
    this.icon,
    this.showIcon = true,
    this.showName = false,
    this.showTooltip = true,
    this.onEdit,
  });

  /// Height of one tab. Fixed, because the rail turns a pointer offset into
  /// a tab index while a brush is being dragged over it.
  static const double extent = 26;

  /// Rail width once names are showing. Wide enough for a short group name
  /// beside the icon without taking the brush list below a usable width.
  static const double namedWidth = 96;

  /// The tab's picture: the group's chosen icon, else its first brush, else
  /// a plain folder. Choosing is for when that guess reads wrong.
  Widget _face(ColorScheme colorScheme) {
    if (icon != null) {
      return Icon(icon!.data, size: 13, color: colorScheme.onSurfaceVariant);
    }
    if (preview != null) {
      return BrushTipPreview(settings: preview!.settings);
    }
    return Icon(
      Icons.folder_outlined,
      size: 13,
      color: colorScheme.onSurfaceVariant,
    );
  }

  final String keyValue;
  final String label;

  /// The group's first brush, or null for an empty group.
  final BrushPreset? preview;
  final bool selected;
  final VoidCallback onTap;

  /// The group's chosen face, or null to fall back to its first brush.
  final BrushGroupIcon? icon;

  /// The rail's view toggles; at least one is always on.
  final bool showIcon;
  final bool showName;

  /// False while the rail is being reordered — see `_railDragging`.
  final bool showTooltip;

  /// Opens the group's name/icon editor — a double tap, which cannot
  /// collide with the single tap that switches group.
  ///
  /// R10: and no longer DELAYS it either. Registering it used to put the
  /// group switch behind the double-tap window, so picking a group took
  /// ~300ms to show — see [InstantTapRegion].
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = Material(
      color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: ValueKey<String>(keyValue),
        // The switch rides the raw pointer (R10) — see the wrapper below.
        // The InkWell keeps a no-op tap so its ripple and its semantics
        // stay, the same shape the timeline cells use.
        onTap: () {},
        onDoubleTap: onEdit,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // No fixed width: the selected tab's border is thicker, so a
              // hard-sized box overflows it by a pixel.
              if (showIcon)
                showName
                    ? SizedBox(width: 20, child: _face(colorScheme))
                    : Expanded(child: _face(colorScheme)),
              if (showName)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: showIcon ? 0 : 5, right: 3),
                    child: Text(
                      label,
                      maxLines: 1,
                      // Group names run long — a pack keeps the file's name
                      // — so the tail is what gives.
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // R10: the group switch acts on the raw pointer, so it no longer waits
    // out `onEdit`'s double-tap window. Touch still commits on the release
    // — the rail scrolls, and a press that becomes a scroll must not
    // switch groups under the finger.
    final instant = InstantTapRegion(onTap: (_) => onTap(), child: body);
    final face = showTooltip
        ? Tooltip(message: label, child: instant)
        : instant;
    return SizedBox(height: extent, child: face);
  }
}

/// Picks a group's face from the fixed catalogue.
///
/// "None" is first and is the default: a tab with no icon wears its first
/// brush, which usually reads better than any icon would. Choosing is for
/// when that guess is wrong.
class _GroupIconPicker extends StatelessWidget {
  const _GroupIconPicker({required this.selected, required this.onPicked});

  final BrushGroupIcon? selected;
  final ValueChanged<BrushGroupIcon?> onPicked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget cell({
      required String keyValue,
      required Widget child,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        key: ValueKey<String>(keyValue),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            // Selection reads as colour only, never a checkmark.
            color: isSelected
                ? colorScheme.surfaceContainerHigh
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        ),
      );
    }

    return AppWindowField(
      label: AppText.strings.brFolderIcon,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          cell(
            keyValue: 'brush-preset-group-icon-none',
            isSelected: selected == null,
            onTap: () => onPicked(null),
            child: Icon(
              Icons.block,
              size: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          for (final icon in BrushGroupIcon.values)
            cell(
              keyValue: 'brush-preset-group-icon-${icon.name}',
              isSelected: selected == icon,
              onTap: () => onPicked(icon),
              child: Icon(
                icon.data,
                size: 13,
                color: colorScheme.onSurfaceVariant,
              ),
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
    this.extra,
  });

  final String keyPrefix;
  final String title;
  final IconData titleIcon;
  final String fieldLabel;
  final String initialName;
  final String confirmLabel;
  final String emptyError;

  /// Content confirmed alongside the name — the group editor's icon grid.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      extra: extra,
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
