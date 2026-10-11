import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/cubic_curve.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/position_path.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// I-89 ④ — the path a position walks in space, After Effects' spatial
/// interpolation: a key is a corner unless it is made a curve — smooth
/// through it as its neighbours lay it, or along a handle the hand placed,
/// the other side its mirror — and a segment is walked by distance along
/// the path, at the pace its keys' sides give.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  void expectNear(Offset actual, Offset expected) {
    expect(actual.dx, closeTo(expected.dx, 1e-9), reason: 'x');
    expect(actual.dy, closeTo(expected.dy, 1e-9), reason: 'y');
  }

  group('the cubic', () {
    test('is the Bernstein cubic over its four values', () {
      expect(cubicAt(0, 2, 7, -3, 5), 2);
      expect(cubicAt(1, 2, 7, -3, 5), 5);
      expect(cubicAt(0.25, 0, 1, 0, 0), closeTo(3 * 0.75 * 0.75 * 0.25, 1e-15));
      expect(cubicAt(0.25, 0, 0, 1, 0), closeTo(3 * 0.75 * 0.25 * 0.25, 1e-15));
      expect(cubicAt(0.25, 0, 0, 0, 1), closeTo(0.25 * 0.25 * 0.25, 1e-15));
    });

    test('with its controls on its ends it is the line, in the spelling '
        'every straight pin was written on', () {
      const from = Offset(0.1, 0.2);
      const to = Offset(10.7, -3.3);
      final walk = CubicWalk(from, from, to, to);
      for (final s in [0.0, 0.3, 0.7, 1.0]) {
        expect(
          walk.at(s),
          Offset(
            from.dx + (to.dx - from.dx) * s,
            from.dy + (to.dy - from.dy) * s,
          ),
        );
      }
    });

    test('a bent one is walked by distance: so much of the way is so much '
        'of its length, end to end', () {
      const from = Offset.zero;
      const leaving = Offset(0, 90);
      const arriving = Offset(30, 90);
      const to = Offset(100, 0);
      Offset curve(double u) => Offset(
        cubicAt(u, from.dx, leaving.dx, arriving.dx, to.dx),
        cubicAt(u, from.dy, leaving.dy, arriving.dy, to.dy),
      );
      // The curve's length up to each of its points, measured on its own,
      // finely.
      const fine = 20000;
      final points = [for (var k = 0; k <= fine; k++) curve(k / fine)];
      final lengths = <double>[0];
      for (var k = 1; k <= fine; k++) {
        lengths.add(lengths.last + (points[k] - points[k - 1]).distance);
      }
      double shareOfLength(Offset point) {
        var nearest = 0;
        for (var k = 1; k <= fine; k++) {
          if ((points[k] - point).distance <
              (points[nearest] - point).distance) {
            nearest = k;
          }
        }
        return lengths[nearest] / lengths.last;
      }

      expect(
        shareOfLength(curve(0.5)),
        isNot(closeTo(0.5, 0.05)),
        reason: '⛔전제: the curve\'s own parameter does not pace it evenly',
      );
      final walk = CubicWalk(from, leaving, arriving, to);
      for (final s in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        expect(shareOfLength(walk.at(s)), closeTo(s, 0.001), reason: 's $s');
      }
      expectNear(walk.at(0), from);
      expectNear(walk.at(1), to);
    });
  });

  group('a key\'s path in a file', () {
    test('a corner says nothing, a smooth key 「auto」, a placed handle its '
        'tangent — and each reads back as itself', () {
      expect(KeyPath.straight.toJson(), isNull);
      expect(KeyPath.fromJson(null), same(KeyPath.straight));
      expect(KeyPath.auto.toJson(), 'auto');
      expect(KeyPath.fromJson('auto'), same(KeyPath.auto));
      final handled = HandledPath(p(3, -4));
      expect(handled.toJson(), {
        'tangent': {'x': 3.0, 'y': -4.0},
      });
      expect(KeyPath.fromJson(handled.toJson()), handled);
      expect(KeyPath.fromJson(handled.toJson()), isNot(HandledPath(p(3, 4))));
    });

    test('a path this build has no word for is a file it cannot read', () {
      expect(() => KeyPath.fromJson('spline'), throwsFormatException);
      expect(() => KeyPath.fromJson({'tangent': 'up'}), throwsFormatException);
    });

    test('a track writes a key\'s path only where it bends, and reads it '
        'back', () {
      final track = PropertyTrack<CanvasPoint>(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), path: KeyPath.auto),
          20: PropertyKey(p(100, 100), path: HandledPath(p(5, 6))),
        },
      );
      final json = track.toJson((value) => value.toJson());
      expect(json[0].containsKey('path'), isFalse);
      expect(json[1]['path'], 'auto');
      expect(json[2]['path'], {
        'tangent': {'x': 5.0, 'y': 6.0},
      });
      expect(
        PropertyTrack.fromJson<CanvasPoint>(
          json,
          (value) => CanvasPoint.fromJson(value! as Map<String, dynamic>),
        ),
        track,
      );
    });
  });

  group('the handle a key reaches out with', () {
    SplayTreeMap<int, PropertyKey<CanvasPoint>> keys(
      Map<int, PropertyKey<CanvasPoint>> keys,
    ) => SplayTreeMap.of(keys);

    test('a corner has none', () {
      final at = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0)),
        20: PropertyKey(p(100, 60)),
      });
      expect(keyPathHandle(at, 10, ahead: true), Offset.zero);
      expect(keyPathHandle(at, 10, ahead: false), Offset.zero);
    });

    test('a smooth key lies along the line from the key before it to the '
        'key after, reaching a third of the way to the neighbour on each '
        'side', () {
      final at = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(100, 60)),
      });
      const through = Offset(100, 60);
      final along = through / through.distance;
      expectNear(keyPathHandle(at, 10, ahead: true), along * (60 / 3));
      expectNear(keyPathHandle(at, 10, ahead: false), along * -(100 / 3));
    });

    test('the first and the last smooth key have no line to lie along, nor '
        'does one whose neighbours stand at one point', () {
      final ends = keys({
        0: PropertyKey(p(0, 0), path: KeyPath.auto),
        10: PropertyKey(p(100, 0)),
        20: PropertyKey(p(100, 60), path: KeyPath.auto),
      });
      for (final ahead in [true, false]) {
        expect(keyPathHandle(ends, 0, ahead: ahead), Offset.zero);
        expect(keyPathHandle(ends, 20, ahead: ahead), Offset.zero);
      }
      final turnBack = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(0, 0)),
      });
      expect(keyPathHandle(turnBack, 10, ahead: true), Offset.zero);
      expect(keyPathHandle(turnBack, 10, ahead: false), Offset.zero);
    });

    test('a handle the hand placed reaches its tangent ahead and its mirror '
        'behind, wherever the neighbours stand', () {
      final at = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: HandledPath(p(12, -5))),
        20: PropertyKey(p(100, 60)),
      });
      expect(keyPathHandle(at, 10, ahead: true), const Offset(12, -5));
      expect(keyPathHandle(at, 10, ahead: false), const Offset(-12, 5));
    });

    group('as the canvas draws it (3b)', () {
      final bent = keys({
        0: PropertyKey(p(0, 0), path: KeyPath.auto),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(100, 60)),
        30: PropertyKey(p(40, 60), path: HandledPath(p(12, -5))),
      });

      test('every curved key has one — its ends where the handle reaches '
          'ahead and behind; a corner has none', () {
        final knobs = keyPathKnobs(bent);
        expect([for (final knob in knobs) knob.frame], [0, 10, 30]);
        final smooth = knobs[1];
        expect(smooth.at, p(100, 0));
        // Along (100, 60) from (100, 0): 60 / 3 ahead, 100 / 3 behind.
        final along = const Offset(100, 60) / const Offset(100, 60).distance;
        expectNear(
          Offset(smooth.ahead.x, smooth.ahead.y),
          const Offset(100, 0) + along * 20,
        );
        expectNear(
          Offset(smooth.behind.x, smooth.behind.y),
          const Offset(100, 0) - along * (100 / 3),
        );
        expect(knobs[2].ahead, p(52, 55));
        expect(knobs[2].behind, p(28, 65));
      });

      test('a smooth end key\'s has no length: it stands on its key, where '
          'the hand pulls it out from', () {
        final end = keyPathKnobs(bent).first;
        expect(end.ahead, p(0, 0));
        expect(end.behind, p(0, 0));
      });

      test('only the frames the path is drawn for', () {
        expect(
          [for (final knob in keyPathKnobs(bent, from: 5, to: 30)) knob.frame],
          [10, 30],
        );
        expect(
          [for (final knob in keyPathKnobs(bent, from: 0, to: 10)) knob.frame],
          [0, 10],
        );
        expect(keyPathKnobs(bent, from: 11, to: 29), isEmpty);
      });
    });
  });

  group('a layer\'s or the camera\'s position walks the path', () {
    TransformTrack moving(Map<int, PropertyKey<CanvasPoint>> keys) =>
        TransformTrack.empty().copyWith(position: PropertyTrack(keys: keys));

    CanvasPoint at(TransformTrack track, int frame) => track
        .resolveAt(
          frameIndex: frame,
          orElse: () => TransformPose(center: p(0, 0)),
        )
        .center;

    test('between corners it is the line, to the bit as it always was', () {
      final keys = {
        0: PropertyKey(p(0, 0), outgoing: const EaseSide()),
        10: PropertyKey(p(100, 40)),
        13: PropertyKey(p(-7.3, 11.1)),
      };
      final track = moving(keys);
      for (var frame = 0; frame <= 13; frame++) {
        expect(
          at(track, frame),
          PropertyTrack(keys: keys).resolveAt(
            frameIndex: frame,
            orElse: () => p(0, 0),
            space: pointKeySpace,
          ),
          reason: 'frame $frame',
        );
      }
    });

    test('a smooth key bends the segments either side of it, outward of the '
        'turn — and stands where it is', () {
      final keys = {
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(100, 100)),
      };
      final track = moving(keys);
      expect(at(track, 10), p(100, 0));
      expect(at(track, 5).y, lessThan(0), reason: 'the way in swings out');
      expect(at(track, 15).x, greaterThan(100), reason: 'and the way out');
      expect(
        at(track, 5),
        positionPathBetween(SplayTreeMap.of(keys), 0, 10)(0.5),
      );
    });

    test('a track lays a bent segment\'s walk once for every point asked '
        'along it, and the track an edit leaves lays its own', () {
      final laid = <int>[];
      final space = KeyValueSpace<CanvasPoint>(
        lerp: CanvasPoint.lerp,
        inverseLerp: CanvasPoint.inverseLerp,
        walk: (keys, from, to) {
          laid.add(from);
          return positionPathBetween(keys, from, to);
        },
      );
      CanvasPoint along(PropertyTrack<CanvasPoint> track, int frame) =>
          track.resolveAt(
            frameIndex: frame,
            orElse: () => p(0, 0),
            space: space,
          );
      final track = PropertyTrack(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), path: KeyPath.auto),
          20: PropertyKey(p(100, 100)),
        },
      );
      final first = [
        for (var frame = 1; frame < 10; frame++) along(track, frame),
      ];
      expect(laid, [0], reason: 'nine points, one walk');
      along(track, 15);
      expect(laid, [0, 10], reason: 'the next segment lays its own');
      expect(along(track, 5), first[4]);
      expect(laid, [0, 10], reason: 'read again, not laid again');

      final edited = track.withKey(10, p(100, -60));
      expect(edited.keyAt(10)!.path, KeyPath.auto, reason: '⛔전제');
      expect(
        along(edited, 5),
        positionPathBetween(SplayTreeMap.of(edited.keys), 0, 10)(0.5),
      );
      expect(laid, [0, 10, 0]);
    });

    test('a bent segment keeps the pace its keys\' sides give: it is as far '
        'along its path as the line would be along the line', () {
      const ease = EaseSide(speed: 0, influence: 0.6);
      final bent = {
        0: PropertyKey(p(0, 0), outgoing: ease),
        10: PropertyKey(p(100, 0), incoming: ease, path: HandledPath(p(0, 40))),
        20: PropertyKey(p(100, 100)),
      };
      final line = {
        for (final entry in bent.entries)
          entry.key: entry.value.copyWith(path: KeyPath.straight),
      };
      final progress = CanvasPoint.inverseLerp(
        p(0, 0),
        p(100, 0),
        at(moving(line), 3),
      );
      expect(progress, isNot(closeTo(0.3, 0.01)), reason: '⛔전제: eased');
      final expected = positionPathBetween(SplayTreeMap.of(bent), 0, 10)(
        progress,
      );
      final actual = at(moving(bent), 3);
      expect(actual.x, closeTo(expected.x, 1e-9));
      expect(actual.y, closeTo(expected.y, 1e-9));
    });
  });

  group('a key keeps its path', () {
    final track = PropertyTrack<CanvasPoint>(
      keys: {
        0: PropertyKey(p(0, 0), name: 'A'),
        10: PropertyKey(p(100, 0), path: HandledPath(p(4, 4))),
        20: PropertyKey(p(0, 0), name: 'A'),
        30: PropertyKey(p(50, 50)),
      },
    );

    test('dragged on the canvas to another value — the value is written, '
        'the curve stays', () {
      final dragged = track.withKey(10, p(80, 20));
      expect(dragged.keyAt(10)!.value, p(80, 20));
      expect(dragged.keyAt(10)!.path, HandledPath(p(4, 4)));
      expect(
        track.withKey(10, p(80, 20), path: KeyPath.straight).keyAt(10)!.path,
        KeyPath.straight,
      );
    });

    test('a name hands its path to every key it links, and a path changed '
        'under a name is a change the link hears', () {
      final linked = track.withNamedKey('A', (
        value: p(0, 0),
        incoming: KeySide.linear,
        outgoing: KeySide.linear,
        path: KeyPath.auto,
      ));
      expect(linked.keyAt(0)!.path, KeyPath.auto);
      expect(linked.keyAt(20)!.path, KeyPath.auto);
      expect(linked.keyAt(10)!.path, HandledPath(p(4, 4)));

      final curved = track.withKeyPaths(frames: {0}, curved: true)!;
      expect(movedNamedKeys(track, curved), {
        'A': (
          value: p(0, 0),
          incoming: KeySide.linear,
          outgoing: KeySide.linear,
          path: KeyPath.auto,
        ),
      });
    });

    test('the key window turns a corner into a curve its neighbours lay, '
        'leaves a curve its handle, and straightens one — nothing else '
        'moves', () {
      final curved = track.withKeyPaths(frames: {0, 10, 30}, curved: true)!;
      expect(curved.keyAt(0)!.path, KeyPath.auto);
      expect(curved.keyAt(10)!.path, HandledPath(p(4, 4)));
      expect(curved.keyAt(30)!.path, KeyPath.auto);
      expect(curved.keyAt(20)!.path, KeyPath.straight, reason: 'not chosen');
      expect(curved.keyAt(0)!.name, 'A');
      expect(curved.keyAt(0)!.value, p(0, 0));

      final straight = curved.withKeyPaths(frames: {10, 30}, curved: false)!;
      expect(straight.keyAt(10)!.path, KeyPath.straight);
      expect(straight.keyAt(30)!.path, KeyPath.straight);
      expect(straight.keyAt(0)!.path, KeyPath.auto, reason: 'not chosen');
    });

    test('a handle placed on the canvas bends that one key — its value, '
        'sides and name stay, and the link hears it', () {
      final bent = track.withKeyPath(0, HandledPath(p(3, 1)))!;
      expect(bent.keyAt(0)!.path, HandledPath(p(3, 1)));
      expect(bent.keyAt(0)!.value, p(0, 0));
      expect(bent.keyAt(0)!.name, 'A');
      expect(bent.keyAt(10)!.path, HandledPath(p(4, 4)));
      expect(movedNamedKeys(track, bent)['A']!.path, HandledPath(p(3, 1)));
      expect(track.withKeyPath(10, HandledPath(p(4, 4))), isNull);
      expect(track.withKeyPath(5, KeyPath.auto), isNull, reason: 'no key');
    });

    test('and says so when it changed nothing', () {
      expect(track.withKeyPaths(frames: {0, 20}, curved: false), isNull);
      expect(track.withKeyPaths(frames: {10}, curved: true), isNull);
      expect(track.withKeyPaths(frames: {5}, curved: true), isNull);
    });
  });
}
