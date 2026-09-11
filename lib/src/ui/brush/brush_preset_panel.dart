import '../widgets/app_icon_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_icon.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/reorder_target.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../panels/editor_panel_frame.dart';
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../widgets/app_scrollbar_lane.dart';
import '../widgets/app_window.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/instant_tap_region.dart';
import '../widgets/panel_flyout.dart';
import 'brush_group_icon_glyph.dart';
import 'brush_preset_reorder.dart';
import 'brush_preset_reorder_grid.dart';
import 'brush_stroke_preview.dart';
import 'brush_tip_preview.dart';
import '../text/app_strings.dart';
import '../input/control_press_claim.dart';

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
  exportPreset,
  exportGroup,
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
    this.onPresetExported,
    this.onGroupExported,
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

  /// 🚨유저 (`H25-Q1`, 답 both-by-selection): 「점선 버튼통해 브러시
  /// 내보내기, 브러시 그룹 내보내기」 — one brush, or the group it sits in.
  /// Both write one `.anibrush` (`brush-export-format-Q1`, 답 1).
  final ValueChanged<BrushPresetId>? onPresetExported;
  final ValueChanged<BrushGroupId?>? onGroupExported;

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

  /// 🚨NAMES ARE ON BY DEFAULT (유저 2026-09-08: 「그룹쪽은 대신 아이콘
  /// 버튼이아니라 **아이콘+이름**으로 해서, 이름 넣을수있게 가로로 좀 더
  /// 길게해주고」).
  ///
  /// ⚠️Nothing was built for this — the named rail has existed since
  /// 2026-07-27 (`_BrushGroupTab.namedWidth`, 96px) and only ever opened
  /// closed. The toggle stays: 유저 confirmed 「토글은 그대로 남김」, so a
  /// narrow screen can still trade the names back for 70px of brush list.
  bool _railShowName = true;

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
    return id == null
        ? null
        : widget.groups.where((group) => group.id == id).firstOrNull;
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
    final selected = selectedId == null
        ? null
        : widget.presets.where((preset) => preset.id == selectedId).firstOrNull;
    if (selected != null) {
      return _ownerGroupId(selected);
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
        unawaited(_createGroup());
      case _BrushPresetMenuAction.renameGroup:
        final group = _openGroup;
        if (group != null) {
          unawaited(_editGroup(group));
        }
      case _BrushPresetMenuAction.deleteGroup:
        final group = _openGroup;
        if (group != null) {
          unawaited(_deleteGroup(group));
        }
      case _BrushPresetMenuAction.rename:
        unawaited(_renameSelectedPreset());
      case _BrushPresetMenuAction.delete:
        final selectedId = widget.selectedPresetId;
        if (selectedId != null) {
          widget.onPresetDeleted!(selectedId);
        }
      case _BrushPresetMenuAction.reset:
        unawaited(_resetLibrary());
      case _BrushPresetMenuAction.exportPreset:
        final selectedId = widget.selectedPresetId;
        if (selectedId != null) {
          widget.onPresetExported!(selectedId);
        }
      case _BrushPresetMenuAction.exportGroup:
        // ⚠️Null is the ROOT section, which is a real answer here: every
        // brush that belongs to no group is still a selection worth
        // exporting.
        widget.onGroupExported!(_openGroup?.id);
    }
  }

  Future<void> _createGroup() {
    final onCreated = widget.onGroupCreated;
    if (onCreated == null) {
      return Future<void>.value();
    }
    return askThenCommit<String>(
      context,
      dialog: (_) => AppPromptDialog.keyed(
        keyPrefix: 'brush-preset-group-new',
        title: AppText.strings.brNewGroup,
        titleIcon: Icons.create_new_folder_outlined,
        fieldLabel: AppText.strings.brGroupNameField,
        initialValue: 'New Group',
        confirmLabel: AppText.strings.brCreate,
        emptyError: AppText.strings.brGroupNameEmpty,
      ),
      commit: onCreated,
    );
  }

  Future<void> _renameSelectedPreset() {
    final selectedId = widget.selectedPresetId;
    final onRenamed = widget.onPresetRenamed;
    final selected = widget.presets
        .where((preset) => preset.id == selectedId)
        .firstOrNull;
    if (selected == null || onRenamed == null) {
      return Future<void>.value();
    }
    return askThenCommit<String>(
      context,
      dialog: (_) => AppPromptDialog.keyed(
        keyPrefix: 'brush-preset-rename',
        title: AppText.strings.brRenameBrush,
        titleIcon: Icons.drive_file_rename_outline,
        fieldLabel: AppText.strings.brBrushNameField,
        initialValue: selected.name,
        confirmLabel: AppText.strings.commonRename,
        emptyError: AppText.strings.brBrushNameEmpty,
      ),
      commit: (nextName) => onRenamed(selected.id, nextName),
    );
  }

  /// The group's name and face, edited together.
  ///
  /// One editor with two ways in — a double tap on the tab, and the tab's
  /// own menu — rather than a rename dialog and an icon dialog in a row.
  Future<void> _editGroup(BrushGroup group) {
    final onEdited = widget.onGroupEdited;
    if (onEdited == null) {
      return Future<void>.value();
    }
    var icon = group.icon;
    return askThenCommit<String>(
      context,
      dialog: (_) => StatefulBuilder(
        builder: (context, setLocal) => AppPromptDialog.keyed(
          keyPrefix: 'brush-preset-group-rename',
          title: AppText.strings.brEditGroup,
          titleIcon: Icons.drive_file_rename_outline,
          fieldLabel: AppText.strings.brGroupNameField,
          initialValue: group.name,
          confirmLabel: AppText.strings.commonSave,
          emptyError: AppText.strings.brGroupNameEmpty,
          // Content confirmed alongside the name — the group's face, so
          // the two are one edit rather than two dialogs in a row.
          extra: _GroupIconPicker(
            selected: icon,
            onPicked: (picked) => setLocal(() => icon = picked),
          ),
        ),
      ),
      commit: (nextName) => onEdited(group.id, nextName, icon),
    );
  }

  Future<void> _deleteGroup(BrushGroup group) {
    final onDeleted = widget.onGroupDeleted;
    if (onDeleted == null) {
      return Future<void>.value();
    }
    final keys = confirmDialogKeys('brush-preset-group-delete');
    final memberCount = widget.presets
        .where((preset) => _ownerGroupId(preset) == group.id)
        .length;
    return confirmThenCommit(
      context,
      dialog: (context) => confirmWindow(
        context,
        ConfirmQuestion(
          keys: keys,
          title: AppText.strings.brDeleteGroup,
          titleIcon: Icons.delete_outline,
          message: memberCount == 0
              ? 'Delete the empty group "${group.name}"?'
              : 'Delete "${group.name}" and the $memberCount '
                    '${memberCount == 1 ? 'brush' : 'brushes'} inside it?',
        ),
        accept: ConfirmChoice(AppText.strings.commonDelete),
      ),
      commit: () => onDeleted(group.id),
    );
  }

  Future<void> _resetLibrary() {
    final onReset = widget.onLibraryReset;
    if (onReset == null) {
      return Future<void>.value();
    }
    return confirmThenCommit(
      context,
      dialog: (context) => confirmWindow(
        context,
        ConfirmQuestion(
          keys: confirmDialogKeys('brush-preset-reset'),
          title: AppText.strings.brResetLibrary,
          titleIcon: Icons.restart_alt,
          message: AppText.strings.brResetLibraryBody,
        ),
        accept: ConfirmChoice(AppText.strings.commonReset),
      ),
      commit: onReset,
    );
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
    // ⚠️`onReorderItem` (not the obsolete `onReorder`) already lifted the
    // dragged tab out of the count, so this is a TARGET — see
    // [reorderAnchorAt], which is the one place that arithmetic lives.
    //
    // The root tab rides along at the end of `tabs` and is not in `groups`,
    // and it needs no translation: groups come first, so a group's index is
    // the same in both. A target past the last group is the append, which is
    // the very move 유저 could not make.
    final anchor = reorderAnchorAt(
      widget.groups,
      movedIndex: oldIndex,
      target: newIndex,
    );
    onReordered(
      moveBrushGroupInLibrary(
        groups: widget.groups,
        movedId: moved.id,
        insertBeforeId: anchor?.id,
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
    // The grid reports a TARGET too — the same law, from the same file, as
    // the rail above. It used to be spelled out here and only here, which is
    // how the rail came to have a different one.
    final anchor = reorderAnchorAt(
      visible,
      movedIndex: oldIndex,
      target: newIndex,
    );
    onReordered(
      moveBrushPresetInLibrary(
        presets: widget.presets,
        movedId: moved.id,
        targetGroupId: _openGroupId,
        insertBeforeId: anchor?.id,
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
      // 🚨유저 (`H25-Q1`): 「점선 버튼통해 브러시 내보내기, 브러시 그룹
      // 내보내기」 — the selection decides which, so both sit here rather than
      // one of them becoming a mode.
      if (widget.onPresetExported != null)
        item(
          'brush-preset-menu-export',
          AppText.strings.brExportSelected,
          _BrushPresetMenuAction.exportPreset,
          enabled: widget.selectedPresetId != null,
        ),
      if (widget.onGroupExported != null)
        item(
          'brush-preset-menu-export-group',
          AppText.strings.brExportGroup,
          _BrushPresetMenuAction.exportGroup,
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
      // The tabs' own width plus a LANE (H35, 유저 2026-09-11: 「그룹쪽이랑
      // 브러시리스트쪽 … 내용물에 공통적으로 스크롤바 넣자. 항상 보이도록」).
      // ↩️This said the opposite on purpose until then: the bar was laid
      // over the tabs and only while they overflowed, so the rail paid
      // nothing for a bar that was usually not there — and on a tablet there
      // was no bar at all.
      width:
          (_railShowName ? _BrushGroupTab.namedWidth : _BrushGroupTab.extent) +
          AppScrollbarLane.wide,
      child: ContentScrollbar(
        controller: _railController,
        builder: (context, controller) => ReorderableListView.builder(
          key: const ValueKey<String>('brush-preset-tab-rail'),
          scrollController: controller,
          buildDefaultDragHandles: false,
          itemCount: tabs.length,
          onReorderStart: (_) => setState(() => _railDragging = true),
          // 🚨★★★THE FLAG OUTLIVES THE DROP BY A FRAME (유저 2026-09-01,
          // F-60, with the recipe: 「3번째 브러시 그룹을 드래그해서 4번째랑
          // 자리바꾸기 … 커밋될때? 끝날때 빨간화면떴어」).
          //
          // ⛔Clearing it here — synchronously — put the tooltips back in the
          // SAME frame that `ReorderableListView` revives the dragged item
          // from the inactive list by global key. Flutter named the collision
          // itself:
          //
          //   A _RenderLayoutBuilder was mutated in performLayout.
          //   _RenderTheater._addDeferredChild ← _OverlayEntryLocation._activate
          //     ← _OverlayPortalElement.activate ← Element._activateRecursively
          //   error-causing widget: ReorderableListView-[brush-preset-tab-rail]
          //
          // A `Tooltip` is an `OverlayPortal`; reviving one adds a deferred
          // child to the theater, and that is illegal inside the panel's
          // `LayoutBuilder` layout callback. Everything after it in 유저's log
          // — the ink `referenceBox.attached` asserts, the semantics
          // `traversalParentIdentifier` failure, buttons vanishing on hover
          // across the whole app — is the wreckage of that one frame.
          //
          // ⚠️A post-frame callback, not a timer: the next frame is exactly
          // when the revival is over and no more than that.
          onReorderEnd: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              setState(() => _railDragging = false);
            });
          },
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
      ),
    );
  }

  /// The open tab's brushes.
  /// 🚨유저 확정 (`brush-grid-reorder-Q1`, 답 1): the list is a GRID whose
  /// cells still drag into a new order. One column is the same grid with one
  /// column, so nothing here branches on the width and there is no view
  /// where reordering quietly stops working.
  Widget _buildList(List<BrushPreset> visible, bool reorderable) {
    // 🚨H37 (유저 2026-09-11): 「이름이나 스트로크 프리뷰 없애고 팁 이미지?
    // 아이콘만 남게하면 그에 맞춰서 공간 줄이도록」 — a cell is as wide as what
    // it draws, the way the rail's tabs already are. The four-column ceiling
    // is about reading STROKES side by side, so a list of bare tips has none.
    final tipsOnly = !_showName && !_showStrokePreview;
    return BrushPresetReorderGrid(
      key: const ValueKey<String>('brush-preset-list'),
      scrollController: _scrollController,
      itemCount: visible.length,
      cellHeight: brushPresetRowHeight,
      cellTargetWidth: tipsOnly
          ? _BrushPresetRow.tipsOnlyWidth
          : brushPresetCellTargetWidth,
      maxColumns: tipsOnly ? null : brushPresetMaxColumns,
      itemKey: (index) =>
          ValueKey<String>('brush-preset-entry-${visible[index].id.value}'),
      onDragStart: () => _dragging = true,
      onDragEnd: () {
        _dragging = false;
        _cancelSpring();
      },
      onReorder: reorderable
          ? (oldIndex, newIndex) => _handleReorder(visible, oldIndex, newIndex)
          : null,
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
        // The rows carry tooltips too, and a row drag re-parents them
        // exactly the same way (유저, R4 #11 — same defect, other list).
        return reorderable ? _dismissTooltipsOnPress(row) : row;
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
      title: AppText.strings.brBrushesTitle,
      bodyPadding: const EdgeInsets.all(5),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onPresetImportRequested != null)
            AppIconButton(
              keyValue: 'brush-preset-import-button',
              tooltip: AppText.strings.brImportBrushes,
              size: AppIconButtonSize.dense,
              icon: const Icon(Icons.file_open_outlined),
              onPressed: widget.onPresetImportRequested,
            ),
          if (widget.onPresetSaveRequested != null)
            AppIconButton(
              keyValue: 'brush-preset-save-button',
              tooltip: AppText.strings.brSaveAsPreset,
              size: AppIconButtonSize.dense,
              // 「＋가 있는 모든 곳, 공통적으로」 — the glyph, not the button.
              icon: Icon(
                Icons.add,
                color: AppColors.addGlyph(
                  enabled: widget.onPresetSaveRequested != null,
                ),
              ),
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
                      Expanded(
                        child: ContentScrollbar(
                          controller: _scrollController,
                          builder: (context, _) =>
                              _buildList(visible, reorderable),
                        ),
                      ),
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
  ///
  /// 🚨TWO THIRDS OF A BRUSH CELL, WIDE RATHER THAN TALL.
  ///
  /// The shape came from `brush-group-tab-shape-Q1` 답 1 (2026-09-10): the
  /// spec was two sentences that fought each other in pixels — 「그룹도 **좀
  /// 더 길게**해서 그룹이름 어느정도 **제대로 보이도록**」 and 「비율적으로
  /// 그룹은 **브러시 프리뷰 세로길이의 반**」 — because a brush cell is 34 and
  /// an 11pt name had been sitting in 26. The answer reads 「길게」 as WIDTH:
  /// the tab gets shorter and the rail gets wider, so both sentences hold.
  ///
  /// The FRACTION then moved once, on sight: 유저 2026-09-10, 「지금 브러시의
  /// 절반인데 너무 작으니 2/3로 하고싶고」. A half was 17; two thirds of 34 is
  /// 22.67, and this is the nearest whole pixel to it.
  ///
  /// ⚠️ROUNDED ON PURPOSE. 34 does not divide by 3, and the rail is a list of
  /// fixed-height rows with backgrounds: a 22.67 row puts every boundary on a
  /// third of a logical pixel, which is a seam between tabs at every DPR. The
  /// pin asserts the rounding rather than the fraction, so it still fails if
  /// either number moves without the other.
  ///
  /// ⚠️AND THE COST WAS TAKEN WITH IT: at the stock 260px panel a rail of 120
  /// leaves 140 for the grid, which is ONE column of 130px cells. That is on
  /// the card as the price of the answer, not a regression to fix.
  static const double extent = 23;

  /// Rail width once names are showing.
  ///
  /// 96 cut a group name at two or three characters, which is what 「이름이
  /// 제대로 보이도록」 was about.
  static const double namedWidth = 120;

  /// The tab's picture: the group's chosen icon, else its first brush, else
  /// a plain folder. Choosing is for when that guess reads wrong.
  Widget _face(ColorScheme colorScheme) {
    if (icon != null) {
      return Icon(
        brushGroupIconGlyph(icon!),
        size: 13,
        color: colorScheme.onSurfaceVariant,
      );
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
      shape: AppShapes.container(AppShapes.wellRadius),
      child: InkWell(
        key: ValueKey<String>(keyValue),
        // The switch rides the raw pointer (R10) — see the wrapper below.
        // The InkWell keeps a no-op tap so its ripple and its semantics
        // stay, the same shape the timeline cells use.
        onTap: () {},
        onDoubleTap: onEdit,
        customBorder: AppShapes.container(AppShapes.wellRadius),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
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
      return ControlPressClaim(
        onPressed: onTap,
        child: InkWell(
          key: ValueKey<String>(keyValue),
          onTap: silentPress(onTap),
          customBorder: AppShapes.container(AppShapes.wellRadius),
          child: Container(
            width: 26,
            height: 26,
            decoration: ShapeDecoration(
              // Selection reads as colour only, never a checkmark.
              color: isSelected
                  ? colorScheme.surfaceContainerHigh
                  : Colors.transparent,
              shape: AppShapes.container(
                AppShapes.wellRadius,
                side: BorderSide(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
            ),
            child: child,
          ),
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
                brushGroupIconGlyph(icon),
                size: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
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

  static const double _barWidth = 5;
  static const double _tipSide = 24;
  static const double _tipGap = 6;
  static const double _trailing = 2;

  /// A cell showing the tip and nothing else (H37) — the list's counterpart
  /// of the rail's `extent`: exactly the width of what is drawn.
  static const double tipsOnlyWidth = _barWidth + _tipSide + _trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
        shape: AppShapes.container(AppShapes.windowRadius),
        child: InkWell(
          // Key kept from the former chip UI so existing flows/tests hold.
          key: ValueKey<String>('brush-preset-chip-${preset.id.value}'),
          customBorder: AppShapes.container(AppShapes.windowRadius),
          onTap: onApplied == null ? null : () => onApplied!(preset),
          child: SizedBox(
            height: brushPresetRowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _barWidth,
                  child: selected
                      ? Center(
                          child: Container(
                            width: 2,
                            height: 22,
                            decoration: ShapeDecoration(
                              color: colorScheme.primary,
                              shape: AppShapes.container(1),
                            ),
                          ),
                        )
                      : null,
                ),
                if (showTipIcon) ...[
                  Container(
                    width: _tipSide,
                    height: _tipSide,
                    decoration: ShapeDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: AppShapes.container(
                        AppShapes.wellRadius,
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: BrushTipPreview(settings: preset.settings),
                  ),
                  if (showName || showStrokePreview)
                    const SizedBox(width: _tipGap),
                ],
                Expanded(child: _rowBody(colorScheme)),
                const SizedBox(width: _trailing),
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
    // 🚨THE NAME MOVED INTO THE PREVIEW: it rides the stroke (유저
    // 2026-09-08), dead centre (H38), in the shared slider's writing (H38
    // again) — see `BrushStrokePreview._nameOverlay`, which owns the
    // placement, the ink and the ⛔rejected 78%-alpha plate.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: BrushStrokePreview(
        settings: preset.settings,
        name: showName ? preset.name : null,
        // The row paints nothing of its own when it is not selected, so the
        // panel's surface IS the ground under the sample.
        nameGround: selected
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surface,
      ),
    );
  }
}
