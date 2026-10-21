import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/cubic_curve.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_path_walk.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// I-89 ④ — the path a position walks in space, After Effects' spatial
/// interpolation: a key is a corner unless it is made a curve — smooth
/// through it as its neighbours lay it, or along handles the hand placed,
/// joined in one line or split (②) — and a segment is walked by distance
/// along the path, at the pace its keys' sides give.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// A pair the hand placed straight through the key, reaching ([x], [y])
  /// ahead and as far the other way behind.
  KeyPath placed(double x, double y) =>
      SplitPath(ahead: p(x, y), behind: p(-x, -y));

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
    test('a corner says nothing, a smooth key 「auto」, a joined pair its '
        'way and two reaches, a split pair its two handles — and each reads '
        'back as itself', () {
      expect(KeyPath.straight.toJson(), isNull);
      expect(KeyPath.fromJson(null), same(KeyPath.straight));
      expect(KeyPath.auto.toJson(), 'auto');
      expect(KeyPath.fromJson('auto'), same(KeyPath.auto));
      const joined = JoinedPath(degrees: -30, ahead: 12, behind: 4);
      expect(joined.toJson(), {
        'joined': {'degrees': -30.0, 'ahead': 12.0, 'behind': 4.0},
      });
      expect(KeyPath.fromJson(joined.toJson()), joined);
      expect(
        KeyPath.fromJson(joined.toJson()),
        isNot(const JoinedPath(degrees: -30, ahead: 4, behind: 12)),
      );
      final split = SplitPath(ahead: p(3, -4), behind: p(1, 2));
      expect(split.toJson(), {
        'split': {
          'ahead': {'x': 3.0, 'y': -4.0},
          'behind': {'x': 1.0, 'y': 2.0},
        },
      });
      expect(KeyPath.fromJson(split.toJson()), split);
      expect(
        KeyPath.fromJson(split.toJson()),
        isNot(SplitPath(ahead: p(1, 2), behind: p(3, -4))),
      );
    });

    test('two pairs are one only where every number agrees', () {
      const joined = JoinedPath(degrees: 10, ahead: 2, behind: 3);
      expect(const JoinedPath(degrees: 10, ahead: 2, behind: 3), joined);
      for (final other in const [
        JoinedPath(degrees: 11, ahead: 2, behind: 3),
        JoinedPath(degrees: 10, ahead: 1, behind: 3),
        JoinedPath(degrees: 10, ahead: 2, behind: 4),
      ]) {
        expect(other, isNot(joined));
      }
      final split = SplitPath(ahead: p(1, 2), behind: p(3, 4));
      expect(SplitPath(ahead: p(1, 2), behind: p(3, 4)), split);
      expect(SplitPath(ahead: p(1, 9), behind: p(3, 4)), isNot(split));
      expect(SplitPath(ahead: p(1, 2), behind: p(3, 9)), isNot(split));
    });

    test('a path this build has no word for is a file it cannot read — a '
        'mirrored tangent among them, and a reach shorter than none', () {
      expect(() => KeyPath.fromJson('spline'), throwsFormatException);
      expect(
        () => KeyPath.fromJson({
          'tangent': {'x': 3.0, 'y': -4.0},
        }),
        throwsFormatException,
      );
      for (final (ahead, behind) in [(-1, 2), (1, -2)]) {
        expect(
          () => KeyPath.fromJson({
            'joined': {'degrees': 0, 'ahead': ahead, 'behind': behind},
          }),
          throwsFormatException,
          reason: '$ahead, $behind',
        );
      }
      expect(
        () => KeyPath.fromJson({
          'split': {'ahead': 'up', 'behind': 'down'},
        }),
        throwsFormatException,
      );
    });

    test('a track writes a key\'s path only where it bends, and reads it '
        'back', () {
      final track = PropertyTrack<CanvasPoint>(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), path: KeyPath.auto),
          20: PropertyKey(p(100, 100), path: placed(5, 6)),
          30: PropertyKey(
            p(0, 100),
            path: const JoinedPath(degrees: 90, ahead: 7, behind: 0),
          ),
        },
      );
      final json = track.toJson((value) => value.toJson());
      expect(json[0].containsKey('path'), isFalse);
      expect(json[1]['path'], 'auto');
      expect(json[2]['path'], placed(5, 6).toJson());
      expect(json[3]['path'], {
        'joined': {'degrees': 90.0, 'ahead': 7.0, 'behind': 0.0},
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

    test('a joined pair reaches along its one line, each as far as its '
        'own — wherever the neighbours stand', () {
      final at = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(
          p(100, 0),
          path: const JoinedPath(degrees: 90, ahead: 12, behind: 5),
        ),
        20: PropertyKey(p(100, 60)),
      });
      expect(keyPathHandle(at, 10, ahead: true), const Offset(0, 12));
      expect(keyPathHandle(at, 10, ahead: false), const Offset(0, -5));
      final slanted = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(
          p(100, 0),
          path: const JoinedPath(degrees: 30, ahead: 10, behind: 2),
        ),
      });
      expectNear(
        keyPathHandle(slanted, 10, ahead: true),
        Offset.fromDirection(math.pi / 6, 10),
      );
      expectNear(
        keyPathHandle(slanted, 10, ahead: false),
        Offset.fromDirection(math.pi / 6, -2),
      );
    });

    test('a split pair reaches each its own way', () {
      final at = keys({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(
          p(100, 0),
          path: SplitPath(ahead: p(12, -5), behind: p(3, 9)),
        ),
        20: PropertyKey(p(100, 60)),
      });
      expect(keyPathHandle(at, 10, ahead: true), const Offset(12, -5));
      expect(keyPathHandle(at, 10, ahead: false), const Offset(3, 9));
    });

    group('as the canvas draws it (3b)', () {
      final bent = keys({
        0: PropertyKey(p(0, 0), path: KeyPath.auto),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(100, 60)),
        30: PropertyKey(p(40, 60), path: placed(12, -5)),
      });

      test('every curved key has its two — their ends where its handles '
          'reach ahead and behind; a corner has none', () {
        final knobs = keyPathKnobs(bent);
        expect([for (final knob in knobs) knob.frame], [0, 10, 30]);
        final smooth = knobs[1];
        expect(smooth.at, p(100, 0));
        // Along (100, 60) from (100, 0): 60 / 3 ahead, 100 / 3 behind.
        final along = const Offset(100, 60) / const Offset(100, 60).distance;
        expectNear(
          Offset(smooth.ahead!.x, smooth.ahead!.y),
          const Offset(100, 0) + along * 20,
        );
        expectNear(
          Offset(smooth.behind!.x, smooth.behind!.y),
          const Offset(100, 0) - along * (100 / 3),
        );
        expect(knobs[2].behind, p(28, 65));
      });

      test('an end key has the one its segment leaves by — the first its '
          'handle ahead, the last its handle behind — and a smooth one\'s '
          'has no length: it stands on its key, where the hand pulls it out '
          'from', () {
        final [first, ..., last] = keyPathKnobs(bent);
        expect(first.ahead, p(0, 0));
        expect(first.behind, isNull);
        expect(last.ahead, isNull);
        expect(last.behind, p(28, 65));
        expect(
          keyPathKnobs(keys({0: PropertyKey(p(0, 0), path: KeyPath.auto)})),
          isEmpty,
          reason: 'a key alone bends no segment',
        );
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

  group('the key window turns a key into any of AE\'s four '
      '(anchor-walks-a-path-Q4)', () {
    // A key at (100, 0) between (0, 0) and (100, 60): the handles its
    // neighbours lay reach along (100, 60) — 60 / 3 ahead, 100 / 3 behind.
    final at = p(100, 0);
    final before = p(0, 0);
    final after = p(100, 60);
    const through = Offset(100, 60);
    final laidAhead = through / through.distance * 20;
    final laidBehind = through / through.distance * -(100 / 3);
    const joined = JoinedPath(degrees: 90, ahead: 12, behind: 5);

    KeyPath turned(KeyPath path, KeyPathKind kind) =>
        path.turned(kind, at: at, before: before, after: after);
    Offset handle(KeyPath path, {required bool ahead}) =>
        path.reach(ahead: ahead, at: at, before: before, after: after);

    test('each path says which of the four it is', () {
      expect(KeyPath.straight.kind, KeyPathKind.linear);
      expect(placed(1, 1).kind, KeyPathKind.bezier);
      expect(joined.kind, KeyPathKind.continuousBezier);
      expect(KeyPath.auto.kind, KeyPathKind.autoBezier);
    });

    test('a corner or an auto key made a bezier, split or joined, starts '
        'from the handles its neighbours lay', () {
      for (final from in [KeyPath.straight, KeyPath.auto]) {
        final split = turned(from, KeyPathKind.bezier);
        final continuous = turned(from, KeyPathKind.continuousBezier);
        expect(split, isA<SplitPath>(), reason: '$from');
        expect(continuous, isA<JoinedPath>(), reason: '$from');
        for (final made in [split, continuous]) {
          expectNear(handle(made, ahead: true), laidAhead);
          expectNear(handle(made, ahead: false), laidBehind);
        }
      }
    });

    test('a joined pair split keeps its two handles as they reach', () {
      expect(
        turned(joined, KeyPathKind.bezier),
        SplitPath(ahead: p(0, 12), behind: p(0, -5)),
      );
    });

    test('a split pair joined lines the one behind up with the one ahead, '
        'each keeping its length', () {
      final split = SplitPath(ahead: p(3, 4), behind: p(12, 0));
      final made = turned(split, KeyPathKind.continuousBezier) as JoinedPath;
      expect(made.ahead, 5);
      expect(made.behind, 12);
      expectNear(handle(made, ahead: true), const Offset(3, 4));
      expectNear(handle(made, ahead: false), const Offset(-3, -4) / 5 * 12);
      final noAhead = SplitPath(ahead: p(0, 0), behind: p(0, -7));
      expectNear(
        handle(turned(noAhead, KeyPathKind.continuousBezier), ahead: false),
        const Offset(0, -7),
      );
    });

    test('made a corner or an auto key, a key gives up the handles it had',
        () {
      for (final from in [placed(3, 1), joined]) {
        expect(turned(from, KeyPathKind.linear), KeyPath.straight);
        expect(turned(from, KeyPathKind.autoBezier), KeyPath.auto);
      }
    });

    test('its own kind leaves a key as it is', () {
      for (final path in [KeyPath.straight, KeyPath.auto, placed(3, 1)]) {
        expect(turned(path, path.kind), same(path));
      }
      expect(turned(joined, KeyPathKind.continuousBezier), same(joined));
    });

    test('an end key made a bezier holds handles of no length, on the key '
        'the hand pulls them out of', () {
      expect(
        KeyPath.straight.turned(
          KeyPathKind.continuousBezier,
          at: at,
          before: before,
        ),
        const JoinedPath(degrees: 0, ahead: 0, behind: 0),
      );
      expect(
        KeyPath.auto.turned(KeyPathKind.bezier, at: at, after: after),
        SplitPath(ahead: p(0, 0), behind: p(0, 0)),
      );
    });
  });

  group('the hand carries a handle (②)', () {
    SplayTreeMap<int, PropertyKey<CanvasPoint>> around(KeyPath path) =>
        SplayTreeMap.of({
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), path: path),
          20: PropertyKey(p(100, 60)),
        });

    void expectJoined(
      KeyPath actual, {
      required double degrees,
      required double ahead,
      required double behind,
    }) {
      expect(actual, isA<JoinedPath>());
      final joined = actual as JoinedPath;
      expect(joined.degrees, closeTo(degrees, 1e-9), reason: 'degrees');
      expect(joined.ahead, closeTo(ahead, 1e-9), reason: 'ahead');
      expect(joined.behind, closeTo(behind, 1e-9), reason: 'behind');
    }

    test('a smooth key\'s becomes a joined pair: the way the hand left it, '
        'the other handle turned into its line, as long as it was', () {
      final keys = around(KeyPath.auto);
      expect(
        keyPathHandle(keys, 10, ahead: false).distance,
        closeTo(100 / 3, 1e-9),
        reason: '⛔전제',
      );
      expectJoined(
        keyPathPulled(keys, 10, ahead: true, reach: const Offset(0, 30)),
        degrees: 90,
        ahead: 30,
        behind: 100 / 3,
      );
      expectJoined(
        keyPathPulled(keys, 10, ahead: false, reach: const Offset(0, 30)),
        degrees: -90,
        ahead: 20,
        behind: 30,
      );
    });

    test('a joined pair turns as the carried handle does, and the other '
        'keeps its own length', () {
      final keys = around(
        const JoinedPath(degrees: 0, ahead: 10, behind: 4),
      );
      expectJoined(
        keyPathPulled(keys, 10, ahead: true, reach: const Offset(0, -25)),
        degrees: -90,
        ahead: 25,
        behind: 4,
      );
      expectJoined(
        keyPathPulled(keys, 10, ahead: false, reach: const Offset(-3, -3)),
        degrees: 45,
        ahead: 10,
        behind: math.sqrt(18),
      );
    });

    test('a split pair\'s other handle stays where it was', () {
      final keys = around(SplitPath(ahead: p(12, -5), behind: p(3, 9)));
      expect(
        keyPathPulled(keys, 10, ahead: true, reach: const Offset(-1, 7)),
        SplitPath(ahead: p(-1, 7), behind: p(3, 9)),
      );
      expect(
        keyPathPulled(keys, 10, ahead: false, reach: const Offset(-1, 7)),
        SplitPath(ahead: p(12, -5), behind: p(-1, 7)),
      );
    });

    test('carried onto the key itself it keeps the way the pair lay', () {
      expectJoined(
        keyPathPulled(
          around(const JoinedPath(degrees: 33, ahead: 10, behind: 4)),
          10,
          ahead: true,
          reach: Offset.zero,
        ),
        degrees: 33,
        ahead: 0,
        behind: 4,
      );
      expect(
        keyPathPulled(
          around(const JoinedPath(degrees: 33, ahead: 0, behind: 0)),
          10,
          ahead: true,
          reach: Offset.zero,
        ),
        const JoinedPath(degrees: 33, ahead: 0, behind: 0),
        reason: 'a pair of no length keeps its way, to the bit',
      );
      expectJoined(
        keyPathPulled(
          around(KeyPath.auto),
          10,
          ahead: false,
          reach: Offset.zero,
        ),
        degrees: math.atan2(60, 100) * 180 / math.pi,
        ahead: 20,
        behind: 0,
      );
      final end = SplayTreeMap.of({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
      });
      expectJoined(
        keyPathPulled(end, 10, ahead: false, reach: Offset.zero),
        degrees: 0,
        ahead: 0,
        behind: 0,
      );
      // The key after stands on it: the handle ahead reaches nowhere, so
      // the way is away from the one behind — back along (0, 0)–(100, 0).
      final stood = SplayTreeMap.of({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
        20: PropertyKey(p(100, 0)),
      });
      expect(
        keyPathHandle(stood, 10, ahead: true),
        Offset.zero,
        reason: '⛔전제',
      );
      expectJoined(
        keyPathPulled(stood, 10, ahead: false, reach: Offset.zero),
        degrees: 0,
        ahead: 0,
        behind: 0,
      );
      expectJoined(
        keyPathPulled(stood, 10, ahead: true, reach: Offset.zero),
        degrees: 0,
        ahead: 0,
        behind: 100 / 3,
      );
    });

    test('a smooth end key\'s handle of no length pulled out bends its one '
        'segment, the other side none', () {
      final end = SplayTreeMap.of({
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: KeyPath.auto),
      });
      expectJoined(
        keyPathPulled(end, 10, ahead: false, reach: const Offset(0, 40)),
        degrees: -90,
        ahead: 0,
        behind: 40,
      );
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
        keyPathBetween(SplayTreeMap.of(keys), 0, 10).at(0.5),
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
          return keyPathBetween(keys, from, to);
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
        keyPathBetween(SplayTreeMap.of(edited.keys), 0, 10).at(0.5),
      );
      expect(laid, [0, 10, 0]);
    });

    test('a bent segment keeps the pace its keys\' sides give: it is as far '
        'along its path as the line would be along the line', () {
      const ease = EaseSide(speed: 0, influence: 0.6);
      final bent = {
        0: PropertyKey(p(0, 0), outgoing: ease),
        10: PropertyKey(p(100, 0), incoming: ease, path: placed(0, 40)),
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
      final expected = keyPathBetween(SplayTreeMap.of(bent), 0, 10).at(
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
        10: PropertyKey(p(100, 0), path: placed(4, 4)),
        20: PropertyKey(p(0, 0), name: 'A'),
        30: PropertyKey(p(50, 50)),
      },
    );

    test('dragged on the canvas to another value — the value is written, '
        'the curve stays', () {
      final dragged = track.withKey(10, p(80, 20));
      expect(dragged.keyAt(10)!.value, p(80, 20));
      expect(dragged.keyAt(10)!.path, placed(4, 4));
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
        roving: false,
      ));
      expect(linked.keyAt(0)!.path, KeyPath.auto);
      expect(linked.keyAt(20)!.path, KeyPath.auto);
      expect(linked.keyAt(10)!.path, placed(4, 4));

      final curved = track.withKeyPaths(
        frames: {0},
        kind: KeyPathKind.autoBezier,
      )!;
      expect(movedNamedKeys(track, curved), {
        'A': (
          value: p(0, 0),
          incoming: KeySide.linear,
          outgoing: KeySide.linear,
          path: KeyPath.auto,
          roving: false,
        ),
      });
    });

    // ↩️「직선 · 곡선」 (④-Q4 A while it was asked): a key already curved
    // kept its handle where a curve was picked.
    test('the key window makes the keys it covers auto or a corner — a '
        'placed handle given back to the neighbours — and nothing else '
        'moves', () {
      final auto = track.withKeyPaths(
        frames: {0, 10, 30},
        kind: KeyPathKind.autoBezier,
      )!;
      expect(auto.keyAt(0)!.path, KeyPath.auto);
      expect(auto.keyAt(10)!.path, KeyPath.auto);
      expect(auto.keyAt(30)!.path, KeyPath.auto);
      expect(auto.keyAt(20)!.path, KeyPath.straight, reason: 'not chosen');
      expect(auto.keyAt(0)!.name, 'A');
      expect(auto.keyAt(0)!.value, p(0, 0));

      final straight = auto.withKeyPaths(
        frames: {10, 30},
        kind: KeyPathKind.linear,
      )!;
      expect(straight.keyAt(10)!.path, KeyPath.straight);
      expect(straight.keyAt(30)!.path, KeyPath.straight);
      expect(straight.keyAt(0)!.path, KeyPath.auto, reason: 'not chosen');
    });

    test('a key the window makes a bezier starts from the handles its own '
        'neighbours lay', () {
      final auto = track.withKeyPaths(
        frames: {20},
        kind: KeyPathKind.autoBezier,
      )!;
      for (final kind in [
        KeyPathKind.bezier,
        KeyPathKind.continuousBezier,
      ]) {
        final made = track.withKeyPaths(frames: {20}, kind: kind)!;
        expect(made.keyAt(20)!.path.kind, kind);
        expect(made.keyAt(20)!.value, p(0, 0));
        for (final ahead in [true, false]) {
          expectNear(
            keyPathHandle(made.keys, 20, ahead: ahead),
            keyPathHandle(auto.keys, 20, ahead: ahead),
          );
        }
      }
    });

    test('a handle placed on the canvas bends that one key — its value, '
        'sides and name stay, and the link hears it', () {
      final bent = track.withKeyPath(0, placed(3, 1))!;
      expect(bent.keyAt(0)!.path, placed(3, 1));
      expect(bent.keyAt(0)!.value, p(0, 0));
      expect(bent.keyAt(0)!.name, 'A');
      expect(bent.keyAt(10)!.path, placed(4, 4));
      expect(movedNamedKeys(track, bent)['A']!.path, placed(3, 1));
      expect(track.withKeyPath(10, placed(4, 4)), isNull);
      expect(track.withKeyPath(5, KeyPath.auto), isNull, reason: 'no key');
    });

    test('and says so when it changed nothing', () {
      expect(
        track.withKeyPaths(frames: {0, 20}, kind: KeyPathKind.linear),
        isNull,
      );
      expect(
        track.withKeyPaths(frames: {10}, kind: KeyPathKind.bezier),
        isNull,
      );
      expect(
        track.withKeyPaths(frames: {5}, kind: KeyPathKind.autoBezier),
        isNull,
      );
    });
  });
}
