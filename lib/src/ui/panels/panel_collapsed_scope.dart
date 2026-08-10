import 'package:flutter/widgets.dart';

/// Whether the surrounding panel is COLLAPSED — the region it lives in has
/// been folded down to its sill plus whatever the panel says it needs.
///
/// ★This is the seam that makes collapsing a REPRESENTATION rather than a
/// CROP. Before it, the dock simply handed the panel less height than its
/// floor, the shell put it in a vertical scroller at its natural size, and
/// what showed was whatever happened to be in the top of it — measured at
/// 40px of budget over a 136px floor, that was the command bar and four
/// pixels of grid. Every tab that ever lands in the bottom dock inherits
/// that, which is why the answer is a scope the shell provides and not a
/// per-panel guess at its own height.
///
/// A panel that reads this promises ONE thing: at [EditorPanelTab.collapsedExtent]
/// pixels it lays out without overflowing. The frame panels keep their
/// command bar and offstage the grid — 「접으면 버튼행만 남는다」 (유저 확정,
/// 2026-08-10). A panel that declares no extent is never asked: the shell
/// shows nothing at all and the region is its sill alone.
///
/// A plain `bool` and not a listenable, unlike [PanelVisibilityScope]:
/// collapsing changes the panel's LAYOUT, so the rebuild it forces is the
/// work, not an avoidable cost.
class PanelCollapsedScope extends InheritedWidget {
  const PanelCollapsedScope({
    super.key,
    required this.collapsed,
    required super.child,
  });

  final bool collapsed;

  /// False when no scope is present — a panel mounted bare in a focused
  /// widget test behaves exactly like an expanded one.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PanelCollapsedScope>()
          ?.collapsed ??
      false;

  @override
  bool updateShouldNotify(PanelCollapsedScope oldWidget) =>
      oldWidget.collapsed != collapsed;
}
