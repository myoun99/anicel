import 'package:flutter/rendering.dart';

/// A painter that decides its repaints by comparing its inputs AS ONE
/// VALUE.
///
/// The hand-written `old.a != a || old.b != b || …` chain is a comparison
/// written a second time, next to the fields it is about: adding a field
/// to a painter and forgetting the chain leaves the old pixels on screen,
/// and the compiler cannot say so. A painter mixing this in names its
/// inputs ONCE, in [props] — a record, which compares itself field by
/// field — and gets the one `shouldRepaint` below.
///
/// 🚨A record compares every field with `==`. A field that must NOT be
/// compared that way — a surface whose `==` walks megabytes of tile
/// bytes, a list or a map whose `==` is identity, a notifier — says so at
/// its place in [props] by wrapping itself in `ByIdentity` / `ByList` /
/// `BySet` / `ByMap` (`timeline/memo_token.dart`), where the reason for
/// the choice can be read beside it. Leaving such a field bare turns a
/// deliberate identity check into a deep compare in silence, which is the
/// one way this pattern can be worse than the chain it replaces.
///
/// A field the painter reads but deliberately does NOT gate on — geometry
/// that arrives through `repaint`, a closure that is fresh every build —
/// is simply absent from [props], with the reason written there.
mixin RepaintOnProps on CustomPainter {
  /// Every input this painter's pixels depend on, as one comparable value.
  Object get props;

  @override
  bool shouldRepaint(covariant RepaintOnProps oldDelegate) =>
      oldDelegate.props != props;
}
