import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/cut_warm_extent.dart';
import '../../models/playback_quality.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../dev_profile.dart';
import 'cut_frame_composite_cache.dart';

/// How much of the requested warm range is composited already.
@immutable
class PrerenderProgress {
  const PrerenderProgress({required this.cached, required this.total});

  static const none = PrerenderProgress(cached: 0, total: 0);

  final int cached;
  final int total;

  bool get isComplete => cached >= total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrerenderProgress &&
          other.cached == cached &&
          other.total == total;

  @override
  int get hashCode => Object.hash(cached, total);

  @override
  String toString() => 'PrerenderProgress($cached/$total)';
}

/// Background composite warming (the AE RAM-preview green bar analogue).
///
/// One chunked async loop composites one frame per iteration and yields
/// between frames; it stays paused until [idleDelay] has elapsed since the
/// last [notifyEditActivity], so drawing never contends with warming. A new
/// warm request replaces the queue (generation counter cancellation).
class PlaybackPrerenderScheduler {
  PlaybackPrerenderScheduler({
    required this.composites,
    required this.resolveCut,
    this.afterFrameCached,
    this.idleDelay = const Duration(milliseconds: 400),
  });

  final CutFrameCompositeCache composites;
  final Cut? Function(CutId cutId) resolveCut;

  /// Called after each composited frame (budget enforcement hook).
  final void Function()? afterFrameCached;

  final Duration idleDelay;

  /// Frames whose composite threw, and the content signature they threw
  /// at — the warm queue's half of the layer stack's `_failedRevisions`.
  ///
  /// A throwing compose caches nothing, so `alreadyValid` can never come
  /// true for that frame; and the whole queue is rebuilt shortly after
  /// every stroke. Without this, one unreachable cel is re-opened,
  /// re-thrown and re-reported once per queued frame, on every stroke,
  /// for the life of the session — a blocking file open each time, which
  /// is the hot loop the sibling record exists to stop. The signature
  /// comes from the composite cache so "has this frame changed" stays
  /// one rule rather than two.
  final Map<(CutId, int, PlaybackQuality), CutFrameCompositeSignature>
  _failedSignatures = {};

  final ValueNotifier<PrerenderProgress> _progress = ValueNotifier(
    PrerenderProgress.none,
  );
  ValueListenable<PrerenderProgress> get progress => _progress;

  int _generation = 0;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _current = Future<void>.value();
  bool _disposed = false;

  /// Completes when the current warm run has finished or been cancelled
  /// (test hook).
  Future<void> get idle => _current;

  /// Warms one cut, playhead-outward from [aroundFrameIndex] — and then,
  /// when [followedByCutId] names a next cut, that cut start-to-end on
  /// the same run (#31, 유저 확정 2026-08-16: 스토리보드 프로 따라서).
  ///
  /// The lookahead is Storyboard Pro's shape mapped onto this pipeline:
  /// background, idle-gated, one direction (the cut you are about to
  /// enter), and it rides BEHIND every active-cut frame in the order, so
  /// the active cut always wins the budget and the thread. What it bakes
  /// is the COMPOSITE — the one image per frame the readiness bar and
  /// playback actually read — not per-layer intermediates; those pass
  /// through the layer-image LRU and age out on their own. The run's
  /// already-cached skip plus content-addressed adoption (C2) mean a
  /// held or covering next cut costs its DISTINCT pictures, not its
  /// frame count.
  ///
  /// Next-cut frames are deliberately NOT budget-protected: under
  /// pressure the enforcer that runs after every baked frame reclaims
  /// the lookahead first and the active cut keeps its range — standing
  /// down is the correct order, and the waste is bounded by one warm
  /// run per debounced restart.
  void requestWarmCut({
    required CutId cutId,
    required PlaybackQuality quality,
    int aroundFrameIndex = 0,
    CutId? followedByCutId,
  }) {
    final cut = resolveCut(cutId);
    if (cut == null) {
      return;
    }
    // ⑯: the warm reaches what was AUTHORED, not just the conte length.
    // The timeline's runway past the cut end takes drawings like any other
    // frame, and a frame the warm never visits misses in the cache forever
    // — which is how a drawing out there stayed invisible while scrubbing
    // and appeared only on release. B1: the count is the SHARED law
    // ([cutWarmFrameCount]) — budget protection derives from the same
    // function now, so a runway frame this bakes can no longer be evicted
    // as out-of-range by the enforcer that runs after every baked frame.
    final frameCount = cutWarmFrameCount(cut);
    final center = aroundFrameIndex.clamp(0, frameCount - 1);
    final order = <(CutId, int)>[(cutId, center)];
    for (var distance = 1; distance < frameCount; distance += 1) {
      if (center + distance < frameCount) {
        order.add((cutId, center + distance));
      }
      if (center - distance >= 0) {
        order.add((cutId, center - distance));
      }
    }
    final next = followedByCutId == null
        ? null
        : resolveCut(followedByCutId);
    if (next != null && followedByCutId != cutId) {
      // Start-to-end, not playhead-outward: a next cut is entered at its
      // first frame. The same warm law as the active cut (runway
      // included) so the two never disagree about what "the cut" is.
      final nextCount = cutWarmFrameCount(next);
      for (var index = 0; index < nextCount; index += 1) {
        order.add((followedByCutId!, index));
      }
    }
    _restart(order, quality);
  }

  /// Warms a multi-cut playlist sequentially (play-all).
  void requestWarmFrames({
    required List<(CutId, int)> frames,
    required PlaybackQuality quality,
  }) {
    _restart(List.of(frames), quality);
  }

  /// Restarts the idle debounce; warming stays paused while edits are hot.
  void notifyEditActivity() {
    _lastActivity = DateTime.now();
  }

