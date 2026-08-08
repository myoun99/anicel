import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One dock's tab group: an ordered tab list plus which of them is showing.
///
/// A dock holds ONE of these or nothing at all. Docks used to hold a STACK
/// of them — panel below panel, each with its own strip and a splitter
/// between — which is the free-form dock tree this app left behind: a panel
/// goes where its BUTTON is now. The stack outlived the gestures that built
/// it (a saved layout still described one, and the host still knew how to
/// draw it), so a workspace saved before the change reopened with the old
/// shape and no way back out of it. Removing the concept is the fix.
class DockGroup {
  DockGroup({required List<String> tabs, String? activeTabId})
    : _tabs = List.of(tabs),
      _activeTabId = tabs.contains(activeTabId) ? activeTabId! : tabs.first,
      assert(tabs.isNotEmpty);

  final List<String> _tabs;
  String _activeTabId;

  List<String> get tabs => List.unmodifiable(_tabs);
  String get activeTabId => _activeTabId;
}

/// Where a tab currently lives.
typedef DockTabLocation = ({String dockId, int tabIndex});

/// Which panel tabs live in which dock, in what order, and which one is
/// active there. This is pure layout state — the panel definitions
/// (label/icon/content) stay with the workspace that owns the panels.
///
/// Every dock id the app knows is a KEY here, whether or not it holds
/// anything: an empty dock renders as a drop rail so a panel can be dragged
/// back into it, and the rail slot pool needs its ids to exist across a
/// restore. A dock with no tabs maps to null; there is no such thing as an
/// empty group.
class EditorPanelLayoutModel extends ChangeNotifier {
  EditorPanelLayoutModel({
    required Map<String, DockGroup?> docks,
    Map<String, double> dockExtents = const <String, double>{},
  }) : _docks = Map.of(docks),
       _dockExtents = Map.of(dockExtents);

  /// A SEPARATE, finer signal for "a dock changed size".
  ///
  /// The whole workspace — both rails, the full-bleed canvas, the floating
  /// region — is built inside one listener on this model, so a splitter
  /// firing [notifyListeners] on every drag frame rebuilt the canvas panel
  /// once per frame. That is the lag: dragging a divider was repainting the
  /// drawing surface.
  ///
  /// A resize does not change WHAT is docked, only how wide it is, so it
  /// rides its own notifier and only the widgets that actually read an
  /// extent listen to it.
  final ValueNotifier<int> extentRevision = ValueNotifier<int>(0);

  @override
  void dispose() {
    extentRevision.dispose();
    super.dispose();
  }

  final Map<String, DockGroup?> _docks;

  /// Resizable dock extents (side dock widths, bottom dock height) in
  /// logical pixels; docks without an entry use their built-in size.
  final Map<String, double> _dockExtents;

  static const double _minDockExtent = 160;

  /// The default ceiling — a guard against an absurd WIDTH, which is the
  /// axis this model was written for. A caller that knows a truer ceiling
  /// says so and overrides it in either direction: a rail panel's HEIGHT
  /// is bounded by the rail, which on a tall window is more than this and
  /// on a short one is much less.
  static const double maxDockExtent = 640;

  Iterable<String> get dockIds => _docks.keys;

  double dockExtent(String dockId, {required double fallback}) =>
      _dockExtents[dockId] ?? fallback;

  /// Adjusts a dock's extent by a drag delta (positive grows the dock).
  ///
  /// [minExtent] is what the dock's own PANELS need along this axis (the
  /// caller knows the tabs; this model does not). It raises the floor above
  /// [_minDockExtent] so the splitter stops where the content stops
  /// shrinking, instead of dragging on past it and cutting the bottom off —
  /// the shrink-floor round's whole point. It never LOWERS the floor, and a
  /// dock too small for its own maximum keeps the maximum.
  /// Returns the part of [delta] that actually moved the edge.
  ///
  /// The remainder is travel the hand made past a floor or a ceiling, and
  /// [DockEdgeSplitter] keeps it so the return trip has to spend it before
  /// the edge moves again (유저, R4 #13). Dropping it here is what made a
  /// splitter that had been pushed to the wall run out ahead of the cursor
  /// on the way back.
  double resizeDock(
    String dockId,
    double delta, {
    required double fallback,
    double? minExtent,
    double? maxExtent,
  }) {
    final ceiling = (maxExtent ?? maxDockExtent).clamp(0.0, double.infinity)
        .toDouble();
    final floor = math
        .max(_minDockExtent, minExtent ?? 0)
        .clamp(0.0, ceiling)
        .toDouble();
    // The CURRENT value is clamped first: a dock restored from a layout
    // saved before this floor existed sits below it, and the host already
    // draws it at the floor. Adding the delta to the stored value instead
    // would make the first drag frame jump.
    //
    // The CEILING is the same promise at the other end. Without it the
    // stored number kept growing past what the window could show, so the
    // drag back down spent that surplus before the edge moved at all —
    // "the splitter follows the cursor, but late and short".
    final current = dockExtent(dockId, fallback: fallback).clamp(floor, ceiling);
    final next = (current + delta).clamp(floor, ceiling).toDouble();
    // What the edge MOVED, which is the honest answer to "how much of that
    // did you use" even on the frame where the stored number does not
    // change (a dock restored below a floor that did not exist when it was
    // saved is drawn at the floor already).
    final used = next - current;
    if (next == _dockExtents[dockId]) {
      return used;
    }
    _dockExtents[dockId] = next;
    // NOT notifyListeners: see [extentRevision]. A width is not a change of
    // arrangement, and paying for a full workspace rebuild per drag frame is
    // what made the splitter feel heavy.
    extentRevision.value += 1;
    return used;
  }

