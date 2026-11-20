import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The app's spinner — the wait window's, and a page's or a frame's that
/// is not there yet ([ViewerPageLoading]) — turning on the frame clock.
///
/// 🚨IT STANDS UP WHERE THE CLOCK IS, NOT AT ITS OWN START (F-617, 검증
/// 2026-11-19: 「체크무늬 종이 + 가운데 청록 점(약 3 px)」). Flutter's
/// spinner turns from where it was put up, and there its arc is 0.001 rad
/// — a dot — and under 0.28 rad, 3 px at this size, for its first 100 ms
/// (measured 2026-11-20). A page waited on for 0.2–0.5 s showed a dot for
/// much of it, and a file opening in the import window handed the opening
/// ring to the page's, which stood up as a dot again. Put up at the frame
/// clock's own phase, every spinner shows the same turn at the same
/// moment: one put up in another's place goes on where it was, and one put
/// up alone is mid-turn.
///
/// Each turns its own ticker, and only while it stands: one controller for
/// the whole app would ask for a frame forever for spinners nobody shows.
class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key});

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner>
    with SingleTickerProviderStateMixin {
  static const Duration _turns =
      CircularProgressIndicator.defaultAnimationDuration;

  late final AnimationController _clock = AnimationController(
    duration: _turns,
    value: _phaseAt(SchedulerBinding.instance.currentSystemFrameTimeStamp),
    vsync: this,
  )..repeat();

  static double _phaseAt(Duration now) =>
      now.inMicroseconds % _turns.inMicroseconds / _turns.inMicroseconds;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CircularProgressIndicator(strokeWidth: 2, controller: _clock);
}
