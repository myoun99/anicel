import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

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
    () {
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
}

class _Heavy implements Command, RetainedBytesCommand {
  _Heavy({required this.bytes});
  final int bytes;
  @override
  int get estimatedRetainedBytes => bytes;
  @override
  String get description => 'Heavy';
  @override
  void execute() {}
  @override
  void undo() {}
}
