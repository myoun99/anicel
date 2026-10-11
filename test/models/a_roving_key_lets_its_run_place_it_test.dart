import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/cubic_curve.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// I-89 ④ — a roving key, After Effects' Rove Across Time (I-89 ①:
/// 「위치에만, 처음 · 끝 키 시간 고정, 가운데 키는 시간을 풀어 속도를
/// 고르게」): between the keys either side that keep their time, the
/// position walks the path through it at the pace those two set, and the
/// key stands on the frame nearest where that walk passes it (Q④-6 A while
/// it is asked).
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  CanvasPoint at(PropertyTrack<CanvasPoint> track, double time) =>
      track.resolveAtTime(
        time: time,
        orElse: () => p(0, 0),
        space: positionKeySpace,
      );

  void expectNear(CanvasPoint actual, CanvasPoint expected, [String? why]) {
    expect(actual.x, closeTo(expected.x, 1e-6), reason: '$why x');
    expect(actual.y, closeTo(expected.y, 1e-6), reason: '$why y');
  }

  /// A corner at 0, a roving point 100 right of it, then 300 down to a
  /// corner at 20: 400 of way over 20 frames.
  PropertyTrack<CanvasPoint> turning({
    KeyExit leaving = KeySide.linear,
    int rovingAt = 10,
  }) => PropertyTrack(
    keys: {
      0: PropertyKey(p(0, 0), outgoing: leaving),
      rovingAt: PropertyKey(p(100, 0), roving: true),
      20: PropertyKey(p(100, 300)),
    },
  );

  group('the walk through a run', () {
    test('is even over its whole way, whatever frame the roving key '
        'stands on: it is passed a quarter of the way in', () {
      final track = turning();
      expectNear(at(track, 5), p(100, 0), 'passed at 5');
      expectNear(at(track, 10), p(100, 100), 'its frame is not its time');
      expectNear(at(track, 15), p(100, 200));
      expect(at(track, 0), p(0, 0));
      expect(at(track, 20), p(100, 300));
      expect(at(track, 25), p(100, 300));
    });

    test('keeps the pace the timed ends set over the whole way — an ease '
        'leaving the first is slow across the run, not across a segment', () {
      const ease = EaseSide(influence: 0.5, speed: 0);
      final track = turning(leaving: ease);
      final passed = track.rovingTimes(positionKeySpace)[10]!;
      expect(passed, greaterThan(5), reason: 'later than an even pace');
      expectNear(at(track, passed), p(100, 0), 'passed when its times say');
      final share = segmentProgress(
        passed / 20,
        leaving: keyHandleOf(ease, () => 0),
        arriving: linearKeyHandle,
      );
      expect(share, closeTo(0.25, 1e-9), reason: 'its share of the way');
    });

    test('holds where the first holds — none of its points is passed', () {
      final track = turning(leaving: KeyExit.hold);
      expect(at(track, 5), p(0, 0));
      expect(at(track, 19.5), p(0, 0));
      expect(at(track, 20), p(100, 300));
    });

    test('a key\'s own path bends the run as it bends a segment', () {
      final bent = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), roving: true, path: KeyPath.auto),
          20: PropertyKey(p(100, 100)),
        },
      );
      final stops = bent.rovingTimes(positionKeySpace);
      expectNear(at(bent, stops[10]!), p(100, 0), 'passed at its time');
      expect(at(bent, 5).y, lessThan(0), reason: 'the way in swings out');
    });

    test('time sees the timed keys alone: a roving key changes no '
        'neighbouring way\'s pace', () {
      PropertyTrack<CanvasPoint> track({required bool roving}) =>
          PropertyTrack(
            keys: {
              0: PropertyKey(p(0, 0)),
              if (roving) 10: PropertyKey(p(50, 50), roving: true),
              20: PropertyKey(p(100, 0), outgoing: KeySide.auto),
              30: PropertyKey(p(200, 0)),
            },
          );
      for (final time in [22.0, 25.0, 28.5]) {
        expectNear(
          at(track(roving: true), time),
          at(track(roving: false), time),
          '$time',
        );
      }
    });

    test('a key that keeps its time is still met on its frame', () {
      final track = turning();
      expect(
        track.resolveAt(
          frameIndex: 20,
          orElse: () => p(0, 0),
          space: positionKeySpace,
        ),
        p(100, 300),
      );
    });
  });

  group('when a roving key is passed', () {
    test('is its share of the way, at the pace of the run — not where it '
        'stands', () {
      for (final standing in [3, 10, 17]) {
        expect(
          turning(rovingAt: standing).rovingTimes(positionKeySpace),
          {standing: closeTo(5, 1e-9)},
        );
      }
    });

    test('a hold\'s run is placed as if it did not hold', () {
      expect(
        turning(leaving: KeyExit.hold).rovingTimes(positionKeySpace)[10],
        closeTo(5, 1e-9),
      );
    });

    test('a way with no length spreads its roving keys evenly', () {
      final still = PropertyTrack(
        keys: {
          0: PropertyKey(p(7, 7)),
          4: PropertyKey(p(7, 7), roving: true),
          5: PropertyKey(p(7, 7), roving: true),
          30: PropertyKey(p(7, 7)),
        },
      );
      final times = still.rovingTimes(positionKeySpace);
      expect(times[4], closeTo(10, 1e-9));
      expect(times[5], closeTo(20, 1e-9));
    });

    test('nothing roves on a lane whose keys walk no path', () {
      final track = PropertyTrack(
        keys: {
          0: const PropertyKey(0.0),
          10: const PropertyKey(100.0, roving: true),
          20: const PropertyKey(400.0),
        },
      );
      expect(track.rovingTimes(doubleKeySpace), isEmpty);
      expect(
        track.resolveAt(
          frameIndex: 10,
          orElse: () => 0,
          space: doubleKeySpace,
        ),
        100,
        reason: 'it keeps its time',
      );
    });
  });

  group('where a roving key stands', () {
    test('the frame nearest when it is passed — and a placed track is '
        'placed again as it is', () {
      final placed = turning().withRovingKeysSlotted(positionKeySpace);
      expect(placed.keys.keys, [0, 5, 20]);
      expect(placed.keyAt(5)!.roving, isTrue);
      expect(
        identical(placed.withRovingKeysSlotted(positionKeySpace), placed),
        isTrue,
      );
      for (final time in [3.0, 5.0, 12.5]) {
        expect(at(placed, time), at(turning(), time), reason: '$time');
      }
    });

    test('one to a frame, in their order, between the run\'s ends', () {
      final crowded = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0)),
          5: PropertyKey(p(290, 0), roving: true),
          6: PropertyKey(p(295, 0), roving: true),
          10: PropertyKey(p(300, 0)),
        },
      );
      final times = crowded.rovingTimes(positionKeySpace);
      expect(times[5]!.round(), 10, reason: '⛔전제: both nearest the end');
      expect(times[6]!.round(), 10, reason: '⛔전제');
      expect(
        crowded.withRovingKeysSlotted(positionKeySpace).keys.keys,
        [0, 8, 9, 10],
      );
    });

    test('the first and the last keep their time', () {
      final ends = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0), roving: true),
          10: PropertyKey(p(100, 0), roving: true),
          20: PropertyKey(p(100, 300), roving: true),
        },
      ).withRovingKeysSlotted(positionKeySpace);
      expect(ends.keys.keys, [0, 5, 20]);
      expect([for (final key in ends.keys.values) key.roving], [
        false,
        true,
        false,
      ]);
    });

    test('a lane walking no path roves nothing', () {
      final track = PropertyTrack(
        keys: {
          0: const PropertyKey(0.0),
          10: const PropertyKey(100.0, roving: true),
          20: const PropertyKey(400.0),
        },
      ).withRovingKeysSlotted(doubleKeySpace);
      expect(track.keyAt(10)!.roving, isFalse);
    });

    test('a transform track never holds a position key anywhere else', () {
      final transform = TransformTrack.empty().copyWith(position: turning());
      expect(transform.position.keys.keys, [0, 5, 20]);
      expect(
        TransformTrack.fromJson(transform.toJson()).position,
        transform.position,
      );
    });
  });

  group('the key window\'s write', () {
    test('frees the keys it covers but the first and the last', () {
      final still = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0)),
          20: PropertyKey(p(100, 300)),
        },
      );
      final freed = still.withKeysRoving(frames: {0, 10, 20}, roving: true)!;
      expect([for (final key in freed.keys.values) key.roving], [
        false,
        true,
        false,
      ]);
      expect(still.withKeysRoving(frames: {0, 20}, roving: true), isNull);
      expect(freed.withKeysRoving(frames: {10}, roving: true), isNull);
      expect(
        freed.withKeysRoving(frames: {10}, roving: false)!.keyAt(10)!.roving,
        isFalse,
      );
    });

    test('a name carries it, as it carries the sides and the path', () {
      final named = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), name: 'A'),
          20: PropertyKey(p(100, 300), name: 'A'),
          30: PropertyKey(p(0, 0)),
        },
      );
      final freed = named.withKeysRoving(frames: {10}, roving: true)!;
      final moved = movedNamedKeys(named, freed);
      expect(moved['A']?.roving, isTrue);
      expect(named.withNamedKeys(moved).keyAt(20)!.roving, isTrue);
    });
  });

  group('the file', () {
    test('says a key roves only where it does, and reads it back', () {
      final json = turning().toJson((value) => value.toJson());
      expect([for (final key in json) key['rove']], [null, true, null]);
      final back = PropertyTrack.fromJson(
        json,
        (value) => CanvasPoint.fromJson(value! as Map<String, dynamic>),
        roves: true,
      );
      expect(back, turning());
    });

    test('a key roving on a lane that walks no path is a file this build '
        'cannot read', () {
      final json = [
        {'index': 0, 'value': 1.0},
        {'index': 5, 'value': 2.0, 'rove': true},
        {'index': 9, 'value': 3.0},
      ];
      expect(
        () => PropertyTrack.fromJson(json, (value) => value! as double),
        throwsFormatException,
      );
      expect(
        () => TransformTrack.fromJson({'rotation': json}),
        throwsFormatException,
      );
    });
  });

  test('a walk knows how long it is', () {
    const from = Offset.zero;
    const to = Offset(30, 40);
    expect(CubicWalk(from, from, to, to).length, 50);
    final bent = CubicWalk(from, const Offset(0, 40), const Offset(30, 0), to);
    expect(bent.length, greaterThan(50));
    expect(bent.length, lessThan(40 + 30 + 40));
  });
}
