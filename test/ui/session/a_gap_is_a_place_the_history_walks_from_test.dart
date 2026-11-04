import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/standing_place.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_places.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

class _Edit implements Command {
  @override
  String get description => 'Edit';

  @override
  void execute() {}

  @override
  void undo() {}
}

/// 🗣️F-559-Q2 (유저 2026-11-04): 「새 프로젝트 → 초기 컷 블록 복사 → 컷 뒤로
/// 이동 → 붙여넣기. 언두하고 리두하면 안 생김」 — the undo left the user in
/// the gap and the redo walked to the cut it had taken away, every press.
/// The two laws the walk (I-41) asks, each pinned on its own.
void main() {
  group('🎯an entry is made where the action left the user — a gap too', () {
    const cut = (cut: CutId('pasted'), layer: null, frame: 0);

    test('stamped in a gap, an entry made on a cut is made nowhere', () {
      StandingPlace? now = cut;
      final places = HistoryPlaces()..placeNow = () => now;
      final entry = _Edit();
      places.stamp(entry);
      expect(places.of(entry), cut, reason: '⛔전제');

      now = null;
      places.stamp(entry);
      expect(places.of(entry), isNull);
      expect(places.foundAt(entry), cut, reason: 'where it found them');
    });

    test('…and settled in one', () {
      StandingPlace? now = cut;
      final places = HistoryPlaces()..placeNow = () => now;
      final entry = _Edit();
      places.stamp(entry);
      now = null;
      places.settle();
      expect(places.of(entry), isNull);
    });
  });

  group('🎯a place whose cut is gone is nowhere to walk to — from a gap '
      'too', () {
    late EditorSessionManager session;
    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(session.dispose);
    });

    test('a gap is elsewhere from a cut that stands', () {
      final there = (
        cut: session.requireActiveCut.id,
        layer: null,
        frame: 0,
      );
      expect(session.standing.isElsewhere(there, from: null), isTrue);
    });

    test('a cut that is gone is nowhere, from a gap or a cut', () {
      const there = (cut: CutId('gone'), layer: null, frame: 0);
      final here = (cut: session.requireActiveCut.id, layer: null, frame: 0);
      expect(session.standing.isElsewhere(there, from: null), isFalse);
      expect(session.standing.isElsewhere(there, from: here), isFalse);
    });
  });
}
