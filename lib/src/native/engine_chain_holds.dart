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
/// ([settle]).
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

  /// The keys asked for since the holds last settled, and their holds.
  final Map<Object, _Hold> _asked = {};

  int _next = 0;

  /// The number what [key] shows is held under: the one it has, or one of
  /// its own from now on. Nothing is let go of until the run is done
  /// ([settle]): its plan names the number.
  int idOf(Object key) => _asked
      .putIfAbsent(key, () => _holds.take(key) ?? _Hold(_next++))
      .id;

  /// Weighs each hold asked for since the last settling — what its run
  /// kept — as the newest, in the order asked, and lets go of the oldest
  /// past the room; one that alone does not fit is let go of. One asked
  /// for of a hold freed since ([free]) kept nothing.
  void settle() {
    final held = _held;
    for (final MapEntry(:key, value: hold) in _asked.entries) {
      hold.bytes = held?.bytesOf(hold.id) ?? 0;
      if (hold.bytes > _room()) {
        held?.letGo(hold.id);
      } else {
        _holds.keep(key, hold);
      }
    }
    _asked.clear();
  }

  /// The bytes the holds keep.
  int get heldBytes => _holds.held;

  /// Lets go of the oldest past the room, where the room moved under them.
  void fit() => _holds.fit();

  /// Lets go of every hold.
  void clear() {
    for (final hold in _holds.values) {
      _held?.letGo(hold.id);
    }
    _holds.clear();
  }

  /// Lets go of every hold and frees the engine's. A plan that asks
  /// after is given a hold made for its engine ([heldOf]).
  void free() {
    clear();
    _held?.free();
    _held = null;
  }
}

/// A number the engine holds a chain's put under, and what it weighed
/// when last settled.
final class _Hold {
  _Hold(this.id);

  final int id;
  int bytes = 0;
}
