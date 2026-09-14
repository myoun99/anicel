import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';

import '../helpers/run_edge_fixtures.dart';

/// 🚨A GHOST NAMES THE EDGE THAT DERIVED IT — SIDE AND MODE — AND A BLOCK
/// NAMES THE PROPERTY IT CARRIES (F-134).
///
/// A run edge property stores no ghost entries: `rederiveRunBehaviors` wipes
/// and re-synthesizes them after every timeline edit, and the checks that
/// ask "is this ghost MINE" (a repeat's default pattern taking its own
/// front hold or rear hold along, UI-R13 #5) read the stamp on the entry.
/// They need no run in it: two edges' ghosts only touch when their sides
/// differ.
///
/// The round trip is the other half: marks and stamps live in the project
/// file, and one that reads back as something else is a run that
/// re-arranges itself on load.
void main() {
  group('the ghost stamp', () {
    test('names the side AND the mode', () {
      expect(startHoldGhost, isNot(endHoldGhost));
      expect(startHoldGhost, isNot(startRepeatGhost));
      expect(
        const TimelineRunEdgeGhost(
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.hold,
        ),
        endHoldGhost,
      );
    });

    test('a neighbour\'s hold tail that reaches a run\'s start is an END '
        'ghost — the run\'s own repeat does not take it into its pattern', () {
      // ⛔The lead-in test is `ghostOf == start hold`, not `ghost`: A's end
      // hold fills up to B's start, and a default pattern that took any
      // abutting ghost along would cycle A's drawing after B. B's own start
      // hold is what makes the check run at all — and holds apply in run
      // order, so A's tail has already taken the room it would fill.
      final layer = Layer(
        id: const LayerId('l'),
        name: 'L',
        frames: [
          for (final id in ['a', 'b'])
            Frame(id: FrameId(id), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(
            FrameId('a'),
            length: 1,
            endEdge: holdMark,
          ),
          4: const TimelineExposure.drawing(
            FrameId('b'),
            length: 1,
            startEdge: holdMark,
            endEdge: repeatMark,
          ),
        },
      );

      final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
      expect(derived.timeline[1]!.ghostOf, endHoldGhost);
      expect(derived.timeline[1]!.length, 3, reason: 'A holds up to B');
      for (final index in [5, 6, 7]) {
        expect(
          derived.timeline[index]!.frameId,
          const FrameId('b'),
          reason: 'B cycles itself alone at $index',
        );
        expect(derived.timeline[index]!.ghostOf, endRepeatGhost);
      }
    });
  });

  group('the round trip', () {
    test('every kind of mark comes back the same', () {
      for (final mark in [holdMark, repeatMark, repeatBoundMark, boundMark]) {
        expect(TimelineRunEdgeMark.fromJson(mark.toJson()), mark);
      }
    });

    test('none writes NO key on its entry, and reads back as none', () {
      const plain = TimelineExposure.drawing(FrameId('a'), length: 2);
      final json = plain.toJson();
      expect(json.containsKey('startEdge'), isFalse);
      expect(json.containsKey('endEdge'), isFalse);
      expect(json.containsKey('ghostOf'), isFalse);
      final back = TimelineExposure.fromJson(json);
      expect(back.startEdge, TimelineRunEdgeMark.none);
      expect(back.endEdge, TimelineRunEdgeMark.none);
      expect(back.ghost, isFalse);
    });

    test('an entry\'s marks and a ghost\'s stamp ride its JSON', () {
      const carrier = TimelineExposure.drawing(
        FrameId('a'),
        length: 2,
        startEdge: holdMark,
        endEdge: repeatBoundMark,
      );
      expect(TimelineExposure.fromJson(carrier.toJson()), carrier);

      const ghost = TimelineExposure.drawing(
        FrameId('a'),
        length: 3,
        ghostOf: startRepeatGhost,
      );
      final back = TimelineExposure.fromJson(ghost.toJson());
      expect(back, ghost);
      expect(back.ghost, isTrue);
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
      expect(repeatMark, const TimelineRunEdgeMark(mode: TimelineRunEdgeMode.repeat));
      expect(repeatMark, isNot(holdMark));
      expect(repeatMark, isNot(repeatBoundMark));
      expect(TimelineRunEdgeMark.none, isNot(boundMark));
      expect(endHoldGhost, isNot(endRepeatGhost));

      const plain = TimelineExposure.drawing(FrameId('a'), length: 2);
      expect(plain, isNot(plain.copyWith(endEdge: holdMark)));
      expect(plain, isNot(plain.copyWith(startEdge: holdMark)));
    });

    test('equal marks and stamps hash the same', () {
      final sameMark = TimelineRunEdgeMark.fromJson(repeatMark.toJson());
      expect(identical(sameMark, repeatMark), isFalse, reason: 'LIVENESS');
      expect(sameMark, repeatMark);
      expect(sameMark.hashCode, repeatMark.hashCode);

      final sameGhost = TimelineRunEdgeGhost.fromJson(endHoldGhost.toJson());
      expect(identical(sameGhost, endHoldGhost), isFalse, reason: 'LIVENESS');
      expect(sameGhost, endHoldGhost);
      expect(sameGhost.hashCode, endHoldGhost.hashCode);
    });
  });
}
