import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The factor the memory tab's allowance scales every cache budget by — 1
/// is the automatic allowance, every cache on its own device law.
///
/// 🗣️유저 2026-09-11 (the memory tab's three tiers): the allowance a person
/// sets moves EVERY budget, by the same factor. The session sets its own
/// caches when the allowance changes; a holder that lives in a widget — a
/// viewer, the storyboard's thumbnails — reads this instead, on each ask,
/// so an open viewer follows too.
abstract final class MemoryAllowance {
  static final ValueNotifier<double> factor = ValueNotifier<double>(1);

  /// [bytes] — one budget at the automatic allowance — scaled [by] the
  /// given factor (the current one when omitted), never under [floor]:
  /// below what a cache keeps under a memory warning, it stops being a
  /// cache.
  static int scaled(int bytes, {required int floor, double? by}) =>
      math.max((bytes * (by ?? factor.value)).round(), floor);
}