  /// Open input holds (pen down, drag in flight). While any hold is open
  /// warming stands down HARD: the idle gate stays closed regardless of
  /// elapsed time, and an in-flight composite aborts between layers — a
  /// live stroke never shares the UI/raster threads with opportunistic
  /// cache warming (R13-3: the commit-timing stutter).
  int _inputHolds = 0;

  void beginInputHold() {
    _inputHolds += 1;
  }

  void endInputHold() {
    if (_inputHolds > 0) {
      _inputHolds -= 1;
    }
    // The release opens a fresh quiet window: warming resumes idleDelay
    // after the pen lifts, not the instant it lifts.
    notifyEditActivity();
  }

  /// True when warming may touch the UI thread right now.
  bool _isQuietNow() =>
      _inputHolds == 0 && DateTime.now().difference(_lastActivity) >= idleDelay;

  /// Outstanding gate/yield waits, cancellable as a group: [cancel] and
  /// [dispose] flush them so a parked warm run resumes at once, sees its
  /// stale generation and exits — no timer outlives the scheduler (widget
  /// tests assert exactly that at teardown).
  final Map<Timer, Completer<void>> _pendingWaits = {};

  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _pendingWaits.remove(timer);
      completer.complete();
    });
    _pendingWaits[timer] = completer;
    return completer.future;
  }

  void _flushPendingWaits() {
    final waits = Map.of(_pendingWaits);
    _pendingWaits.clear();
    for (final entry in waits.entries) {
      entry.key.cancel();
      entry.value.complete();
    }
  }

  void cancel() {
    _generation += 1;
    _progress.value = PrerenderProgress.none;
    _flushPendingWaits();
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _flushPendingWaits();
    _progress.dispose();
  }

  void _restart(List<(CutId, int)> queue, PlaybackQuality quality) {
    final generation = ++_generation;
    _progress.value = PrerenderProgress(cached: 0, total: queue.length);
    _current = _run(generation, queue, quality);
  }

  Future<void> _run(
    int generation,
    List<(CutId, int)> queue,
    PlaybackQuality quality,
  ) async {
    var cached = 0;
    for (final (cutId, frameIndex) in queue) {
      // Retry loop: an input-interrupted composite is NOT skipped — the
      // frame waits behind the idle gate and warms when quiet returns.
      while (true) {
        await _idleGate(generation);
        if (_isStale(generation)) {
          return;
        }
        final cut = resolveCut(cutId);
        if (cut == null) {
          break;
        }
        final alreadyValid =
            composites.validCompositeOrNull(
              cut: cut,
              frameIndex: frameIndex,
              quality: quality,
            ) !=
            null;
        if (alreadyValid) {
          break;
        }
        final indexKey = (cutId, frameIndex, quality);
        final signature = composites.signatureOf(
          cut: cut,
          frameIndex: frameIndex,
          quality: quality,
        );
        if (_failedSignatures[indexKey] == signature) {
          // This exact content already threw. Nothing about it changed,
          // and the open blocks — so do not pay it again just because a
          // stroke rebuilt the queue.
          break;
        }
        final watch = brushLabProfile ? (Stopwatch()..start()) : null;
        // 🚨ONE FRAME'S FAILURE IS ONE FRAME'S. The composite reads cel
        // STORAGE, so a cel whose bytes are unreachable throws from in
        // here — and this future is nobody's to await, so a throw used to
        // abandon the whole queue: progress froze where it stopped and
        // every later frame was never warmed. Give up on the frame, keep
        // the queue.
        final ui.Image? image;
        try {
          image = await composites.prepareCompositeInterruptible(
            cut: cut,
            frameIndex: frameIndex,
            quality: quality,
            shouldAbort: () => _isStale(generation) || !_isQuietNow(),
          );
        } catch (error, stack) {
          _failedSignatures[indexKey] = signature;
          // Skipping the frame is right; hiding WHY is not. The failure
          // reaches the framework's error channel rather than vanishing,
          // so a permanently unreachable cel is diagnosable instead of
          // showing up only as a queue that never finishes warming. The
          // record above is what keeps that report to once per content
          // state instead of once per stroke.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'playback prerender',
              context: ErrorDescription(
                'warming cut ${cutId.value} frame $frameIndex',
              ),
            ),
          );
          // Every other post-await exit in this loop re-checks staleness
          // before it lets the caller touch `_progress`; skipping it here
          // would let a cancelled or disposed run write its bar back over
          // a live one.
          if (_isStale(generation)) {
            return;
          }
          break;
        }
        if (watch != null) {
          // ignore: avoid_print — BRUSH_LAB_PROFILE-armed builds only.
          print(
            '[lab-warm] f=$frameIndex ${watch.elapsedMilliseconds}ms'
            '${image == null ? ' INTERRUPTED' : ''}',
          );
        }
        if (_isStale(generation)) {
          return;
        }
        if (image == null) {
          continue;
        }
        afterFrameCached?.call();
        break;
      }
      cached += 1;
      _progress.value = PrerenderProgress(cached: cached, total: queue.length);
      // Yield so interactive work interleaves between frames.
      await _wait(Duration.zero);
      if (_isStale(generation)) {
        return;
      }
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  Future<void> _idleGate(int generation) async {
    while (!_isStale(generation)) {
      if (_isQuietNow()) {
        return;
      }
      final remaining = idleDelay - DateTime.now().difference(_lastActivity);
      // With a hold open (or the window already elapsed but held) poll on
      // the 50ms heartbeat; otherwise sleep out the remaining window.
      await _wait(
        remaining > Duration.zero &&
                remaining < const Duration(milliseconds: 50)
            ? remaining
            : const Duration(milliseconds: 50),
      );
    }
  }
}
