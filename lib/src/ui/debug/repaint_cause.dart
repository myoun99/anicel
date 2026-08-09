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
  static bool _pending = false;

  /// Names what the app is doing, for whatever bakes on this frame or the
  /// next one.
  ///
  /// Call it from the places that are KNOWN to schedule frames. Do not
  /// try to be exhaustive — an unattributed bake showing as `unknown` is
  /// a useful reading too, and a wrong attribution is worse than none.
  ///
  /// 🚨 The marks that matter are made from OUTSIDE a frame. A pointer
  /// event is dispatched in [SchedulerPhase.idle] — that is the whole
  /// point, the frame it causes has not begun yet — so [_frameStamp]
  /// returns null for exactly the call this channel exists to serve. The
  /// first version stamped that null and then compared it, which made
  /// [attribute] answer `unknown` unconditionally, for every bake,
  /// forever. A cause channel that cannot name a cause.
  ///
  /// So a mark made between frames is held PENDING and claimed by the
  /// next frame that asks.
  static void note(String cause) {
    if (!collecting) {
      return;
    }
    _cause = cause;
    final stamp = _frameStamp();
    _causeFrame = stamp;
    _pending = stamp == null;
  }

  /// The cause for a bake happening now: whatever was marked during this
  /// frame or in the gap before it, or `unknown`.
  ///
  /// Scoped to one frame on purpose. A mark from two seconds ago explains
  /// nothing, and carrying it forward would turn the report into a story
  /// about whatever the user last touched.
  ///
  /// ⚠️ The residual: a pending mark that no bake ever claims stays
  /// pending, so a mark followed by a long quiet period and then a bake
  /// attributes that bake to the stale mark. In practice the marks this
  /// serves arrive continuously while the pen is moving, so the window is
  /// one frame. Bounding it properly would need a frame-end hook, and
  /// this channel is correlational by construction — being wrong makes a
  /// diagnosis misleading and cannot make a pixel stale, which is the
  /// only reason it is allowed to be approximate at all.
  static String attribute() {
    if (!collecting) {
      return 'unknown';
    }
    final now = _frameStamp();
    if (now == null) {
      return 'unknown';
    }
    if (_causeFrame == now) {
      return _cause ?? 'unknown';
    }
    if (_pending) {
      // The first frame after the mark takes it, and takes it exclusively:
      // stamping it here is what stops a later frame from claiming it too.
      _causeFrame = now;
      _pending = false;
      return _cause ?? 'unknown';
    }
    return 'unknown';
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

  /// The last thing the app marked, whether or not a bake ever claimed
  /// it. Exists so a test can prove the app still CALLS [note] — an
  /// attribution channel with nothing wired into it reads exactly like a
  /// channel reporting good news.
  @visibleForTesting
  static String? get debugMarkedCause => _cause;

  @visibleForTesting
  static void reset() {
    _cause = null;
    _causeFrame = null;
    _pending = false;
  }
}
