import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'measurement_mode.dart';

/// What the app was doing when a surface re-baked.
///
/// ## Why this is not Blender's
///
/// Blender's regions carry a `do_draw` tag that named notifiers SET, so
/// "who dirtied this region and why" is a fact the code knows. Ours is
/// implicit: a [StaticRaster] re-bakes because Flutter ran `paint()`,
/// and Flutter does not say who asked. Making it explicit would mean
/// every panel declaring its own invalidation — which buys precision and
/// costs the one property this design has that Blender's does not, that
/// the invalidation CANNOT BE WRONG.
///
/// So this is correlational, and says so. The app marks the handful of
/// things that are known to produce frames; a bake is attributed to
/// whatever was marked in the same frame. Being wrong makes a diagnosis
/// misleading and cannot make a pixel stale, which is the whole reason
/// it is allowed to be approximate.
///
/// ## What it is actually for
///
/// One question, the one that started this whole program: **is this
/// panel re-baking because the pointer moved somewhere else?** A panel
/// re-baking on edits is the design working. A panel re-baking on
/// `pointer` is the design failing, silently, and looking identical.
abstract final class RepaintCause {
  /// Marks are only collected while Frame Stats is up. Everything here
  /// is one comparison and one string assignment on that path, and
  /// nothing at all otherwise.
  static bool get collecting => MeasurementMode.frameStats.value;

  static String? _cause;
  static Duration? _causeFrame;

  /// Names what the app is doing, for whatever bakes on this frame.
  ///
  /// Call it from the places that are KNOWN to schedule frames. Do not
  /// try to be exhaustive — an unattributed bake showing as `unknown` is
  /// a useful reading too, and a wrong attribution is worse than none.
  static void note(String cause) {
    if (!collecting) {
      return;
    }
    _cause = cause;
    _causeFrame = _frameStamp();
  }

  /// The cause for a bake happening now: whatever was marked during this
  /// frame, or `unknown`.
  ///
  /// Scoped to the frame on purpose. A mark from two seconds ago
  /// explains nothing, and carrying it forward would turn the report
  /// into a story about whatever the user last touched.
  static String attribute() {
    if (!collecting) {
      return 'unknown';
    }
    final marked = _causeFrame;
    return marked != null && marked == _frameStamp()
        ? (_cause ?? 'unknown')
        : 'unknown';
  }

  /// The current frame's identity, or null outside a frame.
  ///
  /// `currentFrameTimeStamp` is only valid inside one — `paint` also runs
  /// outside frames (an ancestor's `toImage`, a thumbnail capture), and
  /// reading it there is an error rather than a stale value.
  static Duration? _frameStamp() =>
      SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks ||
          SchedulerBinding.instance.schedulerPhase == SchedulerPhase.midFrameMicrotasks
      ? SchedulerBinding.instance.currentFrameTimeStamp
      : null;

  @visibleForTesting
  static void reset() {
    _cause = null;
    _causeFrame = null;
  }
}
