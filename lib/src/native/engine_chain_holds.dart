import 'dart:async';

import 'package:gpu_engine/gpu_engine.dart';

import '../core/lru.dart';

/// 🚨★WHAT A FRAME'S CHAINS PUT, HELD ON THE ENGINE (folder holding, 관제
/// 2026-11-08 22:14 — what the canvas held under and over its pen and what
/// the frames made ahead held, one kind of hold): the plans' chains keep
/// what they put in their engine's [GpuHeldChains] ([heldOf]) under a
/// number for each picture a chain shows ([idOf]), so a step of a stroke
/// above a blurred folder, or a frame made ahead of the same folder, runs
/// none of its chain again.
///
/// 🚨THE KEY IS WHAT THE CHAIN SHOWS, COMPARED WHOLE — never a hash, so no
/// other picture's put is laid for it. The four cache questions (관제 11-08
/// 22:14): ①it changes where what the chain shows does — a node with a row
/// drawn live has none, and runs each time; ②a miss runs the chain once,
/// as with no hold, and keeps its buffers, no copy; ③what is held fits the
/// [room] it is given, and one that does not fit is not kept; ④the bytes
/// are the engine's, counted where it keeps and lets go
/// ([GpuHeldChains.liveBytes]), each weighed here once its run is done
/// ([settleOnce]).
///
/// 🚨★A CANVAS HOLDS WHAT IT WAS LAID WHOLE WITH LAST, NOTHING ELSE
/// (🗣️유저 2026-10-27, Q3 = c: 「편집 중인 프레임의 위 폴더만 들고 다른
/// 프레임으로 가면 놓는다」): a canvas that stands on a frame to draw, laid
/// whole there ([settleOnce] `standing`), lets go of every hold it named
/// before and not now — the frame it stood on before, what this one showed
/// before it changed — and of every hold no canvas stands on. ⛔Not one
/// another canvas's last laying named: the conte's pictures stand on frames
/// of their own beside the canvas, on these same holds (브러시/렌더링
/// 2026-11-20). 🔬Held as least recently used to the room alone, a blur
/// value dragged 60 steps on S5_BA cut 352 held 3.6 GB of values passed
/// over, the room the frames' pictures had fell to 14 MB, and the band
/// stood at one frame (card a-blur-value-drag-grows-memory-by-gigabytes,
/// Surface, 2026-11-20). ↩️The law was laid in 841f2e275 (`holdOnly`) and
/// went with the Flutter path in 70bba515d; 관제 2026-11-20 had it put
/// back here.
// ⏳Two of these where the frames' pictures move onto the engine (flip lane
// ⓑ), each in the room the playback line gives what it stands for: the
// canvas's in the nodes' (`HeldNodesLine.bytesForNodes` — 🗣️유저 2026-10-27
// Q3 = c, the frames made ahead give way to them), the frames' made ahead
// in what the line has free (`bytesLeftFree` — F-529-Q1, no picture gives
// way to them). The census reads both there.
final class EngineChainHolds {
  /// Holds fitting what [room] answers, asked each time they fit — those
  /// of the frame a canvas stands on to draw where [ofThePensFrame].
  EngineChainHolds({
    required int Function() room,
    required this.ofThePensFrame,
  }) : _room = room;

  /// Whether these are of the frame a canvas stands on to draw
  /// (`FramePictures.heldNodes`) — not of the frames made ahead, nor of a
  /// screen that draws nothing live (`FramePictures.aheadNodes`).
  ///
  /// 🗣️유저 2026-10-27, Q3 = c: 「편집 중인 프레임의 위 폴더만」 — what is kept
  /// one to a source is that frame's to keep, and a recording into any
  /// other holds takes none of its places (`FxPluginStages._keptSteps`).
  final bool ofThePensFrame;

  /// The hold the plans of [engine] name ([GpuPlan.chainHeld]): that
  /// engine's own, made for the first of its plans to ask. What these
  /// held of the engine before went with it (🗣️gpu-canonical-store-Q11,
  /// `FramePictures.letGoWithTheirEngine`), and is let go of here if it
  /// was not yet: no plan is handed another engine's hold.
  ///
  /// ↩️⏳Till 2026-11-14 these kept one hold for their life, of whichever
  /// engine's plans had named a number in it ([GpuHeldChains] has why it
  /// is one engine's now) — 브러시/렌더링, the user asleep; theirs to
  /// overturn.
  GpuHeldChains heldOf(GpuEngine engine) {
    if (_held case final held? when identical(held.engine, engine)) {
      return held;
    }
    free();
    return _held = GpuHeldChains(engine);
  }

