/// 🚨★★★**A BYTE CAP THAT A MEMORY WARNING ONLY EVER LOWERS.**
///
/// Three caches in this app hold pixels and all three must give some back
/// when the OS says memory is tight. They used to say so in three places,
/// in three slightly different ways — and `HistoryManager` even wrote the
/// duplication down in prose: 「the same shape `BrushFrameStore` already
/// uses, and for the same reason」. Prose is not sharing. This is.
///
/// What is genuinely shared is the INVARIANT, not the target:
///
/// • **Pressure only ever lowers.** A budget already under the target —
///   a test, a deliberately tight caller, or a second warning after the
///   first — must not be RAISED by the very signal that says memory is
///   scarce. Every one of the three had to re-derive this guard, and a
///   fourth cache would have had to as well.
/// • **It is idempotent.** iOS sends the warning repeatedly as things get
///   worse; the second one must not halve again forever.
/// • **It holds while the app stays in front** — coming back lifts it
///   ([liftEveryWarning]).
///
/// Where pressure PUTS it stays each cache's own policy, because they
/// genuinely differ and pretending otherwise would be inventing a rule:
/// the cel store halves (its cold tier catches what falls out, so the cut
/// is cheap and can be gentle), while the undo stack drops 8× at once
/// (its bytes are full-canvas snapshots with nowhere to fall to, and that
/// is the cache that killed the user's iPhone — 「세번째, 네번째 변형쯤에서
/// 말없이 앱 종료됨」).
class MemoryPressureBudget {
  /// A budget that pressure HALVES, never below [floor].
  ///
  /// The floor is not a second opinion about the halving — it is the
  /// point below which the cache would thrash instead of holding a
  /// working set, so cutting further costs more than it saves.
  MemoryPressureBudget.halving({required int normal, required int floor})
    : _normal = normal,
      _floor = floor,
      _fixedTarget = null;

  /// A budget that pressure drops straight to [underPressure].
  MemoryPressureBudget.droppingTo({
    required int normal,
    required int underPressure,
  }) : _normal = normal,
       _floor = underPressure,
       _fixedTarget = underPressure;

  final int _floor;

  /// Non-null for [MemoryPressureBudget.droppingTo]: the one target, as
  /// opposed to halving toward [_floor].
  final int? _fixedTarget;

  /// The cap a caller set — what [bytes] is while no warning stands.
  int _normal;

  /// What the standing warning lowered the cap to, and the stay in front
  /// it was said in ([liftEveryWarning]) — null while none was said.
  ({int bytes, int stay})? _warned;

  /// The cap in force: what a warning lowered it to while that warning
  /// stands ([liftEveryWarning]), and the normal a caller set otherwise.
  ///
  /// ⚠️Assigning is NOT guarded by the lowers-only rule, deliberately: a
  /// caller setting a budget is stating a new normal, which is a different
  /// act from the OS reporting pressure. What pressure lowered, a later
  /// assignment may raise — that is how the session seeds the
  /// device-scaled number, and how a test builds a tight fixture.
  int get bytes {
    final warned = _warned;
    return warned != null && warned.stay == _stay ? warned.bytes : _normal;
  }

  set bytes(int value) {
    _normal = value;
    _warned = null;
  }

  /// Where a warning right now would put the cap.
  int get targetUnderPressure {
    final target = _fixedTarget ?? bytes ~/ 2;
    return target < _floor ? _floor : target;
  }

  /// Lowers the cap for a memory warning. Answers whether it MOVED, so a
  /// caller can skip the sweep — and, more importantly, so a test can
  /// tell「pressure did nothing」from「pressure ran」without reading the
  /// number back and reasoning about which policy it was built with.
  bool respondToMemoryPressure() {
    final target = targetUnderPressure;
    if (target >= bytes) {
      return false;
    }
    _warned = (bytes: target, stay: _stay);
    return true;
  }

  /// How many times the app has come back to the front — a warning stands
  /// for the stay it was said in.
  static int _stay = 0;

  /// The app is in front again: no warning said before now stands, and
  /// every cap is its normal again — read where it is read, so a cache
  /// nobody asks is not touched.
  ///
  /// 🚨F-504 (유저 2026-10-29, Galaxy Tab: 「재생시 처음에 지금, 뒤 한장만
  /// 초록바 … 메모리 허용을 살짝 조절햇다 원래대로 돌리니 그 초록바가
  /// 20프레임유지」 · 「허용된거에서 메모리 최대한쓰자」): Android's Flutter
  /// embedding says memory is tight at every trim level from RUNNING_LOW
  /// up (`FlutterActivityAndFragmentDelegate.onTrimMemory`), and since API
  /// 34 the only levels an app is told are UI_HIDDEN and BACKGROUND — the
  /// app being covered, by a picker or by Drive. Every trip away halved
  /// the caches, and only a move of the allowance raised them: a few trips
  /// left playback on its floor, two frames of a large canvas.
  /// ↩️Until 2026-10-29 a warning held until the allowance next moved —
  /// a rule nobody asked for, written with the allowance (2026-09-11).
  /// ⚠️A warning said in front (iOS's) still holds until the app next
  /// comes back: that is the one the iPhone was killed after.
  static void liftEveryWarning() => _stay += 1;
}

/// A cache's NORMAL size for the machine it is running on: a share of
/// physical RAM, clamped.
///
/// ⚠️[ceiling] is also the answer when the platform will not say how much
/// RAM there is (tests, host runs, an engine that did not load) — every
/// one of these budgets was a fixed desktop number before it scaled, and
/// that number is the ceiling, so an unknown machine keeps exactly what
/// it used to get.
///
/// The two callers differ only in their three numbers: hot cels take
/// RAM/4 because they are what the screen is drawn from, undo takes RAM/8
/// because the pair has to sum to something a small tablet survives. The
/// SHAPE is one thing and lives here — it was written twice, and the
/// clone scan is what said so.
int deviceScaledBudget({
  required int? physicalMemoryBytes,
  required int divisor,
  required int floor,
  required int ceiling,
}) {
  if (physicalMemoryBytes == null || physicalMemoryBytes <= 0) {
    return ceiling;
  }
  final share = physicalMemoryBytes ~/ divisor;
  if (share < floor) {
    return floor;
  }
  return share > ceiling ? ceiling : share;
}
