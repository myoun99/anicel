/// How a contact's points came in, each at its own time (`PenPath`): how
/// many, how long after the press the first move's came, and the longest
/// wait between two — in the stroke's opening and in all of it. The input
/// inspector's `path` line ([said]).
///
/// 🗣️F-611 (유저 2026-11-18, iPhone build 1093, a finger on a new
/// project's first cel): 「처음구간이 직선으로 이어짐 … 몇번을 그어도
/// 똑같음」. The line the app lays from the points it is handed is round
/// (the whole app under a test, 0.998), so what the phone hands it in the
/// opening is the question, and only the phone can answer it: a wait of
/// about 100 ms in [opening] says the points of that stretch never came in
/// apart — the OS kept them, or they came merged and no datum took them —,
/// one of a frame's length that they came and the line was laid straight
/// from them.
class PenPathTally {
  /// The stretch after the press the `open` wait is taken over — longer
  /// than the user's 「약 0.1초」, so a wait that ends past it still counts.
  static const Duration opening = Duration(milliseconds: 150);

  Duration? _pressed;
  Duration? _last;
  int _points = 0;
  Duration? _firstMove;
  Duration _openingWait = Duration.zero;
  Duration _longestWait = Duration.zero;

  /// A contact's first point, at [at]: the count starts afresh.
  void press(Duration at) {
    _pressed = at;
    _last = at;
    _points = 1;
    _firstMove = null;
    _openingWait = Duration.zero;
    _longestWait = Duration.zero;
  }

  /// The contact's next point, at [at].
  void take(Duration at) {
    final pressed = _pressed;
    final last = _last;
    if (pressed == null || last == null) {
      press(at);
      return;
    }
    final wait = at - last;
    _points += 1;
    _last = at;
    _firstMove ??= wait;
    if (wait > _longestWait) {
      _longestWait = wait;
    }
    if (at - pressed <= opening && wait > _openingWait) {
      _openingWait = wait;
    }
  }

  /// The `path` line of the contact counted since its [press] — and the
  /// count let go of; null when no point came.
  String? said() {
    if (_pressed == null) {
      return null;
    }
    final line =
        'path pts=$_points'
        ' 1st=${_ms(_firstMove)}'
        ' open=${_ms(_openingWait)}'
        ' max=${_ms(_longestWait)}';
    _pressed = null;
    _last = null;
    return line;
  }

  static String _ms(Duration? wait) {
    if (wait == null) {
      return '-';
    }
    final ms = wait.inMicroseconds / Duration.microsecondsPerMillisecond;
    return '${ms.round()}ms';
  }
}
