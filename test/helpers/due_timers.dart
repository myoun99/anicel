import 'dart:async';

/// A one-shot timer a test fires by hand ([fire]).
class Due implements Timer {
  Due(this.after, this._onDue);

  /// How long it was armed for.
  final Duration after;
  final void Function() _onDue;
  bool _active = true;
  int _ticks = 0;

  /// Its moment come.
  void fire() {
    if (_active) {
      _active = false;
      _ticks += 1;
      _onDue();
    }
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}

/// Every timer a clock under test armed, the latest last — handed to it as
/// its `Timer Function(Duration, void Function())` ([arm]), so nothing waits
/// on a real clock.
class DueTimers {
  final List<Due> armed = [];

  /// A [Due], kept in [armed].
  Timer arm(Duration after, void Function() onDue) {
    final due = Due(after, onDue);
    armed.add(due);
    return due;
  }

  /// The timers neither fired nor cancelled.
  List<Due> get running => [
    for (final due in armed)
      if (due.isActive) due,
  ];
}