  GpuHeldChains? _held;

  final int Function() _room;

  late final Lru<Object, _Hold> _holds = Lru(
    limit: _room,
    costOf: (hold) => hold.bytes,
    letGo: (_, hold) => _held?.letGo(hold.id),
  );

  /// The holds asked for and not yet weighed ([settleOnce]), each with the
  /// runs still to be done of the plans that named it.
  final Map<Object, _Hold> _asked = {};

  /// The keys the plan being planned names ([idOf]).
  final Set<Object> _naming = {};

  /// The runs whose holds are still to be weighed ([settleOnce]).
  int _runsToCome = 0;

  /// What waits for them to be weighed ([onceWeighed]).
  final Set<void Function()> _onceWeighed = {};

  /// The keys named since each laying whole whose holds are still to be
  /// let go of ([_laidWhole]).
  final List<Set<Object>> _namedSince = [];

  int _next = 0;

  /// The number what [key] shows is held under: the one it has, or one of
  /// its own from now on. Nothing is let go of until the run is done
  /// ([settleOnce]): its plan names the number.
  ///
  /// 🚨A NUMBER IS GIVEN ONCE, TO ONE PICTURE (F-610, 2026-11-19): the
  /// engine tells a kept picture's tile by the number of a chain laid on
  /// it, and holds that tile for another picture told the same long after
  /// the hold was let go of (held.rs, `Plan::made_of`). ⛔One given again —
  /// counted from nothing after [clear] or [free], or a let-go one handed
  /// out — would show one picture's pixels in another.
  int idOf(Object key) {
    _naming.add(key);
    for (final named in _namedSince) {
      named.add(key);
    }
    return _asked
        .putIfAbsent(key, () => _holds.take(key) ?? _Hold(_next++))
        .id;
  }

  /// Weighs each hold the plan just planned named ([idOf]) — what its run
  /// kept — once that run is [done], at once where it is null: as the
  /// newest, in the order named, letting go of the oldest past the room;
  /// one that alone does not fit is let go of. A hold another plan named
  /// too is weighed once that one's run is done as well, and one let go of
  /// meanwhile ([clear]) is not. One of a hold freed since ([free]) kept
  /// nothing.
  ///
  /// Where the plan laid whole the frame the canvas [standing] stands on to
  /// draw, that canvas stands on what the plan named and on nothing else: a
  /// weighed hold no canvas stands on is let go of once the plan's own run
  /// is weighed, and again once every run named so far is ([onceWeighed]) —
  /// one whose run was still to come, once that run is done (브러시/렌더링
  /// 2026-11-20 ①); none named meanwhile, a step's or the next laying's.
  /// 🔬Let go of only once every run was weighed, a blur value dragged on
  /// S5_BA cut 352 still held 2.7 GB as it was let go of: the runs of a
  /// drag never all end (Surface, 2026-11-20). ⛔A step names no canvas:
  /// patched in where it changed, it would let go of the folders it did not
  /// reach and the frame draw them again (8954628b5, 2026-11-04). ⛔Nor
  /// does a frame made ahead: its holds are kept for the next one
  /// (de930c597, F-529-Q1).
  ///
  /// 🚨WEIGHED ONCE THE GPU HAS RUN IT (the-ui-thread-never-enters-the-
  /// driver B1-a, 2026-11-15): a screen's compose is handed to the engine
  /// with no one waiting for it ([GpuScreen.compose]), and what its chains
  /// kept is there once its done is told. ↩️Weighed as its plan was freed,
  /// each would weigh nothing then and be kept past the room. ⏳브러시/
  /// 렌더링, the user asleep; theirs to overturn.
  void settleOnce(Future<void>? done, {Object? standing}) {
    final named = [
      for (final key in _naming) (key: key, hold: _asked[key]!..runs += 1),
    ];
    _runsToCome += 1;
    final laid = standing == null ? null : _laidWhole(standing, named);
    _naming.clear();
    if (done == null) {
      _weigh(named, laid);
      return;
    }
    // Why it failed is its asker's to hear ([GpuScreen.compose]).
    unawaited(
      done.then(
        (_) => _weigh(named, laid),
        onError: (Object _) => _weigh(named, laid),
      ),
    );
  }

