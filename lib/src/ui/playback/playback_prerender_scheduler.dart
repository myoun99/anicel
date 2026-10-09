import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/cut_warm_extent.dart';
import '../../services/playback/frame_demand.dart';
import '../../core/dev_profile.dart';
import 'playback_pictures.dart';

/// How much of what is wanted is composited already.
@immutable
class PrerenderProgress {
  const PrerenderProgress({required this.cached, required this.total});

  static const none = PrerenderProgress(cached: 0, total: 0);

  /// The frames on from where the walk starts whose pictures are there.
  final int cached;

  /// The frames the walk expects to get there: every one wanted, or — when
  /// the allowance holds fewer — as many as fit. It is [cached] once the
  /// walk has nothing left to make.
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

/// The room playback's pictures have, asked by their maker before it makes
/// one.
abstract interface class PictureRoom {
  /// The bytes pictures may hold now.
  int get bytes;

  /// Makes room for a picture of [bytes] that is wanted [step] steps on, by
  /// letting go of pictures wanted LATER than it — never of one wanted
  /// sooner, nor of one a screen shows. False when that leaves no room.
  bool makeRoomFor({required int bytes, required int step});
}

/// The one maker of playback's pictures (the AE RAM-preview green bar
/// analogue): it walks what is WANTED ([FrameDemand]) from the playhead on
/// and composites the first picture that is not there — one at a time,
/// yielding between them. A new demand replaces the one being followed
/// (generation counter cancellation).
///
/// Under the hand that draws it stays paused until [idleDelay] has elapsed
/// since the last [notifyEditActivity], so drawing never contends with
/// warming. 🚨A run that PLAYS is followed at once (유저 2026-10-08: 「1
/// 재생누르면 바로 재생」) — ↩️it waited out the same quiet window, 1.2
/// seconds from the last stroke or seek to the first picture, and nothing
/// draws under a run.
///
/// 🚨IT RESTS WHEN NO MORE FITS (유저 2026-10-08: 「4 허용치도 해결」). A
/// picture is made only when the allowance has room for it, or can be given
/// room by letting go of pictures wanted LATER than it ([room]). When
/// neither, what is held IS the window, and the walk rests until the
/// playhead moves it on. ↩️It made every frame it was asked for and left the
/// budget to evict behind it — and whatever the budget would not evict, it
/// kept.
class PlaybackPrerenderScheduler {
  PlaybackPrerenderScheduler({
    required this.pictures,
    required this.resolveCut,
    this.room,
    this.afterFrameCached,
    this.beforeCompose,
    this.idleDelay = const Duration(milliseconds: 400),
  });

  /// What a frame's picture is, where the screen looks for it — what is
  /// made, what [has] counts, and what a picture that threw is remembered by.
  final PlaybackPictures pictures;
  final Cut? Function(CutId cutId) resolveCut;

  /// Null = there is room for everything (a test that fills no budget).
  final PictureRoom? room;

  /// Called after each composited frame (budget enforcement hook).
  final void Function()? afterFrameCached;

  /// Fills what a frame's composite reads from OUTSIDE the cel store before
  /// the frame is composed — a movie kept as a reference is decoded here, so
  /// a warmed frame holds its picture and the green bar means what it says
  /// (「초록 바는 지금 그림에 쓰는 그 캐시와 예산이다」).
  final Future<void> Function(Cut cut, int frameIndex)? beforeCompose;

  final Duration idleDelay;

  final ValueNotifier<PrerenderProgress> _progress = ValueNotifier(
    PrerenderProgress.none,
  );
  ValueListenable<PrerenderProgress> get progress => _progress;

  final ValueNotifier<int> _landings = ValueNotifier<int>(0);

  /// Ticks each time a picture lands — what a view that shows playback's
  /// pictures repaints on.
  Listenable get landings => _landings;

  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  /// Ticks whenever the answer a run that WAITS is waiting for may have
  /// changed: a picture landed, a picture was given up on, or the walk came
  /// to rest ([isResting]). ↩️A waiting run looked again on [landings] and
  /// on [progress] — and progress is a value: a walk that rests on the same
  /// count twice changes nothing and tells nobody, which is a run put on a
  /// frame of a film that is all made.
  Listenable get changes => _changes;

  /// Whether the walk rests: everything wanted is there, or no more fits
  /// and what is held is the window. False from the moment it is woken —
  /// it has not looked yet.
  bool get isResting => _resting != null;

  FrameDemand? _demand;

  /// What is being followed — the order the budget lets go against.
  FrameDemand? get demand => _demand;

  /// How long making a picture has been taking: a running mean over the
  /// pictures that landed, zero before the first.
  Duration get composeTime => _composeTime;
  Duration _composeTime = Duration.zero;

  int _generation = 0;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Pending while a walk has something to do; null while it rests or
  /// nothing is followed.
  Completer<void>? _busy;

  /// Completes when the walk rests — everything wanted is there, or no
  /// more fits — or is cancelled (test hook).
  Future<void> get idle => _busy?.future ?? Future<void>.value();

  void _settle() {
    final busy = _busy;
    _busy = null;
    busy?.complete();
  }

