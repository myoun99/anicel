import 'package:flutter/foundation.dart';

/// Moves [listener] from [previous] to [next] — the `didUpdateWidget`
/// subscription swap every State that listens to a widget-supplied
/// [Listenable] performs.
///
/// Identity is the test, as it always was at every site: two notifiers
/// that compare equal by value are still two subscriptions. Returns
/// whether a swap happened, so a caller that must re-sync from the new
/// object (read its value, recompute a slice) does that only on a real
/// change and does not restate the identity check to know.
bool rebindListener(
  Listenable? previous,
  Listenable? next,
  VoidCallback listener,
) {
  if (identical(previous, next)) {
    return false;
  }
  previous?.removeListener(listener);
  next?.addListener(listener);
  return true;
}
