import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'listenable_rebind.dart';

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
  /// The slice the subtree was last built from.
  late S _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.slice();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(SlicedListenableBuilder<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    rebindListener(oldWidget.listenable, widget.listenable, _onChanged);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.slice() != _shown) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _shown = widget.slice();
    return widget.builder(context, _shown);
  }
}
