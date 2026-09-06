import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../listenable_rebind.dart';

/// Whether the surrounding panel tab is the ACTIVE tab of its group.
///
/// [EditorPanelTabs] provides this around every tab's content, carrying a
/// STABLE per-tab [ValueListenable] (so consumers subscribe once and no
/// inherited dependency forces rebuilds on either visibility transition).
/// Keep-alive panels sit offstage while another tab is active; their heavy
/// hosts use [PanelAwareListenableBuilder] to stop rebuilding back there —
/// an offstage rebuild is pure cost, nothing is painted (R12-①).
class PanelVisibilityScope extends InheritedWidget {
  const PanelVisibilityScope({
    super.key,
    required this.visible,
    required super.child,
  });

  final ValueListenable<bool> visible;

  /// Null when no scope is present (bare panels in focused widget tests
  /// behave exactly like always-visible ones).
  static ValueListenable<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PanelVisibilityScope>()?.visible;

  @override
  bool updateShouldNotify(PanelVisibilityScope oldWidget) =>
      !identical(oldWidget.visible, visible);
}

/// A [ListenableBuilder] that stands down while its panel is hidden:
/// notifications arriving offstage only set a dirty flag, and becoming
/// visible again flushes it as ONE catch-up rebuild (none when nothing
/// changed back there). Visible panels rebuild per notify exactly like a
/// plain ListenableBuilder.
class PanelAwareListenableBuilder extends StatefulWidget {
  const PanelAwareListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<PanelAwareListenableBuilder> createState() =>
      _PanelAwareListenableBuilderState();
}

class _PanelAwareListenableBuilderState
    extends State<PanelAwareListenableBuilder> {
  ValueListenable<bool>? _visibility;
  bool _dirty = false;

  bool get _visible => _visibility?.value ?? true;

  void _handleNotify() {
    if (!_visible) {
      _dirty = true;
      return;
    }
    setState(() {});
  }

  void _handleVisibilityChanged() {
    // Fires from the tab strip's build when the active tab changes; this
    // subtree is a DESCENDANT of the strip, so marking it dirty here is
    // legal mid-build and the catch-up lands in the same frame.
    if (_visible && _dirty) {
      _dirty = false;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleNotify);
  }

  @override
  void didUpdateWidget(covariant PanelAwareListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    rebindListener(oldWidget.listenable, widget.listenable, _handleNotify);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope's listenable is stable per tab (the strip owns it), so a
    // plain lookup here suffices — no inherited dependency, no rebuilds
    // from the scope widget itself.
    final next = PanelVisibilityScope.maybeOf(context);
    if (!identical(next, _visibility)) {
      _visibility?.removeListener(_handleVisibilityChanged);
      _visibility = next;
      _visibility?.addListener(_handleVisibilityChanged);
    }
  }

  @override
  void dispose() {
    _visibility?.removeListener(_handleVisibilityChanged);
    widget.listenable.removeListener(_handleNotify);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