  /// Whether every one of [shown] is there to show — or can never be: a
  /// picture whose making throws is not waited for.
  bool has(List<DemandedPicture> shown) => _firstMissing(shown) == null;

  /// ⛔A picture that already threw at this exact content is not missing:
  /// nothing about it changed, and the open blocks — so it is not paid for
  /// again ([PlaybackPictures.failed]).
  DemandedPicture? _firstMissing(List<DemandedPicture> shown) {
    for (final picture in shown) {
      if (!pictures.has(picture) && !pictures.failed(picture)) {
        return picture;
      }
    }
    return null;
  }

  /// Warms one cut, playhead-outward from [aroundFrameIndex] — and then,
  /// when [followedByCutId] names a next cut, that cut start-to-end
  /// ([StandingDemand], where the order and its reasons are).
  void requestWarmCut({
    required CutId cutId,
    int aroundFrameIndex = 0,
    CutId? followedByCutId,
  }) {
    final cut = resolveCut(cutId);
    if (cut == null) {
      return;
    }
    final next = followedByCutId == null
        ? null
        : resolveCut(followedByCutId);
    follow(
      StandingDemand(
        cutId: cutId,
        // ⑯ / B1: the SHARED law ([cutWarmFrameCount]) — the warm reaches
        // what was AUTHORED, not just the conte length, and the runway
        // past the cut end takes drawings like any other frame.
        frameCount: cutWarmFrameCount(cut),
        around: aroundFrameIndex,
        nextCutId: next == null ? null : followedByCutId,
        nextFrameCount: next == null ? 0 : cutWarmFrameCount(next),
        resolveCut: resolveCut,
      ),
    );
  }