  /// Weighs what a run [named], then what was [laid] whole by it lets go.
  void _weigh(
    List<({Object key, _Hold hold})> named,
    void Function()? laid,
  ) {
    final held = _held;
    for (final (:key, :hold) in named) {
      hold.runs -= 1;
      if (hold.runs > 0 || !identical(_asked[key], hold)) {
        continue;
      }
      _asked.remove(key);
      hold.bytes = held?.bytesOf(hold.id) ?? 0;
      if (hold.bytes > _room()) {
        held?.letGo(hold.id);
      } else {
        _holds.keep(key, hold);
      }
    }
    laid?.call();
    _runsToCome -= 1;
    if (_runsToCome == 0) {
      final waiting = [..._onceWeighed];
      _onceWeighed.clear();
      for (final then in waiting) {
        then();
      }
    }
  }

  /// [canvas] laid whole naming [named]: it stands on those, and on none
  /// else it stood on — a weighed hold no canvas stands on let go of, but
  /// one named meanwhile ([idOf]) — once the run is weighed (what this
  /// gives) and once every run named so far is.
  void Function() _laidWhole(
    Object canvas,
    List<({Object key, _Hold hold})> named,
  ) {
    final own = <Object>{};
    for (final (:key, :hold) in named) {
      own.add(key);
      hold.standers.add(canvas);
    }
    final meanwhile = <Object>{};
    _namedSince.add(meanwhile);
    void standOnOwnAlone() {
      for (final key in [..._holds.keys]) {
        if (own.contains(key) || meanwhile.contains(key)) {
          continue;
        }
        final hold = _holds.peek(key)!;
        hold.standers.remove(canvas);
        _letGoUnstood(key, hold);
      }
    }

    onceWeighed(() {
      _namedSince.remove(meanwhile);
      standOnOwnAlone();
    });
    return standOnOwnAlone;
  }

  /// [canvas] stands on none of these any more — gone with its screen: a
  /// weighed hold no other canvas stands on is let go of.
  void standDown(Object canvas) {
    for (final hold in _asked.values) {
      hold.standers.remove(canvas);
    }
    for (final key in [..._holds.keys]) {
      final hold = _holds.peek(key)!;
      if (hold.standers.remove(canvas)) {
        _letGoUnstood(key, hold);
      }
    }
  }

  void _letGoUnstood(Object key, _Hold hold) {
    if (hold.standers.isEmpty) {
      _holds.take(key);
      _held?.letGo(hold.id);
    }
  }

  /// Runs [then] once every run named so far is weighed ([settleOnce]) —
  /// now, where none is to come. Asked again meanwhile, it runs once.
  void onceWeighed(void Function() then) {
    if (_runsToCome == 0) {
      then();
    } else {
      _onceWeighed.add(then);
    }
  }

  /// The bytes the holds keep — one whose run is still to be weighed as it
  /// weighed last.
  int get heldBytes =>
      _asked.values.fold(_holds.held, (bytes, hold) => bytes + hold.bytes);

  /// Lets go of the oldest past the room, where the room moved under them.
  void fit() => _holds.fit();

  /// Lets go of every hold — one whose run is still to come after it, on
  /// the engine's thread in turn.
  void clear() {
    for (final hold in [..._holds.values, ..._asked.values]) {
      _held?.letGo(hold.id);
    }
    _holds.clear();
    _asked.clear();
  }

  /// Lets go of every hold and frees the engine's. A plan that asks
  /// after is given a hold made for its engine ([heldOf]).
  void free() {
    clear();
    _held?.free();
    _held = null;
  }
}

/// A number the engine holds a chain's put under, what it weighed when
/// last settled, the runs naming it still to be done, and the canvases
/// whose last laying whole named it ([EngineChainHolds.settleOnce]).
final class _Hold {
  _Hold(this.id);

  final int id;
  int bytes = 0;
  int runs = 0;
  final Set<Object> standers = {};
}
