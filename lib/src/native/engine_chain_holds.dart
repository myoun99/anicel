import 'package:gpu_engine/gpu_engine.dart';

import '../core/lru.dart';

/// 🚨★WHAT A FRAME'S CHAINS PUT, HELD ON THE ENGINE (folder holding, 관제
/// 2026-11-08 22:14 — the canvas's nodes held under and over its pen and
/// the frames' made ahead, one hold): the plans' chains keep what they put
/// in one [GpuHeldChains] under a number for each picture a chain shows
/// ([idOf]), so a step of a stroke above a blurred folder, or a frame made
/// ahead of the same folder, runs none of its chain again.
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
// ⏳Given its room by the playback line where the frames' pictures move onto
// the engine (flip lane ⓑ): the census reads it there, beside them.
final class EngineChainHolds {
  /// Holds fitting what [room] answers, asked each time they fit.
  EngineChainHolds({required int Function() room}) : _room = room;

  /// The hold the plans name ([GpuPlan.chainHeld]).
  final GpuHeldChains held = GpuHeldChains();

  final int Function() _room;

  late final Lru<Object, _Hold> _holds = Lru(
    limit: _room,
    costOf: (hold) => hold.bytes,
    letGo: (_, hold) => held.letGo(hold.id),
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
  /// past the room; one that alone does not fit is let go of.
  void settle() {
    for (final MapEntry(:key, value: hold) in _asked.entries) {
      hold.bytes = held.bytesOf(hold.id);
      if (hold.bytes > _room()) {
        held.letGo(hold.id);
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
    for (final hold in [..._holds.values, ..._asked.values]) {
      held.letGo(hold.id);
    }
    _holds.clear();
    _asked.clear();
  }

  /// Lets go of every hold and frees the engine's.
  void free() {
    clear();
    held.free();
  }
}

/// A number the engine holds a chain's put under, and what it weighed
/// when last settled.
final class _Hold {
  _Hold(this.id);

  final int id;
  int bytes = 0;
}
