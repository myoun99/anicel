import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';

/// 🚨THE GHOST OWNER ID IS WHAT LETS A REDERIVE FIND ITS OWN GHOSTS.
///
/// A run behaviour stores no ghost entries: `rederiveRunBehaviors` wipes
/// and re-synthesizes them after every timeline edit, and it tells its own
/// ghosts apart from anybody else's by the marker stamped on them. Two
/// behaviours on the SAME run — one per side — must therefore never mint
/// the same id, or a rederive of one wipes the other's.
///
/// The round trip is the other half: these live in the project file, and a
/// spec that reads back as something else is a run that re-arranges itself
/// on load.
void main() {
  FrameId frame(String value) => FrameId(value);

  TimelineRunBehavior behavior({
    String anchor = 'f1',
    TimelineRunEdgeSide side = TimelineRunEdgeSide.end,
    TimelineRunEdgeMode mode = TimelineRunEdgeMode.hold,
    String? patternAnchor,
  }) => TimelineRunBehavior(
    anchorFrameId: frame(anchor),
    side: side,
    mode: mode,
    patternAnchorFrameId: patternAnchor == null ? null : frame(patternAnchor),
  );

  group('the ghost owner id', () {
    test('names the run AND the side, so the two edges of one run own '
        'different ghosts', () {
      final start = behavior(side: TimelineRunEdgeSide.start);
      final end = behavior(side: TimelineRunEdgeSide.end);
      expect(start.ghostOwnerId, isNot(end.ghostOwnerId));
      expect(start.ghostOwnerId, 'f1:start');
      expect(end.ghostOwnerId, 'f1:end');
    });

    test('does NOT depend on the mode or the pattern — the same edge keeps '
        'its ghosts when the user flips hold to repeat', () {
      final held = behavior(mode: TimelineRunEdgeMode.hold);
      final repeated = behavior(
        mode: TimelineRunEdgeMode.repeat,
        patternAnchor: 'f9',
      );
      expect(held.ghostOwnerId, repeated.ghostOwnerId);
    });

    test('different runs own different ghosts', () {
      expect(
        behavior(anchor: 'f1').ghostOwnerId,
        isNot(behavior(anchor: 'f2').ghostOwnerId),
      );
    });
  });

  group('the round trip', () {
    test('a plain hold comes back the same', () {
      final original = behavior(
        side: TimelineRunEdgeSide.start,
        mode: TimelineRunEdgeMode.hold,
      );
      expect(TimelineRunBehavior.fromJson(original.toJson()), original);
    });

    test('a selection-scoped repeat keeps its pattern anchor', () {
      final original = behavior(
        mode: TimelineRunEdgeMode.repeat,
        patternAnchor: 'f7',
      );
      final back = TimelineRunBehavior.fromJson(original.toJson());
      expect(back, original);
      expect(back.patternAnchorFrameId, frame('f7'));
    });

    test('a whole-run repeat writes NO pattern key, and reads back as one', () {
      final original = behavior(mode: TimelineRunEdgeMode.repeat);
      expect(
        original.toJson().containsKey('patternAnchor'),
        isFalse,
        reason:
            'null means "the whole run" — writing it would be a second '
            'way to say the same thing',
      );
      expect(
        TimelineRunBehavior.fromJson(original.toJson()).patternAnchorFrameId,
        isNull,
      );
    });
  });

  group('the enums refuse what they do not know', () {
    test('a side and a mode round-trip by name', () {
      for (final side in TimelineRunEdgeSide.values) {
        expect(TimelineRunEdgeSide.fromJson(side.toJson()), side);
      }
      for (final mode in TimelineRunEdgeMode.values) {
        expect(TimelineRunEdgeMode.fromJson(mode.toJson()), mode);
      }
    });

    test('an unknown value THROWS rather than picking a default', () {
      // A silent default here is a run that quietly behaves differently
      // from the one that was saved.
      expect(
        () => TimelineRunEdgeSide.fromJson('middle'),
        throwsFormatException,
      );
      expect(() => TimelineRunEdgeSide.fromJson(null), throwsFormatException);
      expect(
        () => TimelineRunEdgeMode.fromJson('bounce'),
        throwsFormatException,
      );
    });
  });

  group('equality', () {
    test('every field counts', () {
      expect(behavior(), behavior());
      expect(behavior(), isNot(behavior(anchor: 'f2')));
      expect(behavior(), isNot(behavior(side: TimelineRunEdgeSide.start)));
      expect(behavior(), isNot(behavior(mode: TimelineRunEdgeMode.repeat)));
      expect(behavior(), isNot(behavior(patternAnchor: 'f3')));
    });

    test('equal specs hash the same, so a set holds one of them', () {
      expect({behavior(), behavior()}.length, 1);
    });
  });
}
