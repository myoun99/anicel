part of '../editor_workspace.dart';

/// The STRIP BUTTONS — a strip's group buttons, a rail's down its edge and
/// the top strip's floor buttons along it: the same buttons, the same band,
/// the same drops — as their own object.
///
/// 🚨Carved out of [_WorkspaceDocks] when the top strip took the rails'
/// buttons (I-147, 2026-10-30): 「이 버튼 자체 탭 띠는 공용으로 다른
/// 사이드띠에도 쓸수있게」 made them one thing on three strips, not a part
/// of the edge docks. It reaches the State through `_state`, and asks the
/// docks where a panel may go ([_WorkspaceDocks._canDockAccept]).
class _WorkspaceStripButtons {
  _WorkspaceStripButtons(this._state);

  final _EditorWorkspaceState _state;

  /// [groups]' buttons along [axis], and [emptySlot]'s while something it
  /// would take is in flight.
  ///
  /// 띠는 스크롤하지 않는다 (유저 확정): a strip that scrolls hands drags to
  /// its scroll arena before the buttons ever see them, and dragging a
  /// panel ONTO a button is how a group is made. So the column is plain —
  /// eight slots is the pool, and eight 42px buttons fit any window tall
  /// enough to draw in.
  Widget build({
    required List<String> groups,
    required String? emptySlot,
    required ValueNotifier<bool> nearby,
    Axis axis = Axis.vertical,
  }) => ListenableBuilder(
    listenable: Listenable.merge([
      _state._draggingTab,
      _state._draggingGroup,
    ]),
    builder: (context, _) {
      final slot = emptySlot == null ? null : _emptySlot(emptySlot, nearby);
      final children = [
        for (final railId in groups) ...[
          _button(railId, nearby),
          alongBox(axis, 4),
        ],
        ?slot,
      ];
      final buttons = Flex(
        direction: axis,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
      // The strip is what the band's first rung hears: anywhere on it,
      // every button says it can be lifted, as every tab does anywhere on
      // its panel.
      return MouseRegion(
        onEnter: (_) => nearby.value = true,
        onExit: (_) => nearby.value = false,
        child: Padding(
          padding: switch (axis) {
            Axis.vertical => const EdgeInsets.only(left: 3, top: 4, bottom: 6),
            // The top strip's rule stands its margin before what follows
            // it, where anything does — its other side's is the floor
            // switch's.
            Axis.horizontal when children.isNotEmpty => const EdgeInsets.only(
              left: StripGroupRule.margin,
            ),
            Axis.horizontal => EdgeInsets.zero,
          },
          child: buttons,
        ),
      );
    },
  );

  Widget _button(String railId, ValueNotifier<bool> nearby) {
    final dragging = _state._draggingTab.value;
    final carried = _state._draggingGroup.value;
    return _RailGroupButton(
      railId: railId,
      open: _state._rail.dockShows(railId),
      tabs: [
        for (final tabId in _state._layout.tabsIn(railId))
          _state._tabs.tabFor(tabId),
      ],
      // The COLOUR group's button is the swatch itself. The strip's swatch
      // was the one place the two colours you paint with were readable
      // without opening anything, and moving the picker to a rail would
      // have taken that with it — so the button that opens the picker shows
      // them, and tapping the back slot still swaps (⛔there is no swap
      // glyph: that would be the same verb twice).
      face: _state._rail._colorRailFace(railId),
      nearby: nearby,
      dragging:
          dragging != null && _state._docks._canDockAccept(railId, dragging)
          ? dragging
          : null,
      carried: carried != null && _canJoinGroup(railId, carried)
          ? carried
          : null,
      onPressed: () => _state._rail._pressStripGroup(railId),
      onTabDropped: (data) => _state._rail._dropIntoRailGroup(railId, data),
      onGroupDropped: (data) =>
          _state._rail.carryGroupTo(fromId: data.groupId, toId: railId),
      onLifted: (data) => _state._draggingGroup.value = data,
    );
  }

  /// The one empty slot on offer, and only while something it would take
  /// is in flight: a permanently visible "+" would be a button that does
  /// nothing until you happen to be dragging.
  Widget? _emptySlot(String slotId, ValueNotifier<bool> nearby) {
    final dragging = _state._draggingTab.value;
    final carried = _state._draggingGroup.value;
    final takes =
        (dragging != null && _state._docks._canDockAccept(slotId, dragging)) ||
        (carried != null && _canTakeGroup(slotId, carried));
    if (!takes) {
      return null;
    }
    return _RailGroupButton(
      railId: slotId,
      open: false,
      tabs: const [],
      nearby: nearby,
      dragging: dragging,
      carried: carried,
      onPressed: null,
      onTabDropped: (data) => _state._rail._dropIntoRailGroup(slotId, data),
      onGroupDropped: (data) =>
          _state._rail.carryGroupTo(fromId: data.groupId, toId: slotId),
    );
  }

  /// Whether the button [carried] may stand in the empty [slotId]: what it
  /// holds may stand there ([_WorkspaceDocks._placeHolds]) — on the top
  /// strip a button per panel (I-147-Q2 a), so there must be a slot for
  /// each.
  bool _canTakeGroup(String slotId, _StripGroupDragData carried) {
    final tabs = _state._layout.tabsIn(carried.groupId);
    if (!_state._docks._placeHolds(slotId, tabs)) {
      return false;
    }
    if (!_WorkspaceRail.isTopSlot(slotId)) {
      return true;
    }
    final free = _WorkspaceRail._topSlotIds().where(
      (id) => _state._layout.tabsIn(id).isEmpty,
    );
    return free.length >= tabs.length;
  }

  /// Whether the button [carried] may JOIN the group of the rail button
  /// [groupId] — as a panel dropped on it does (I-147-Q2 a: 「사이드 띠 버튼
  /// 위에 놓으면 그 묶음에 들어간다 — 지금 탭을 버튼에 놓을 때와 같은 법」). A
  /// top strip button joins nothing: it is one panel.
  bool _canJoinGroup(String groupId, _StripGroupDragData carried) =>
      carried.groupId != groupId &&
      !_WorkspaceRail.isTopSlot(groupId) &&
      _state._docks._placeHolds(
        groupId,
        _state._layout.tabsIn(carried.groupId),
      );

  /// The top strip's floor buttons (I-147), handed to the strip through the
  /// panels bridge ([WorkspacePanelsMenuController.floorGroups]).
  Widget buildFloorGroupButtons() => build(
    groups: _state._rail._topGroups(),
    emptySlot: _state._docks._emptyTopSlot(),
    nearby: _state._stripNearby.top,
    axis: Axis.horizontal,
  );
}