  /// Sets a dock's extent outright (a restore, a reset, a detent).
  void setDockExtent(String dockId, double extent) {
    if (_dockExtents[dockId] == extent) {
      return;
    }
    _dockExtents[dockId] = extent;
    extentRevision.value += 1;
  }

  /// The tabs of [dockId], in strip order; empty when the dock holds
  /// nothing.
  List<String> tabsIn(String dockId) =>
      _docks[dockId]?.tabs ?? const <String>[];

  /// The showing tab of [dockId]; null when the dock holds nothing.
  String? activeTabIn(String dockId) => _docks[dockId]?.activeTabId;

  /// The dock/tab position of a tab; null for unknown ids.
  DockTabLocation? locateTab(String tabId) {
    for (final entry in _docks.entries) {
      final group = entry.value;
      if (group == null) {
        continue;
      }
      final index = group._tabs.indexOf(tabId);
      if (index >= 0) {
        return (dockId: entry.key, tabIndex: index);
      }
    }
    return null;
  }

  /// The active tab of every dock, for visibility checks.
  Iterable<String> get activeTabs sync* {
    for (final group in _docks.values) {
      if (group != null) {
        yield group._activeTabId;
      }
    }
  }

  void selectTab(String dockId, String tabId) {
    final group = _docks[dockId];
    if (group == null ||
        !group._tabs.contains(tabId) ||
        group._activeTabId == tabId) {
      return;
    }
    group._activeTabId = tabId;
    notifyListeners();
  }

  /// Whether a tab may be dropped into [toDockId]: any known tab may move
  /// to any known dock (panels dock anywhere; an emptied dock collapses).
  bool canMoveTab({required String tabId, required String toDockId}) {
    return locateTab(tabId) != null && _docks.containsKey(toDockId);
  }

  /// Moves a tab into [toDockId] at [insertIndex] (counted in the target's
  /// tabs BEFORE the tab is removed from its current position). The moved
  /// tab becomes the target's active tab. An empty target grows its group.
  void moveTab({
    required String tabId,
    required String toDockId,
    required int insertIndex,
  }) {
    final from = locateTab(tabId);
    if (from == null || !_docks.containsKey(toDockId)) {
      return;
    }
    final source = _docks[from.dockId]!;
    final target = _docks[toDockId];

    if (identical(source, target)) {
      var index = insertIndex.clamp(0, source._tabs.length);
      if (index > from.tabIndex) {
        index -= 1;
      }
      if (index == from.tabIndex) {
        return;
      }
      source._tabs
        ..removeAt(from.tabIndex)
        ..insert(index, tabId);
      notifyListeners();
      return;
    }

    _removeTab(from);
    final group = _docks[toDockId];
    if (group == null) {
      _docks[toDockId] = DockGroup(tabs: [tabId]);
    } else {
      group._tabs.insert(insertIndex.clamp(0, group._tabs.length), tabId);
      group._activeTabId = tabId;
    }
    notifyListeners();
  }

  /// Hides a panel: removes its tab from the layout entirely (a dock
  /// emptied this way collapses). Reopen via [addTab].
  void removeTab(String tabId) {
    final from = locateTab(tabId);
    if (from == null) {
      return;
    }
    _removeTab(from);
    notifyListeners();
  }

  /// Re-opens a hidden panel INTO [dockId]'s group; no-op when the tab is
  /// already placed or the dock is unknown.
  void addTab(String tabId, {required String toDockId}) {
    if (!_docks.containsKey(toDockId) || locateTab(tabId) != null) {
      return;
    }
    final group = _docks[toDockId];
    if (group == null) {
      _docks[toDockId] = DockGroup(tabs: [tabId]);
    } else {
      group._tabs.add(tabId);
    }
    notifyListeners();
  }

  /// Serializes the whole dock layout (tabs, active tabs, dock extents) for
  /// persistence.
  Map<String, Object?> toJson() => {
    'docks': {
      for (final entry in _docks.entries)
        if (entry.value case final group?)
          entry.key: {'tabs': group._tabs, 'active': group._activeTabId},
    },
    'extents': _dockExtents,
  };

  /// Replaces the whole layout with a restored one (e.g. from the saved
  /// workspace file).
  void restore({
    required Map<String, DockGroup?> docks,
    Map<String, double> dockExtents = const <String, double>{},
  }) {
    _docks
      ..clear()
      ..addAll(docks);
    _dockExtents
      ..clear()
      ..addAll(dockExtents);
    notifyListeners();
  }

  /// Removes a tab from its location; a dock left with no tabs goes empty.
  void _removeTab(DockTabLocation from) {
    final group = _docks[from.dockId]!;
    group._tabs.removeAt(from.tabIndex);
    if (group._tabs.isEmpty) {
      _docks[from.dockId] = null;
      return;
    }
    // If the moved tab was the active one, fall back to the nearest
    // remaining neighbour.
    if (!group._tabs.contains(group._activeTabId)) {
      group._activeTabId =
          group._tabs[from.tabIndex.clamp(0, group._tabs.length - 1)];
    }
  }
}
