import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';

/// 🚨THE WARNING HAS TO REACH BOTH (H-crash, 유저 2026-08-27: 「세번째, 네번째
/// 변형쯤에서 말없이 앱 종료됨」 — iPhone, repeated transforms on a large cel).
///
/// `didHaveMemoryPressure` reached `BrushFrameStore` and stopped there. The
/// undo stack beside it held up to 512 MB of full-canvas surface snapshots —
/// a MOVE retains a PRE and a POST per confirm — and heard nothing. On iOS
/// that warning is the last thing before the kill.
///
/// ⚠️The unit test on `HistoryManager` cannot catch this: the manager did its
/// job the moment it was asked, and NOBODY WAS ASKING. That is why this pin
/// stands one level up, at the session that owns both.
void main() {
  test(
    'session memory pressure reaches the undo stack, not just the store',
    () async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      for (var i = 0; i < 6; i++) {
        session.historyManager.execute(_Heavy(bytes: 40 * 1024 * 1024));
      }
      expect(
        session.historyManager.retainedBytes,
        greaterThan(HistoryManager.retainedByteBudgetUnderPressure),
        reason: 'fixture premise: over the pressure cap, under the normal one',
      );

      session.respondToMemoryPressure();
      // ⚠️The relief is a spill pass now: an over-budget entry is WRITTEN
      // OUT rather than deleted, so the bytes come back a pass later. The
      // fixture's entries hold nothing that can move, so the pass stands
      // down and sheds — but it does that from a microtask.
      await session.historyManager.drainSpilling();

      expect(
        session.historyManager.retainedBytes,
        lessThanOrEqualTo(HistoryManager.retainedByteBudgetUnderPressure),
        reason: '⛔the stack heard the warning too',
      );
      expect(
        session.historyManager.canUndo,
        isTrue,
        reason: 'pressure must not cost you the undo you are about to press',
      );
    },
  );

  /// 🚨**THE SAME BUG, ONE CACHE OVER — and this one was the biggest.**
  ///
  /// `respondToMemoryPressure` DID call the playback enforcer, which is
  /// why this looked wired: the session even claimed the playback caches
  /// "re-run their budget against the shrunken world". They re-ran it
  /// against the same 600MB. Enforcing a budget nobody lowered frees
  /// nothing.
  ///
  /// ⚠️Pinned at the session for the reason the undo case above is: the
  /// enforcer does its job the moment it is asked, and the defect was that
  /// NOBODY WAS ASKING it to stand down.
  test('session memory pressure lowers the playback caches too', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      playbackCacheBudgetBytes,
      reason: 'fixture premise: the full budget before any warning',
    );

    session.respondToMemoryPressure();

    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      lessThan(playbackCacheBudgetBytes),
      reason: '⛔the largest cache in the app heard the warning',
    );
    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      greaterThanOrEqualTo(playbackCacheBudgetUnderPressureBytes),
      reason: 'and stopped at the floor rather than at zero',
    );
  });

  test('repeated warnings walk the playback budget down to the floor and no '
      'further', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    // iOS sends the warning again and again as things get worse.
    for (var i = 0; i < 12; i += 1) {
      session.respondToMemoryPressure();
    }

    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      playbackCacheBudgetUnderPressureBytes,
      reason:
          'a budget that kept halving would reach zero, and a scrub would '
          'rebuild every frame it touches',
    );
  });
}

class _Heavy implements Command, RetainedBytesCommand {
  _Heavy({required this.bytes});
  final int bytes;
  @override
  int estimatedRetainedBytes({required bool undone}) => bytes;
  @override
  String get description => 'Heavy';
  @override
  void execute() {}
  @override
  void undo() {}
}
