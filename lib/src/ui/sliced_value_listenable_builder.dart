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
class SlicedValueListenableBuilder<T, S> extends StatefulWidget {
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
  State<SlicedValueListenableBuilder<T, S>> createState() =>
      _SlicedValueListenableBuilderState<T, S>();
}

class _SlicedValueListenableBuilderState<T, S>
    extends State<SlicedValueListenableBuilder<T, S>> {
  late S _slice;

  @override
  void initState() {
    super.initState();
    widget.valueListenable.addListener(_onChanged);
    _slice = widget.slice(widget.valueListenable.value);
  }

  @override
  void didUpdateWidget(SlicedValueListenableBuilder<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (rebindListener(
      oldWidget.valueListenable,
      widget.valueListenable,
      _onChanged,
    )) {
      _slice = widget.slice(widget.valueListenable.value);
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final next = widget.slice(widget.valueListenable.value);
    if (next == _slice) {
      return;
    }
    setState(() {
      _slice = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.valueListenable.value);
  }
}
