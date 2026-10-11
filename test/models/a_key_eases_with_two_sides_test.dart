import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart'
    show argbKeySpace, doubleKeySpace, pointKeySpace;
import 'package:flutter_test/flutter_test.dart';

/// I-89 (유저 2026-10-10: 「키 양쪽. 업계 표준인 전문 툴대로 하고싶어. 그게
/// ae고」): a key eases the segment arriving at it with its in side and the
/// one leaving it with its out side — After Effects' temporal
/// interpolation, the segment's curve the two sides' handles together.
void main() {
  double at(PropertyTrack<double> track, int frame) => track.resolveAt(
    frameIndex: frame,
    orElse: () => -1,
    space: doubleKeySpace,
  );

  double progress(KeyHandle leaving, KeyHandle arriving, double x) =>
      segmentProgress(x, leaving: leaving, arriving: arriving);

  const easyEase = (influence: 1 / 3, speed: 0.0);

  group('the segment curve', () {
    test('two straight ramps are time itself', () {
      for (final x in [0.0, 0.1, 0.25, 0.5, 0.8, 1.0]) {
        expect(
          progress(linearKeyHandle, linearKeyHandle, x),
          closeTo(x, 1e-9),
        );
      }
    });

    test('an Easy Ease on both sides is slow at both ends and even in the '
        'middle', () {
      expect(progress(easyEase, easyEase, 0.5), closeTo(0.5, 1e-9));
      expect(
        progress(easyEase, easyEase, 0.2) + progress(easyEase, easyEase, 0.8),
        closeTo(1, 1e-9),
        reason: 'the same ease both ways is symmetric',
      );
      expect(progress(easyEase, easyEase, 0.1), lessThan(0.1 / 2));
    });

    test('easing out of a key leaves it slowly, easing in reaches it '
        'slowly', () {
      expect(progress(easyEase, linearKeyHandle, 0.1), lessThan(0.1));
      expect(progress(linearKeyHandle, easyEase, 0.9), greaterThan(0.9));
    });

    test('a speed above the average starts faster than the ramp', () {
      const quick = (influence: 1 / 3, speed: 2.0);
      expect(progress(quick, linearKeyHandle, 0.05), greaterThan(0.05));
    });

    test('time runs forward even where the two influences overlap', () {
      const long = (influence: 1.0, speed: 0.0);
      var last = 0.0;
      for (var step = 0; step <= 200; step += 1) {
        final y = progress(long, long, step / 200);
        expect(y, greaterThanOrEqualTo(last - 1e-12));
        last = y;
      }
      expect(progress(long, long, 0.5), closeTo(0.5, 1e-9));
    });
  });

  group('a handle\'s point (I-89 ③)', () {
    test('leaving, a side stands its influence into the segment and its '
        'influence × speed up it; arriving, as far back from the end', () {
      void stands(KeyHandle handle, bool leaving, double x, double y) {
        final point = keyHandlePoint(handle, leaving: leaving);
        expect(point.x, closeTo(x, 1e-12));
        expect(point.y, closeTo(y, 1e-12));
      }

      stands(easyEase, true, 1 / 3, 0);
      stands(easyEase, false, 2 / 3, 1);
      const quick = (influence: 0.25, speed: 2.0);
      stands(quick, true, 0.25, 0.5);
      stands(quick, false, 0.75, 0.5);
    });

    test('read back, a point gives the handle standing there', () {
      for (final handle in [
        easyEase,
        linearKeyHandle,
        (influence: 0.5, speed: 2.0),
        (influence: 0.2, speed: -1.0),
      ]) {
        for (final leaving in [true, false]) {
          final (:x, :y) = keyHandlePoint(handle, leaving: leaving);
          final back = keyHandleAt(x, y, leaving: leaving);
          expect(back.influence, closeTo(handle.influence, 1e-12));
          expect(back.speed, closeTo(handle.speed, 1e-12));
        }
      }
    });

    test('a point past either end reads the reach a side may take: the '
        'least influence, or the whole segment', () {
      expect(
        keyHandleAt(-0.5, 0, leaving: true).influence,
        EaseSide.leastInfluence,
      );
      expect(keyHandleAt(1.5, 0, leaving: true).influence, 1);
      expect(
        keyHandleAt(1.5, 1, leaving: false).influence,
        EaseSide.leastInfluence,
      );
      expect(keyHandleAt(-0.5, 1, leaving: false).influence, 1);
    });
  });

  group('the resolver', () {
    test('a key easing in arrives slowly', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(10, 100, incoming: const EaseSide());
      expect(at(track, 5), greaterThan(50));
      expect(at(track, 9), greaterThan(90));
      expect(at(track, 10), 100);
    });

    test('a key easing out leaves slowly', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0, outgoing: const EaseSide())
          .withKey(10, 100);
      expect(at(track, 1), lessThan(10));
      expect(at(track, 5), lessThan(50));
    });

    test('a hold out of a key freezes whatever the next key eases in '
        'with', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0, outgoing: KeyExit.hold)
          .withKey(10, 100, incoming: const EaseSide());
      expect(at(track, 9), 0);
      expect(at(track, 10), 100);
    });

    test('an auto key at a peak stops level there', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(
            10,
            100,
            incoming: KeySide.auto,
            outgoing: KeySide.auto,
          )
          .withKey(20, 0);
      expect(at(track, 9), closeTo(at(track, 11), 1e-9));
      expect(at(track, 9), greaterThan(90), reason: 'level, not a corner');
      expect(at(track, 10), 100);
    });

    test('an auto key on an even run moves like the ramp through it', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(
            10,
            100,
            incoming: KeySide.auto,
            outgoing: KeySide.auto,
          )
          .withKey(20, 200);
      for (final frame in [3, 7, 9, 11, 14, 18]) {
        expect(at(track, frame), closeTo(frame * 10.0, 1e-6));
      }
    });

    test('an auto key past a peak never climbs over it', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(
            10,
            100,
            incoming: KeySide.auto,
            outgoing: KeySide.auto,
          )
          .withKey(20, 50);
      for (var frame = 10; frame <= 20; frame += 1) {
        expect(at(track, frame), inInclusiveRange(50, 100));
      }
      expect(at(track, 11), greaterThan(99), reason: 'level at the peak');
    });

    test('an auto key in a flat stretch keeps it flat', () {
      final track = PropertyTrack<double>()
          .withKey(0, 5)
          .withKey(10, 5, incoming: KeySide.auto, outgoing: KeySide.auto)
          .withKey(20, 5);
      for (var frame = 0; frame <= 20; frame += 1) {
        expect(at(track, frame), 5);
      }
    });

    test('a value space puts every value at 0 between two equal ones — '
        'there is no line to fall on', () {
      expect(doubleKeySpace.inverseLerp(5, 5, 9), 0);
      expect(
        pointKeySpace.inverseLerp(
          CanvasPoint(x: 3, y: 4),
          CanvasPoint(x: 3, y: 4),
          CanvasPoint(x: 9, y: 1),
        ),
        0,
      );
      expect(argbKeySpace.inverseLerp(0xFF102030, 0xFF102030, 0xFFFFFFFF), 0);
    });

    test('an auto point on an even run moves like the ramp through it', () {
      final track = PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 0, y: 0))
          .withKey(
            10,
            CanvasPoint(x: 10, y: 20),
            incoming: KeySide.auto,
            outgoing: KeySide.auto,
          )
          .withKey(20, CanvasPoint(x: 20, y: 40));
      for (final frame in [4, 9, 13]) {
        final point = track.resolveAt(
          frameIndex: frame,
          orElse: () => CanvasPoint(x: -1, y: -1),
          space: pointKeySpace,
        );
        expect(point.x, closeTo(frame.toDouble(), 1e-6));
        expect(point.y, closeTo(frame * 2.0, 1e-6));
      }
    });

    test('an auto colour on an even run moves like the ramp through it', () {
      final track = PropertyTrack<int>()
          .withKey(0, 0xFF000000)
          .withKey(
            10,
            0xFF646464,
            incoming: KeySide.auto,
            outgoing: KeySide.auto,
          )
          .withKey(20, 0xFFC8C8C8);
      expect(
        track.resolveAt(
          frameIndex: 5,
          orElse: () => 0,
          space: argbKeySpace,
        ),
        0xFF323232,
      );
    });

    test('an auto key never throws the curve past the values it joins', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(10, 10, incoming: KeySide.auto)
          .withKey(20, 1000);
      for (var frame = 0; frame <= 10; frame += 1) {
        expect(at(track, frame), inInclusiveRange(0, 10));
      }
    });

    test('an auto side at the first or last key is a straight one', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0, outgoing: KeySide.auto)
          .withKey(10, 100, incoming: KeySide.auto);
      expect(at(track, 4), closeTo(40, 1e-9));
    });
  });

  group('the file', () {
    List<Map<String, dynamic>> json(PropertyTrack<double> track) =>
        track.toJson((value) => value);

    PropertyTrack<double> read(List<Object?> json) => PropertyTrack.fromJson(
      json,
      (value) => (value! as num).toDouble(),
    );

    test('each side is written only where it is not straight', () {
      final track = PropertyTrack<double>()
          .withKey(0, 1)
          .withKey(4, 2, incoming: KeySide.auto, outgoing: KeyExit.hold)
          .withKey(
            8,
            3,
            outgoing: const EaseSide(influence: 0.75, speed: 0.5),
          );
      final written = json(track);
      expect(written[0].containsKey('in'), isFalse);
      expect(written[0].containsKey('out'), isFalse);
      expect(written[1]['in'], 'auto');
      expect(written[1]['out'], 'hold');
      expect(written[2]['out'], {
        'kind': 'ease',
        'influence': 0.75,
        'speed': 0.5,
      });
      expect(read(written), track);
    });

    test('an in side that holds is a file this build cannot read', () {
      expect(
        () => read([
          {'index': 0, 'value': 1, 'in': 'hold'},
        ]),
        throwsFormatException,
      );
    });

    test('a side it has no word for, or an ease out of range, is refused', () {
      expect(
        () => read([
          {'index': 0, 'value': 1, 'out': 'bounce'},
        ]),
        throwsFormatException,
      );
      expect(
        () => read([
          {
            'index': 0,
            'value': 1,
            'out': {'kind': 'ease', 'influence': 0, 'speed': 0},
          },
        ]),
        throwsFormatException,
      );
    });
  });

  group('writing sides', () {
    test('a value edit keeps both sides', () {
      final track = PropertyTrack<double>()
          .withKey(4, 1, incoming: KeySide.auto, outgoing: KeyExit.hold)
          .withKey(4, 2);
      expect(track.keyAt(4)!.incoming, KeySide.auto);
      expect(track.keyAt(4)!.outgoing, KeyExit.hold);
    });

    test('an edit writes the side it gives and leaves the other', () {
      final track = PropertyTrack<double>()
          .withKey(4, 1, outgoing: KeyExit.hold)
          .withKeySides(
            frames: {4},
            edit: const KeySidesEdit(
              incoming: KeySideEdit(side: EaseSide()),
            ),
          )!;
      expect(track.keyAt(4)!.incoming, const EaseSide());
      expect(track.keyAt(4)!.outgoing, KeyExit.hold);
    });

    test('a hold says nothing about the side arriving', () {
      expect(
        KeySidesEdit.hold.applyTo(
          incoming: const EaseSide(),
          outgoing: KeySide.linear,
        ),
        (incoming: const EaseSide(), outgoing: KeyExit.hold),
      );
    });

    // I-89 ②: the key window picks a side's KIND and its ease's INFLUENCE,
    // each alone — what it did not pick, it does not touch.
    test('picking the kind a side is keeps the side — its numbers too', () {
      const edit = KeySideEdit<KeySide>(side: EaseSide());
      expect(edit.applyTo(ownEase), ownEase);
      expect(edit.applyTo(KeySide.linear), const EaseSide());
      expect(
        const KeySideEdit<KeySide>(side: KeySide.auto).applyTo(ownEase),
        KeySide.auto,
      );
    });

    test('an influence keeps the speed, and is nothing to a side that does '
        'not ease', () {
      const edit = KeySideEdit<KeySide>(influence: 0.25);
      expect(
        edit.applyTo(ownEase),
        const EaseSide(influence: 0.25, speed: 0.2),
      );
      expect(edit.applyTo(KeySide.linear), KeySide.linear);
      expect(
        const KeySideEdit<KeyExit>(influence: 0.25).applyTo(KeyExit.hold),
        KeyExit.hold,
      );
    });

    test('a kind and an influence picked together: a side of another kind '
        'eases at that influence from a standstill', () {
      const edit = KeySideEdit<KeySide>(side: EaseSide(), influence: 0.6);
      expect(edit.applyTo(KeySide.linear), const EaseSide(influence: 0.6));
      expect(
        edit.applyTo(ownEase),
        const EaseSide(influence: 0.6, speed: 0.2),
      );
    });

    // I-89 ③: a graph's handle says a side's two numbers at once — how far
    // into its segment it reaches and how fast the value moves at the key.
    test('a speed keeps the influence; given both, the side takes both; '
        'neither is anything to a side that does not ease', () {
      expect(
        const KeySideEdit<KeySide>(speed: 2).applyTo(ownEase),
        const EaseSide(influence: 0.5, speed: 2),
      );
      expect(
        const KeySideEdit<KeySide>(influence: 0.2, speed: -1).applyTo(ownEase),
        const EaseSide(influence: 0.2, speed: -1),
      );
      expect(
        const KeySideEdit<KeySide>(speed: 2).applyTo(KeySide.auto),
        KeySide.auto,
      );
      expect(
        const KeySideEdit<KeyExit>(influence: 0.2, speed: 2).applyTo(
          KeyExit.hold,
        ),
        KeyExit.hold,
      );
    });

    test('a range of keys is written key by key, each keeping what the '
        'pick does not say', () {
      final track = PropertyTrack<double>()
          .withKey(0, 1, incoming: ownEase)
          .withKey(4, 2)
          .withKeySides(
            frames: {0, 4},
            edit: const KeySidesEdit(
              incoming: KeySideEdit(side: EaseSide(), influence: 0.4),
            ),
          )!;
      expect(
        track.keyAt(0)!.incoming,
        const EaseSide(influence: 0.4, speed: 0.2),
      );
      expect(track.keyAt(4)!.incoming, const EaseSide(influence: 0.4));
      expect(track.keyAt(4)!.outgoing, KeySide.linear);
    });

    test('an edit that changes no key is no write', () {
      final track = PropertyTrack<double>().withKey(0, 1, incoming: ownEase);
      expect(
        track.withKeySides(
          frames: {0},
          edit: const KeySidesEdit(incoming: KeySideEdit(side: EaseSide())),
        ),
        isNull,
      );
    });

    test('a name carries both sides to every key it links', () {
      final track = PropertyTrack<double>()
          .withKey(0, 1)
          .withKey(8, 1)
          .withKeyName(0, 'A')
          .withKeyName(8, 'A')
          .withNamedKey('A', (
            value: 5,
            incoming: const EaseSide(speed: 0.5),
            outgoing: KeySide.auto,
          ));
      for (final frame in [0, 8]) {
        expect(track.keyAt(frame)!.value, 5);
        expect(track.keyAt(frame)!.incoming, const EaseSide(speed: 0.5));
        expect(track.keyAt(frame)!.outgoing, KeySide.auto);
      }
    });
  });

  group('what a row of the key window says together (I-89 ②)', () {
    test('the kind every side is, or none where they differ', () {
      expect(
        keySidesTogether([KeySide.linear, KeySide.linear]).kind,
        KeySideKind.linear,
      );
      expect(
        keySidesTogether([const EaseSide(), ownEase]).kind,
        KeySideKind.ease,
        reason: 'an ease at 33% and one at 50% are one kind',
      );
      expect(keySidesTogether([KeySide.linear, KeyExit.hold]).kind, isNull);
    });

    test('the influence every ease takes, or none where they differ', () {
      expect(keySidesTogether([ownEase, ownEase]).influence, 0.5);
      expect(keySidesTogether([const EaseSide(), ownEase]).influence, isNull);
      expect(
        keySidesTogether([KeySide.linear, KeySide.linear]).influence,
        isNull,
        reason: 'a straight side has no influence to agree on',
      );
      expect(
        keySidesTogether([ownEase, KeySide.linear]).influence,
        isNull,
        reason: 'sides of different kinds have no influence to agree on',
      );
    });
  });
}

/// An ease of its own numbers — not AE's Easy Ease.
const ownEase = EaseSide(influence: 0.5, speed: 0.2);
