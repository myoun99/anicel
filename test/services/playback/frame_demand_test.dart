import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';

/// THE ORDER FRAMES ARE WANTED IN — the one order the warmer makes pictures
/// by and the budget lets go by (유저 2026-10-08, the playback rework).
///
/// Everything here is the order itself: which frame is at which step, and
/// the same read backwards. What the two readers do with it is theirs to
/// pin (`playback_prerender_scheduler_test`, `playback_cache_budget_test`).
void main() {
  const a = CutId('a');
  const b = CutId('b');

  Cut cutOf(CutId id) => Cut(
    id: id,
    name: id.value,
    duration: 4,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: const [],
  );

  /// The frames [demand] wants, in order, each named `cut:frame`.
  List<String> wanted(FrameDemand demand) => [
    for (var step = 0; step < demand.length; step += 1)
      for (final picture in demand.picturesAt(step)!)
        '${picture.cut.id.value}:${picture.frameIndex}',
  ];

  group('while nothing plays', () {
    StandingDemand standing({
      int frameCount = 5,
      int around = 1,
      CutId? next = b,
      int nextFrameCount = 3,
    }) => StandingDemand(
      cutId: a,
      frameCount: frameCount,
      around: around,
      nextCutId: next,
      nextFrameCount: nextFrameCount,
      resolveCut: cutOf,
    );

    test('the cut is wanted from the playhead outwards, and then the cut '
        'after it from its first frame', () {
      final demand = standing();
      expect(wanted(demand), [
        'a:1', 'a:2', 'a:0', 'a:3', 'a:4', //
        'b:0', 'b:1', 'b:2',
      ]);
      expect(demand.length, 8);
      expect(demand.picturesAt(8), isNull, reason: 'past the last step');
      expect(demand.picturesAt(-1), isNull);
    });

    test('stepOf is the same order read backwards — and null for a frame '
        'no step shows', () {
      final demand = standing();
      for (var step = 0; step < demand.length; step += 1) {
        final picture = demand.picturesAt(step)!.single;
        expect(
          demand.stepOf(picture.cut.id, picture.frameIndex),
          step,
          reason: '${picture.cut.id.value}:${picture.frameIndex}',
        );
      }
      expect(demand.stepOf(a, 5), isNull, reason: 'past the cut');
      expect(demand.stepOf(a, -1), isNull);
      expect(demand.stepOf(b, 3), isNull, reason: 'past the next cut');
      expect(demand.stepOf(const CutId('elsewhere'), 0), isNull);
    });

    test('a playhead past either end starts at the nearest frame', () {
      expect(wanted(standing(around: 99, next: null)).first, 'a:4');
      expect(wanted(standing(around: -3, next: null)).first, 'a:0');
    });

    test('a cut does not follow itself', () {
      final demand = standing(next: a);
      expect(demand.length, 5);
      expect(demand.stepOf(a, 0), 2, reason: 'its own step, not a second one');
    });

    test('the cut is read as it is NOW — an edit is a new cut, and a cut '
        'that is gone shows nothing', () {
      Cut? now = cutOf(a);
      final demand = StandingDemand(
        cutId: a,
        frameCount: 2,
        around: 0,
        resolveCut: (_) => now,
      );
      expect(identical(demand.picturesAt(0)!.single.cut, now), isTrue);

      final edited = cutOf(a);
      now = edited;
      expect(identical(demand.picturesAt(0)!.single.cut, edited), isTrue);

      now = null;
      expect(demand.picturesAt(0), isEmpty);
    });

    test('it stands still, gives way to the editor and takes no lead', () {
      final demand = standing();
      expect(demand.advanced(), 0);
      expect(demand.yieldsToEditing, isTrue);
      expect(demand.leadFor(const Duration(seconds: 3)), 0);
    });
  });

  group('while a run plays', () {
    var playhead = 0;
    var loops = true;

    setUp(() {
      playhead = 0;
      loops = true;
    });

    /// A run of five frames showing cut `a`, frame for frame.
    PlayingDemand playing({int Function(Duration)? lead}) => PlayingDemand(
      totalFrames: 5,
      loops: () => loops,
      playhead: () => playhead,
      picturesOf: (frame) => [(cut: cutOf(a), frameIndex: frame)],
      playlistFrameOf: (cutId, frameIndex) => cutId == a ? frameIndex : null,
      lead: lead,
    );

    test('a run that loops wants a lap from the playhead, round to the '
        'frame behind it', () {
      playhead = 3;
      final demand = playing();
      expect(wanted(demand), ['a:3', 'a:4', 'a:0', 'a:1', 'a:2']);
      expect(demand.picturesAt(5), isNull, reason: 'one lap is all of it');
    });

    test('a run that plays once wants only what is left of it', () {
      playhead = 3;
      loops = false;
      final demand = playing();
      expect(wanted(demand), ['a:3', 'a:4']);
      expect(demand.stepOf(a, 4), 1);
      expect(
        demand.stepOf(a, 2),
        isNull,
        reason: 'a frame behind the playhead is not shown again',
      );
    });

    test('stepOf counts on from the playhead as it stands NOW', () {
      playhead = 3;
      final demand = playing();
      expect(demand.stepOf(a, 3), 0);
      expect(demand.stepOf(a, 2), 4, reason: 'the frame just behind is last');

      playhead = 4;
      expect(demand.stepOf(a, 2), 3);
      expect(demand.stepOf(b, 0), isNull, reason: 'a cut it does not show');
      expect(demand.stepOf(a, 5), isNull, reason: 'past the run');
    });

    test('advanced says how far the playhead has moved since it was '
        'asked', () {
      playhead = 1;
      final demand = playing();
      expect(demand.advanced(), 0);

      playhead = 3;
      expect(demand.advanced(), 2);
      expect(demand.advanced(), 0, reason: 'asked again, it has not moved');

      playhead = 0;
      expect(demand.advanced(), 2, reason: '3 → 4 → 0: the lap wraps');
    });

    test('a step back in a run that plays once is a seek: everything walked '
        'is behind it', () {
      loops = false;
      playhead = 3;
      final demand = playing();
      playhead = 1;
      expect(demand.advanced(), 5);
    });

    test('the loop button pressed under a run changes what it wants', () {
      playhead = 3;
      final demand = playing();
      expect(demand.length, 5);
      loops = false;
      expect(demand.length, 2);
      expect(demand.picturesAt(2), isNull);
    });

    test('a run does not stand aside for the editor, and leads by what it '
        'is told', () {
      expect(playing().yieldsToEditing, isFalse);
      expect(playing().leadFor(const Duration(seconds: 1)), 0);
      expect(
        playing(
          lead: (composeTime) => composeTime.inMilliseconds ~/ 100,
        ).leadFor(const Duration(milliseconds: 250)),
        2,
      );
    });
  });
}
