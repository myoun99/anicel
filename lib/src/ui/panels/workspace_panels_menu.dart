import 'dart:async';

import 'package:flutter/foundation.dart';

/// One entry of the AppBar's Panels menu.
typedef WorkspacePanelEntry = ({String tabId, String label, bool visible});

/// Bridges the AppBar's Panels menu and the workspace: the workspace
/// attaches its live panel catalog + a visibility toggler; the menu widget
/// listens and calls [toggle]. Closed (X-ed) panels reopen from here.
class WorkspacePanelsMenuController extends ChangeNotifier {
  List<WorkspacePanelEntry> Function()? _entriesProvider;
  void Function(String tabId)? _toggler;
  void Function()? _layoutReset;
  Listenable? _relay;

  List<WorkspacePanelEntry> get entries => _entriesProvider?.call() ?? const [];

  bool get isAttached => _entriesProvider != null;

  void toggle(String tabId) => _toggler?.call(tabId);

  /// Restores the factory dock layout (Window > Reset Workspace Layout).
  bool get canResetLayout => _layoutReset != null;

  void resetLayout() => _layoutReset?.call();

  /// Which edge the tool strip lives on.
  ///
  /// It used to be answered by dragging the tab across the workspace. With
  /// 고정 도킹 nothing drags any more, so the left-handed choice the strip
  /// was always meant to offer needs a switch of its own — and it rides
  /// the layout, which is already persisted, rather than a new setting.
  bool get toolRailOnRight => _toolRailOnRight?.call() ?? false;

  bool get canMoveToolRail => _toolRailMover != null;

  void setToolRailOnRight(bool onRight) => _toolRailMover?.call(onRight);

  bool Function()? _toolRailOnRight;
  void Function(bool onRight)? _toolRailMover;

  /// Called by the workspace; [relay] (the layout model) drives menu
  /// refreshes.
  void attach({
    required List<WorkspacePanelEntry> Function() entriesProvider,
    required void Function(String tabId) toggler,
    required Listenable relay,
    void Function()? layoutReset,
    bool Function()? toolRailOnRight,
    void Function(bool onRight)? toolRailMover,
  }) {
    _relay?.removeListener(notifyListeners);
    _entriesProvider = entriesProvider;
    _toggler = toggler;
    _layoutReset = layoutReset;
    _toolRailOnRight = toolRailOnRight;
    _toolRailMover = toolRailMover;
    _relay = relay..addListener(notifyListeners);
    // Attach runs inside the workspace's initState — mid-build. The menu
    // strip sits ABOVE the workspace in the tree and is already built, so
    // a synchronous notify would mark it dirty during this same build;
    // defer the initial refresh past the frame.
    scheduleMicrotask(() {
      if (_entriesProvider != null) {
        notifyListeners();
      }
    });
  }

  void detach() {
    _relay?.removeListener(notifyListeners);
    _relay = null;
    _entriesProvider = null;
    _toggler = null;
    _layoutReset = null;
    _toolRailOnRight = null;
    _toolRailMover = null;
  }
}
