import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A [ValueListenableBuilder] that rebuilds only when a SLICE of the
/// value changes.
///
/// The tool panels each consume one slice of the shared BrushToolState
/// (R18 UI-1): a color-wheel drag must not rebuild the preset grid and
/// the settings knobs, and a tool switch must not rebuild the color
/// wheel — the full-state builders made every state tweak rebuild all
/// four panels (the lab's tool-switch build jank).
///
/// [slice] runs on every notification; the subtree rebuilds only when
/// the new slice `!=` the previous one, so slices must compare by value
/// (primitives and records both do).
///
/// CALLBACK DISCIPLINE: builders receive the CURRENT full value, but
/// any callback that writes back must read the notifier at invoke time
/// (`notifier.value.copyWith(...)`), never capture the builder's value —
/// off-slice fields may have changed without a rebuild, and writing a
/// captured value back would silently revert them.
///
/// ⛔The slicing is [SlicedListenableBuilder]'s, read through the value:
/// one rule for "rebuild only when what is shown changed", whatever the
/// news arrives on.
class SlicedValueListenableBuilder<T, S> extends StatelessWidget {
  const SlicedValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.slice,
    required this.builder,
  });

  final ValueListenable<T> valueListenable;
  final S Function(T value) slice;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    return SlicedListenableBuilder<S>(
      listenable: valueListenable,
      slice: () => slice(valueListenable.value),
      builder: (context, _) => builder(context, valueListenable.value),
    );
  }
}

/// Rebuilds its subtree when [listenable] notifies AND the [slice] it
/// answers has changed — news that changes nothing the subtree shows stops
/// here.
///
/// [builder] is handed the slice, so what it shows IS the slice: a value it
/// read from anywhere else would be one a notification can change without
/// reaching it. Slices compare by value (primitives and records both do).
///
/// A rebuild from ABOVE runs [builder] with the slice read afresh, so
/// nothing the builder was handed by its widget is older than that widget.
class SlicedListenableBuilder<S> extends StatefulWidget {
  const SlicedListenableBuilder({
    super.key,
    required this.listenable,
    required this.slice,
    required this.builder,
  });

  final Listenable listenable;
  final S Function() slice;
  final Widget Function(BuildContext context, S slice) builder;

  @override
  State<SlicedListenableBuilder<S>> createState() =>
      _SlicedListenableBuilderState<S>();
}

class _SlicedListenableBuilderState<S>
    extends State<SlicedListenableBuilder<S>> {
  /// The gate the subtree rebuilds through — the slice it was last built
  /// from, asked of the CURRENT widget's [SlicedListenableBuilder.slice].
  late SlicedListenable<S> _gate = _gateOn(widget.listenable);

  SlicedListenable<S> _gateOn(Listenable listenable) =>
      SlicedListenable<S>(listenable, () => widget.slice())
        ..addListener(_rebuild);

  @override
  void didUpdateWidget(SlicedListenableBuilder<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      _gate.dispose();
      _gate = _gateOn(widget.listenable);
    }
  }

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _gate.reread());
}

/// [listenable]'s news passed on only when the answer of [slice] changes —
/// the one rule behind [SlicedListenableBuilder], for a listener that is not
/// a subtree: a painter's `repaint`, a stratum's live switch.
///
/// Slices compare by value (primitives and records both do).
class SlicedListenable<S> extends ChangeNotifier {
  SlicedListenable(this._listenable, this._slice) : _shown = _slice() {
    _listenable.addListener(_onChanged);
  }

  final Listenable _listenable;
  final S Function() _slice;
  S _shown;

  /// The slice as last passed on.
  S get slice => _shown;

  /// The slice read afresh — what a rebuild from ABOVE shows, so nothing it
  /// was handed is older than that rebuild.
  S reread() => _shown = _slice();

  void _onChanged() {
    final next = _slice();
    if (next == _shown) {
      return;
    }
    _shown = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _listenable.removeListener(_onChanged);
    super.dispose();
  }
}

/// [source] for a reader of one SLICE of it: the value is [source]'s, and
/// its listeners hear only when the slice changes ([SlicedListenable]). A
/// painter handed a busy channel this way repaints for its part alone.
class SlicedValueListenable<T, S> extends SlicedListenable<S>
    implements ValueListenable<T> {
  SlicedValueListenable(this._source, S Function(T value) slice)
    : super(_source, () => slice(_source.value));

  final ValueListenable<T> _source;

  @override
  T get value => _source.value;
}

/// Holds a [SlicedValueListenable] of [valueListenable] for as long as it is
/// mounted, and hands it to [builder] — for a subtree that passes the
/// channel on to listeners of its own (a painter's `repaint`, a stratum's
/// live switch) rather than rebuilding on it.
///
/// [slice] is asked of the CURRENT widget, and the slice is read afresh on
/// every build, as [SlicedListenableBuilder] reads its own.
class SlicedValueListenableScope<T, S> extends StatefulWidget {
  const SlicedValueListenableScope({
    super.key,
    required this.valueListenable,
    required this.slice,
    required this.builder,
  });

  final ValueListenable<T> valueListenable;
  final S Function(T value) slice;
  final Widget Function(
    BuildContext context,
    SlicedValueListenable<T, S> sliced,
  )
  builder;

  @override
  State<SlicedValueListenableScope<T, S>> createState() =>
      _SlicedValueListenableScopeState<T, S>();
}

class _SlicedValueListenableScopeState<T, S>
    extends State<SlicedValueListenableScope<T, S>> {
  late SlicedValueListenable<T, S> _sliced = _slicing(widget.valueListenable);

  SlicedValueListenable<T, S> _slicing(ValueListenable<T> source) =>
      SlicedValueListenable<T, S>(source, (value) => widget.slice(value));

  @override
  void didUpdateWidget(SlicedValueListenableScope<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.valueListenable, widget.valueListenable)) {
      _sliced.dispose();
      _sliced = _slicing(widget.valueListenable);
    }
  }

  @override
  void dispose() {
    _sliced.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sliced.reread();
    return widget.builder(context, _sliced);
  }
}
