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

/// The automatic allowance — what the app's caches may hold between them
/// when nobody has moved the slider.
///
/// 🗣️유저 2026-09-14 (C-ipad-crash ③): 「메모리 상한 초기값 하드코딩하지 말 것.
/// 기기 RAM 용량 따라 설정」 — the sum of the cache laws stood here, and its
/// fixed lines (playback, the native uploads, the tips, the live stroke)
/// stop scaling at 6GB of RAM, so a 48GB PC and a 12GB iPhone both read
/// 5,560MB.
///
/// 🗣️유저 2026-09-16 (memory-allowance-Q1): 「OS 가 이 앱에 주는 한도의 절반
/// (알려 주지 않는 곳은 RAM 의 절반)」. iOS gives every app a limit of its
/// own and the engine can read it ([QaNativeEngine.appMemoryLimitBytes]:
/// held plus still available, the ceiling a jetsam decision is made
/// against), so there the allowance is half of that, read ONCE at start;
/// everywhere else it is half the RAM. And (Q2's note) never under
/// [floorBytes] — the least the app runs on, which is the caches' floors.
///
/// Unknown RAM (no engine: tests, host runs) keeps [lawsTotalBytes], the
/// numbers as they were, byte for byte.
int automaticAllowanceBytes({
  required int? physicalMemoryBytes,
  required int? appMemoryLimitBytes,
  required int floorBytes,
  required int lawsTotalBytes,
}) {
  if (physicalMemoryBytes == null || physicalMemoryBytes <= 0) {
    return lawsTotalBytes;
  }
  final limit = appMemoryLimitBytes != null && appMemoryLimitBytes > 0
      ? appMemoryLimitBytes
      : physicalMemoryBytes;
  return math.max(limit ~/ 2, floorBytes);
}
