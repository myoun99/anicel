import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/scheduler.dart';

/// Runs one job after the frame — once, however many times it is asked
/// before that frame ends — or at once where no scheduler binding was ever
/// started (headless painter tests, where there is no frame to wait for).
///
/// The shape four things needed and three had written out by 2026-09-16:
/// the tile cache's coalesced notify (R11-⑥), the picture budget's walk,
/// the deep-picture release and the warm pump. Each keeps an instance of
/// its own, because 「once」 is per job.
class AfterFrameOnce {
  bool _scheduled = false;

  /// Whether a job is waiting on the frame.
  bool get scheduled => _scheduled;

  void ask(void Function() job) {
    if (_scheduled) {
      return;
    }
    final binding = schedulerBindingOrNull();
    if (binding == null) {
      job();
      return;
    }
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      job();
    });
    // Asked between frames, the job still needs a frame to run after.
    binding.ensureVisualUpdate();
  }
}

/// The scheduler binding, or null where none was started.
SchedulerBinding? schedulerBindingOrNull() {
  try {
    return SchedulerBinding.instance;
  } on FlutterError {
    return null;
  }
}