  /// Follows [demand] from here on, in place of whatever was followed.
  void follow(FrameDemand demand) {
    final generation = ++_generation;
    _demand = demand;
    _startOver = false;
    _progress.value = PrerenderProgress(cached: 0, total: demand.length);
    _busy ??= Completer<void>();
    _flushPendingWaits();
    wake();
    unawaited(_run(generation, demand));
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

  /// Outstanding gate/yield waits, cancellable as a group: [cancel],
  /// [follow] and [dispose] flush them so a parked walk resumes at once,
  /// sees its stale generation and exits — no timer outlives the scheduler
  /// (widget tests assert exactly that at teardown).
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

  /// A walk that rests — it has nothing to make, or no room to make it in —
  /// waits here for something to change. No timer: a rest can last as long
  /// as the playhead stands.
  Completer<void>? _resting;

  bool _startOver = false;

  /// Something the walk rests on has moved — the playhead, a picture let
  /// go, the room there is — so it looks again. [fromTheStart] when what it
  /// had walked over may no longer be there: the pictures themselves
  /// changed under it.
  void wake({bool fromTheStart = false}) {
    if (fromTheStart) {
      _startOver = true;
    }
    final resting = _resting;
    if (resting == null) {
      return;
    }
    _resting = null;
    // Busy from here, not from when the walk next runs: [idle] asked right
    // after a wake waits for the walk it woke.
    _busy ??= Completer<void>();
    resting.complete();
  }

  Future<void> _rest(int generation) {
    if (_isStale(generation)) {
      return Future<void>.value();
    }
    _settle();
    final resting = _resting = Completer<void>();
    // Told once it rests in every sense: whoever hears it may wake it.
    _changes.value += 1;
    return resting.future;
  }

  void cancel() {
    _generation += 1;
    _demand = null;
    _progress.value = PrerenderProgress.none;
    _flushPendingWaits();
    wake();
    _settle();
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _demand = null;
    _flushPendingWaits();
    wake();
    _settle();
    _progress.dispose();
    _landings.dispose();
    _changes.dispose();
  }

  /// How many steps a walk passes over before it lets interactive work in:
  /// a step that is already there costs a lookup, and a window is hundreds
  /// of them.
  static const int _walkBurst = 32;

  Future<void> _run(int generation, FrameDemand demand) async {
    // How many frames, on from where the walk starts, are there.
    var reached = 0;
    // What the pictures of those frames weigh, each part once: what a
    // window that is still filling is measured by.
    var walkedBytes = 0;
    final weighed = <Object>{};
    var startedAhead = 0;
    while (true) {
      if (demand.yieldsToEditing) {
        await _idleGate(generation);
      }
      if (_isStale(generation)) {
        return;
      }
      final length = demand.length;
      if (length <= 0) {
        _progress.value = PrerenderProgress.none;
        await _rest(generation);
        continue;
      }
      // Where the walk starts: the playhead, or — where the clock will not
      // wait — as far ahead of it as a picture takes to make.
      final lead = math.min(demand.leadFor(_composeTime), length - 1);
      List<DemandedPicture>? at(int index) =>
          index < length ? demand.picturesAt((lead + index) % length) : null;

      final moved = demand.advanced();
      if (moved > 0 && reached > 0) {
        final left = math.max(0, reached - moved);
        walkedBytes = walkedBytes * left ~/ reached;
        reached = left;
      }
      // The frame the walk starts on is asked again every time: it is the
      // one about to be shown, and a picture let go from under it (memory
      // pressure, a borrowed line) must not be taken as still there. A walk
      // that starts somewhere else has walked over other frames.
      if (_startOver ||
          lead != startedAhead ||
          (reached > 0 && !has(at(0) ?? const []))) {
        _startOver = false;
        startedAhead = lead;
        reached = 0;
      }
      if (reached == 0) {
        walkedBytes = 0;
        weighed.clear();
      }

      DemandedPicture? missing;
      var ended = false;
      for (var burst = 0; burst < _walkBurst; burst += 1) {
        final shown = at(reached);
        if (shown == null) {
          ended = true;
          break;
        }
        missing = _firstMissing(shown);
        if (missing != null) {
          break;
        }
        if (shown.isNotEmpty) {
          walkedBytes += pictures.weighNew(shown.first, weighed);
        }
        reached += 1;
      }
      if (missing == null && !ended) {
        // A burst's worth walked over: let interactive work in, walk on.
        await _wait(Duration.zero);
        continue;
      }
      if (missing == null) {
        // Everything wanted is there.
        _progress.value = PrerenderProgress(cached: reached, total: reached);
        await _rest(generation);
        continue;
      }
      final pictureBytes = pictures.bytesToMake(missing);
      final step = (lead + reached) % length;
      final madeRoom =
          room?.makeRoomFor(bytes: pictureBytes, step: step) ?? true;
      // 🚨THE PICTURE UNDER THE PLAYHEAD IS MADE WHATEVER THE ROOM. It is the
      // one a screen is about to show and the one a run that waits is
      // waiting for: an allowance with no room for it — every picture held
      // is on a screen — would stand that run for good. It is one picture.
      if (!madeRoom && step != 0) {
        // No more fits: what is held is the window.
        _progress.value = PrerenderProgress(cached: reached, total: reached);
        await _rest(generation);
        continue;
      }
      _progress.value = PrerenderProgress(
        cached: reached,
        total: _expected(length, reached: reached, walkedBytes: walkedBytes),
      );
      final landed = await _compose(generation, demand, missing);
      if (_isStale(generation)) {
        return;
      }
      if (!landed) {
        // Interrupted — the frame waits behind the idle gate and is made
        // when quiet returns — or it threw, and the record passes it. The
        // yield keeps a compose that keeps coming back empty from spinning.
        // A picture that threw will not come: a run waiting for it goes on.
        _changes.value += 1;
        await _wait(Duration.zero);
        continue;
      }
      afterFrameCached?.call();
      _landings.value += 1;
      _changes.value += 1;
      // Yield so interactive work interleaves between pictures.
      await _wait(Duration.zero);
    }
  }

  /// How many frames the walk expects to get there: all [length] of them,
  /// or — going by what the ones walked so far weigh — as many as the room
  /// holds.
  int _expected(int length, {required int reached, required int walkedBytes}) {
    final allowed = room?.bytes;
    if (allowed == null || walkedBytes <= 0 || reached <= 0) {
      return length;
    }
    final fitting = (reached * allowed) ~/ walkedBytes;
    return math.min(length, math.max(fitting, reached + 1));
  }

  /// Makes [picture]; true when it landed. False when it was interrupted
  /// or threw.
  Future<bool> _compose(
    int generation,
    FrameDemand demand,
    DemandedPicture picture,
  ) async {
    final cut = picture.cut;
    final frameIndex = picture.frameIndex;
    final watch = Stopwatch()..start();
    // 🚨ONE FRAME'S FAILURE IS ONE FRAME'S. A picture reads cel STORAGE, so
    // a cel whose bytes are unreachable throws from in here — and this
    // future is nobody's to await, so a throw used to abandon the whole
    // walk: progress froze where it stopped and every later frame was never
    // warmed. Give up on the frame, keep the walk.
    final bool landed;
    try {
      await beforeCompose?.call(cut, frameIndex);
      if (_isStale(generation)) {
        return false;
      }
      landed = await pictures.make(
        picture,
        shouldAbort: () =>
            _isStale(generation) ||
            (demand.yieldsToEditing && !_isQuietNow()),
      );
    } catch (error, stack) {
      pictures.noteFailure(picture);
      // Skipping the frame is right; hiding WHY is not. The failure reaches
      // the framework's error channel rather than vanishing, so a
      // permanently unreachable cel is diagnosable instead of showing up
      // only as a walk that never finishes. The record above is what keeps
      // that report to once per content state instead of once per stroke.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playback prerender',
          context: ErrorDescription(
            'warming cut ${cut.id.value} frame $frameIndex',
          ),
        ),
      );
      return false;
    }
    if (brushLabProfile) {
      // ignore: avoid_print — BRUSH_LAB_PROFILE-armed builds only.
      print(
        '[lab-warm] f=$frameIndex ${watch.elapsedMilliseconds}ms'
        '${landed ? '' : ' INTERRUPTED'}',
      );
    }
    if (!landed) {
      return false;
    }
    final took = watch.elapsed;
    _composeTime = _composeTime == Duration.zero
        ? took
        : (_composeTime * 3 + took) ~/ 4;
    return true;
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
