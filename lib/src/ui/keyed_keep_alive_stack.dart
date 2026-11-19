import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'timeline/memo_token.dart' show ByIdentity, Kept, keptWhileSame;

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
/// must implement value `==` (records and value classes do). The keep
/// is THE keep ([keptWhileSame]), so a child is built again in another
/// language too — ↩️the state was compared here by hand, and the tool
/// library kept its words through a language switch.
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

  /// Each visited key's child as built, and from what.
  final Map<K, Kept<S>> _kept = {};

  /// 🚨The stack as last built, handed back unchanged while the same key is
  /// active over the same keys (2026-09-26). The stack wraps EVERY child
  /// in the guard that keeps focus off it while hidden and rebuilds all of
  /// them whenever it is rebuilt — for keys nobody is looking at (with
  /// [IndexedStack]'s own visibility scaffolding it was four elements a
  /// key). A state change of the active key is news for one slot, so
  /// that slot is all that rebuilds: a brush pick rebuilt forty wrappers in
  /// each of the tool panels, and a size drag did on every frame. A key
  /// visited for the first time is a slot more — slots only come — so
  /// their count is a fact of the stack ([keptWhileSame]).
  final Map<Type, Kept<Object?>> _stack = {};

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
    final child = keptWhileSame(
      _kept,
      key,
      widget.stateOf(),
      () => _childOf(context, key),
    );
    final slot = _slots[key];
    if (slot == null) {
      _slots[key] = ValueNotifier<Widget>(child);
    } else {
      // The child handed back is the one it holds: no news.
      slot.value = child;
    }
    return keptWhileSame(
      _stack,
      _ShownStack,
      (key, ByIdentity(widget.keys), _slots.length),
      () => _ShownStack(
        index: widget.keys.indexOf(key),
        children: [
          for (final k in widget.keys)
            ExcludeFocus(
              excluding: k != key,
              child: switch (_slots[k]) {
                final kept? => ValueListenableBuilder<Widget>(
                  key: ValueKey<K>(k),
                  valueListenable: kept,
                  builder: (context, child, _) => child,
                ),
                null => SizedBox.shrink(key: ValueKey<K>(k)),
              },
            ),
        ],
      ),
    );
  }

  Widget _childOf(BuildContext context, K key) =>
      KeyedSubtree(key: ValueKey<K>(key), child: widget.builder(context));
}

/// An [IndexedStack] that LAYS OUT only the child it shows.
///
/// 🔬An [IndexedStack] lays out every child at every layout of its own, so
/// a tool's panel kept off stage was laid out again with the one in hand
/// whenever the panel's box changed — measured on a rail scrolling its
/// groups to the part its window shows (tool-settings-rows-cut-off-under-
/// the-variants-panel, 2026-11-20): the brush's library and settings were
/// laid out with the fill's on every frame, and a frame's build took twice
/// as long. One kept off stage keeps the layout it was last shown with and
/// is laid out to its box as it comes back — as an [Overlay] keeps the
/// entries it does not show.
///
/// Painting, hit testing and semantics are [RenderIndexedStack]'s; a finder
/// sees the child shown, as it sees an [IndexedStack]'s; and the stack is
/// as big as that child, the others' sizes being out of date.
class _ShownStack extends MultiChildRenderObjectWidget {
  const _ShownStack({required this.index, required super.children});

  final int index;

  @override
  MultiChildRenderObjectElement createElement() => _ShownStackElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShownStack(
    index: index,
    textDirection: Directionality.maybeOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShownStack renderObject,
  ) {
    renderObject
      ..index = index
      ..textDirection = Directionality.maybeOf(context);
  }
}

class _ShownStackElement extends MultiChildRenderObjectElement {
  _ShownStackElement(_ShownStack super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) =>
      visitor(children.elementAt((widget as _ShownStack).index));
}

class _RenderShownStack extends RenderIndexedStack {
  _RenderShownStack({required int super.index, super.textDirection});

  RenderBox get _shown {
    var child = firstChild!;
    for (var i = 0; i < index!; i += 1) {
      child = childAfter(child)!;
    }
    return child;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_shown.getDryLayout(constraints.loosen()));

  @override
  void performLayout() {
    final shown = _shown..layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(shown.size);
    (shown.parentData! as StackParentData).offset = alignment
        .resolve(textDirection)
        .alongOffset(size - shown.size as Offset);
  }
}
