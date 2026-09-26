import 'package:flutter/widgets.dart';

/// An [IndexedStack] whose children build LAZILY and rebuild only when
/// their own state slice changes (R18 UI-4).
///
/// The tool panels' per-switch rebuild was measurably the bulk of the
/// tool-switch jank (frozen-panel experiment: 16–27 → 8–10 janks): every
/// brush⟷eraser switch rebuilt the whole settings/library subtree from
/// scratch. Here each key's subtree is built once, kept alive offstage,
/// and a switch back to it is a pure index flip — it rebuilds only when
/// [stateOf] no longer equals the state it was built with.
///
/// SAFETY BY CONSTRUCTION: a cached child is reused only when its
/// captured state compares EQUAL (by value) to the current one, so
/// closures inside it can never act on semantically stale data. Slices
/// must implement value `==` (records and value classes do).
class KeyedKeepAliveStack<K, S> extends StatefulWidget {
  const KeyedKeepAliveStack({
    super.key,
    required this.keys,
    required this.activeKey,
    required this.stateOf,
    required this.builder,
  });

  /// Stable child order; must contain [activeKey]. Never-visited keys
  /// hold an empty placeholder.
  final List<K> keys;

  final K activeKey;

  /// The CURRENT state slice the active child's content depends on.
  final S Function() stateOf;

  /// Builds the active key's subtree with the current state (the caller
  /// closes over it).
  final Widget Function(BuildContext context) builder;

  @override
  State<KeyedKeepAliveStack<K, S>> createState() =>
      _KeyedKeepAliveStackState<K, S>();
}

class _KeyedKeepAliveStackState<K, S> extends State<KeyedKeepAliveStack<K, S>> {
  /// Each visited key's child, held where only THAT key's slot hears it
  /// change.
  final Map<K, ValueNotifier<Widget>> _slots = {};
  final Map<K, S> _states = {};

  /// 🚨The stack as last built, handed back unchanged while the same key is
  /// active over the same keys (2026-09-26). [IndexedStack] wraps EVERY
  /// child in its own visibility scaffolding and rebuilds all of it
  /// whenever it is rebuilt — four elements a key, for keys nobody is
  /// looking at. A state change of the active key is news for one slot, so
  /// that slot is all that rebuilds: a brush pick rebuilt forty wrappers in
  /// each of the tool panels, and a size drag did on every frame.
  IndexedStack? _stack;
  K? _stackKey;
  List<K>? _stackKeys;

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.activeKey;
    final state = widget.stateOf();
    final slot = _slots[key];
    if (slot == null) {
      _slots[key] = ValueNotifier<Widget>(_childOf(context, key));
      _states[key] = state;
      _stack = null;
    } else if (_states[key] != state) {
      slot.value = _childOf(context, key);
      _states[key] = state;
    }
    final stack = _stack;
    if (stack != null &&
        _stackKey == key &&
        identical(_stackKeys, widget.keys)) {
      return stack;
    }
    _stackKey = key;
    _stackKeys = widget.keys;
    return _stack = IndexedStack(
      index: widget.keys.indexOf(key),
      children: [
        for (final k in widget.keys)
          if (_slots[k] case final kept?)
            ValueListenableBuilder<Widget>(
              key: ValueKey<K>(k),
              valueListenable: kept,
              builder: (context, child, _) => child,
            )
          else
            SizedBox.shrink(key: ValueKey<K>(k)),
      ],
    );
  }

  Widget _childOf(BuildContext context, K key) =>
      KeyedSubtree(key: ValueKey<K>(key), child: widget.builder(context));
}
