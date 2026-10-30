import 'dart:async';

import 'package:flutter/widgets.dart';

/// One entry of the AppBar's Panels menu.
typedef WorkspacePanelEntry = ({String tabId, String label, bool visible});

/// One choice of the top strip's FLOOR switch. Label and icon come from the
/// panel's own tab definition rather than from a second set of strings, so
/// the switch and the panel can never disagree about what a thing is called.
typedef WorkspaceFloorTab = ({String tabId, String label, IconData icon});

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

  /// Which panel is lying on the FLOOR — the bottom layer the artwork or a
  /// media page is drawn on, under everything else the shell floats.
  ///
  /// The top strip's canvas/viewer pair is a switch for exactly this, and it
  /// lives above the workspace in the tree, so it asks through the same
  /// bridge the Panels menu already uses rather than growing a second one.
  String? get floorTabId => _floorTabId?.call();

  /// The panels that may lie on the floor, in strip order.
  List<WorkspaceFloorTab> get floorTabs => _floorTabs?.call() ?? const [];

  void selectFloorTab(String tabId) => _floorTabSelector?.call(tabId);

  String? Function()? _floorTabId;
  List<WorkspaceFloorTab> Function()? _floorTabs;
  void Function(String tabId)? _floorTabSelector;

  /// The top strip's floor BUTTONS after its second rule — the groups whose
  /// panels lie on the floor one at a time (I-147). Built by the workspace:
  /// they are its strip buttons, with its bands and its drops.
  Widget floorGroups(BuildContext context) =>
      _floorGroups?.call(context) ?? const SizedBox.shrink();

  WidgetBuilder? _floorGroups;

  /// Which edge the FLOATING REGION is docked to — the timeline and the
  /// paper panels it switches between.
  ///
  /// 아래 도킹 영역은 위/아래 설정 가능 (유저 확정). No new rule was needed
  /// for what flips: 「기하는 캔버스 향한 변에, 정체성은 창틀 향한 변에」
  /// already decides it, so docking at the top puts the resize handle below
  /// and the 문턱 above out of the same one law.
  bool get regionOnTop => _regionOnTop?.call() ?? false;

  bool get canMoveRegion => _regionMover != null;

  void setRegionOnTop(bool onTop) => _regionMover?.call(onTop);

  bool Function()? _regionOnTop;
  void Function(bool onTop)? _regionMover;

  /// Whether the brush's values — its blend, size and opacity — stand in
  /// the top strip rather than in the canvas's pill.
  ///
  /// 🗣️I-34 (유저 2026-10-18): 「그리고 기본값은 알약으로 두는걸 기본값으로.
  /// 그리고 이름도 브러시 값을 상단띠로로 바꾸자. 기본이 알약이다라는걸
  /// 암묵적으로 표시하려고」 — the pill is the default, and the switch is
  /// named for the other place. It rides the layout, as the region's does.
  bool get brushValuesOnStrip => _brushValuesOnStrip?.call() ?? false;

  bool get canMoveBrushValues => _brushValuesMover != null;

  void setBrushValuesOnStrip(bool onStrip) =>
      _brushValuesMover?.call(onStrip);

  bool Function()? _brushValuesOnStrip;
  void Function(bool onStrip)? _brushValuesMover;

  /// Whether the tool strip holds its tools alone — without the shortcut
  /// buttons (undo, redo, onion, solo …) and the rule under them.
  ///
  /// 🗣️I-128 (유저 2026-10-25): 「이 숏컷 버튼 안쓰는 사람 위해서 설정의 패널에
  /// 해당 영역 끌수있게 옵션 제공. 조작단축버튼이랑 도구 버튼 사이의 가로
  /// 구분선도 그 경우 없어도되니 사라지도록」. It rides the layout, as the
  /// brush's values do.
  bool get railToolsOnly => _railToolsOnly?.call() ?? false;

  bool get canSetRailToolsOnly => _railToolsOnlySetter != null;

  void setRailToolsOnly(bool toolsOnly) =>
      _railToolsOnlySetter?.call(toolsOnly);

  bool Function()? _railToolsOnly;
  void Function(bool toolsOnly)? _railToolsOnlySetter;

  /// The floating region's fold — its chevron's press, and its key's (I-40).
  void toggleRegionFolded() => _regionFolder?.call();

  VoidCallback? _regionFolder;

  /// Called by the workspace; [relay] (the layout model) drives menu
  /// refreshes.
  void attach({
    required List<WorkspacePanelEntry> Function() entriesProvider,
    required void Function(String tabId) toggler,
    required Listenable relay,
    void Function()? layoutReset,
    bool Function()? toolRailOnRight,
    void Function(bool onRight)? toolRailMover,
    String? Function()? floorTabId,
    List<WorkspaceFloorTab> Function()? floorTabs,
    void Function(String tabId)? floorTabSelector,
    WidgetBuilder? floorGroups,
    bool Function()? regionOnTop,
    void Function(bool onTop)? regionMover,
    bool Function()? brushValuesOnStrip,
    void Function(bool onStrip)? brushValuesMover,
    bool Function()? railToolsOnly,
    void Function(bool toolsOnly)? railToolsOnlySetter,
    VoidCallback? regionFolder,
  }) {
    _relay?.removeListener(notifyListeners);
    _entriesProvider = entriesProvider;
    _toggler = toggler;
    _layoutReset = layoutReset;
    _toolRailOnRight = toolRailOnRight;
    _toolRailMover = toolRailMover;
    _floorTabId = floorTabId;
    _floorTabs = floorTabs;
    _floorTabSelector = floorTabSelector;
    _floorGroups = floorGroups;
    _regionOnTop = regionOnTop;
    _regionMover = regionMover;
    _brushValuesOnStrip = brushValuesOnStrip;
    _brushValuesMover = brushValuesMover;
    _railToolsOnly = railToolsOnly;
    _railToolsOnlySetter = railToolsOnlySetter;
    _regionFolder = regionFolder;
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
    _floorTabId = null;
    _floorTabs = null;
    _floorTabSelector = null;
    _floorGroups = null;
    _regionOnTop = null;
    _regionMover = null;
    _brushValuesOnStrip = null;
    _brushValuesMover = null;
    _railToolsOnly = null;
    _railToolsOnlySetter = null;
    _regionFolder = null;
  }
}
