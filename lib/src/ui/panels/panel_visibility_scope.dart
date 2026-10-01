import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

/// A [ListenableBuilder] that stands down while its panel is hidden: it
/// rebuilds through [PanelInSightListenable], so notifications arriving
/// offstage are told as ONE catch-up rebuild when the panel is visible
/// again (none when nothing changed back there). Visible panels rebuild per
/// notify exactly like a plain ListenableBuilder.
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
  late final PanelInSightListenable _gate = PanelInSightListenable(
    widget.listenable,
  )..addListener(_rebuild);

  void _rebuild() => setState(() {});

  @override
  void didUpdateWidget(covariant PanelAwareListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gate.source = widget.listenable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope's listenable is stable per tab (the strip owns it), so a
    // plain lookup here suffices — no inherited dependency, no rebuilds
    // from the scope widget itself.
    _gate.sight = PanelVisibilityScope.maybeOf(context);
  }

  @override
  void dispose() {
    _gate
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// [source] as a panel hears it: in sight every notify passes, and out of
/// sight the news stops at the panel's edge and is told ONCE when the panel
/// comes back (none when nothing changed back there) — an offstage rebuild
/// is pure cost, nothing is painted (R12-①).
///
/// THE gate a hidden panel rests behind: [PanelAwareListenableBuilder]
/// rebuilds through it, and a panel whose parts each subscribe to one
/// channel hands them this in its place, so all of them rest at once
/// (storyboard-drags-lay-out-alone, 10-01: the storyboard kept behind the
/// timeline rebuilt its strip at every step of a timeline drag).
class PanelInSightListenable extends ChangeNotifier {
  PanelInSightListenable(Listenable source) : _source = source {
    source.addListener(_onSource);
  }

  Listenable _source;

  /// What the gate passes on — re-pointable, keeping what it missed.
  Listenable get source => _source;
  set source(Listenable value) {
    if (identical(value, _source)) {
      return;
    }
    _source.removeListener(_onSource);
    _source = value..addListener(_onSource);
  }

  ValueListenable<bool>? _sight;

  /// The panel's sight ([PanelVisibilityScope]); null is always in sight.
  ValueListenable<bool>? get sight => _sight;
  set sight(ValueListenable<bool>? value) {
    if (identical(value, _sight)) {
      return;
    }
    _sight?.removeListener(_onSight);
    _sight = value?..addListener(_onSight);
  }

  bool _missed = false;

  bool get _inSight => _sight?.value ?? true;

  void _onSource() {
    if (!_inSight) {
      _missed = true;
      return;
    }
    notifyListeners();
  }

  void _onSight() {
    // Fires from the tab strip's build when the active tab changes; what
    // hears it is a DESCENDANT of the strip, so the rebuild it asks for is
    // legal mid-build and the catch-up lands in the same frame.
    if (_inSight && _missed) {
      _missed = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onSource);
    _sight?.removeListener(_onSight);
    super.dispose();
  }
}

/// [PanelInSightListenable] over a value channel: the source's value, its
/// news passed only while the panel is in sight.
class PanelInSightValueListenable<T> extends PanelInSightListenable
    implements ValueListenable<T> {
  PanelInSightValueListenable(ValueListenable<T> super.source);

  @override
  ValueListenable<T> get source => super.source as ValueListenable<T>;

  @override
  set source(covariant ValueListenable<T> value) => super.source = value;

  @override
  T get value => source.value;
}
