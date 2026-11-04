import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/property_track_cut.dart';
import 'package:anicel/src/models/transform_track.dart';

/// I-120-Q3 (유저 2026-11-04) 「범위 안만 굽고, 범위 밖은 보이던 그대로」 — a
/// track cleared over a range of frames: the range at rest, and every frame
/// outside it what it was — a key on the frame before the range and the
/// frame after it, and a way the range cuts kept as it was outside, its
/// curve cut in two.
void main() {
  const frames = 30;

  PropertyTrack<double> numbers(Map<int, PropertyKey<double>> keys) =>
      PropertyTrack(keys: keys);

  PropertyTrack<double> cleared(
    PropertyTrack<double> track, {
    required int start,
    required int end,
    double unkeyed = 0,
    KeyValueSpace<double> space = doubleKeySpace,
  }) => trackClearedOver(
    track,
    start: start,
    end: end,
    frames: frames,
    rest: 0,
    unkeyed: () => unkeyed,
    space: space,
    same: (a, b) => (a - b).abs() <= 1e-9 * (a.abs() > 1 ? a.abs() : 1),
  );

  double at(
    PropertyTrack<double> track,
    double time, {
    double unkeyed = 0,
    KeyValueSpace<double> space = doubleKeySpace,
  }) => track.resolveAtTime(time: time, orElse: () => unkeyed, space: space);

  /// Every frame of [frames] outside [start]..[end] of [now] as [was] shows
  /// it — and every frame inside at rest.
  void expectKept(
    PropertyTrack<double> was,
    PropertyTrack<double> now, {
    required int start,
    required int end,
    double unkeyed = 0,
    KeyValueSpace<double> space = doubleKeySpace,
  }) {
    for (var frame = 0; frame < frames; frame += 1) {
      final inside = frame >= start && frame < end;
      expect(
        at(now, frame.toDouble(), unkeyed: unkeyed, space: space),
        closeTo(
          inside ? 0 : at(was, frame.toDouble(), unkeyed: unkeyed, space: space),
          1e-9,
        ),
        reason: 'frame $frame',
      );
    }
  }

  test('a range over every frame clears every key — what a bake with no '
      'range did (Q4)', () {
    final track = numbers({0: const PropertyKey(10), 20: const PropertyKey(40)});
    expect(cleared(track, start: 0, end: frames).isEmpty, isTrue);
  });

  test('an unkeyed lane at rest stays unkeyed; one standing elsewhere takes '
      'a key at each edge and the range\'s own', () {
    expect(cleared(numbers({}), start: 4, end: 8).isEmpty, isTrue);
    final standing = cleared(numbers({}), start: 4, end: 8, unkeyed: 12);
    expect(standing.keys.keys, [3, 4, 7, 8]);
    expectKept(numbers({}), standing, start: 4, end: 8, unkeyed: 12);
  });

  test('🎯a straight ramp the range cuts: a key on the frame before it and '
      'after it, the ramp either side as it was, its sides still straight',
      () {
    final track = numbers({
      0: const PropertyKey(0),
      20: const PropertyKey(100),
    });
    final now = cleared(track, start: 6, end: 10);
    expect(now.keys.keys, [0, 5, 6, 9, 10, 20]);
    expectKept(track, now, start: 6, end: 10);
    for (final key in now.keys.values) {
      expect([key.incoming, key.outgoing], [KeySide.linear, KeySide.linear]);
    }
  });

  test('🎯an eased way the range cuts keeps its curve outside — between '
      'frames as well — its key\'s handle set to the half\'s', () {
    const ease = EaseSide(influence: 0.6, speed: 0);
    final track = numbers({
      0: const PropertyKey(0, outgoing: ease),
      20: const PropertyKey(100, incoming: EaseSide(speed: 0.5)),
    });
    final now = cleared(track, start: 8, end: 14);
    expectKept(track, now, start: 8, end: 14);
    for (final time in [0.5, 3.25, 6.9, 14.4, 17.75, 19.5]) {
      expect(at(now, time), closeTo(at(track, time), 1e-9), reason: '$time');
    }
    expect(now.keys[0]!.outgoing, isNot(ease), reason: 'its half is shorter');
    expect(now.keys[0]!.outgoing, isA<EaseSide>());
    expect(now.keys[7]!.incoming, isA<EaseSide>());
  });

  test('a smooth key whose neighbour the range moved keeps the way it was '
      'read into it — set to the handle it was', () {
    final track = numbers({
      0: const PropertyKey(0, outgoing: KeySide.auto),
      6: const PropertyKey(60, incoming: KeySide.auto, outgoing: KeySide.auto),
      16: const PropertyKey(0, incoming: KeySide.auto),
    });
    final now = cleared(track, start: 8, end: 12);
    expectKept(track, now, start: 8, end: 12);
    for (final time in [1.5, 4.5, 5.5]) {
      expect(at(now, time), closeTo(at(track, time), 1e-9), reason: '$time');
    }
    expect(now.keys[6]!.incoming, isA<EaseSide>());
    expect(now.keys[0]!.outgoing, KeySide.auto, reason: 'it reads 6 alone');
  });

  test('a hold across an edge holds on: the key after the range holds what '
      'it held until the next', () {
    final track = numbers({
      0: const PropertyKey(10, outgoing: KeyExit.hold),
      20: const PropertyKey(40),
    });
    final now = cleared(track, start: 4, end: 8);
    expectKept(track, now, start: 4, end: 8);
    expect(now.keys[8]!.outgoing, KeyExit.hold);
  });

  test('an edge on a key cuts nothing — the key keeps its sides', () {
    const ease = EaseSide(influence: 0.4, speed: 0.2);
    final track = numbers({
      0: const PropertyKey(0, outgoing: ease),
      5: const PropertyKey(50, incoming: ease),
      20: const PropertyKey(100),
    });
    final now = cleared(track, start: 6, end: 10);
    expectKept(track, now, start: 6, end: 10);
    expect(now.keys[5], track.keys[5]);
  });

  test('a range at the start or at the end keeps the one side it has', () {
    final track = numbers({
      0: const PropertyKey(0),
      20: const PropertyKey(100, incoming: EaseSide()),
    });
    final head = cleared(track, start: 0, end: 10);
    expectKept(track, head, start: 0, end: 10);
    expect(head.keys.keys.first, 9, reason: 'the range\'s own key');
    final tail = cleared(track, start: 15, end: frames);
    expectKept(track, tail, start: 15, end: frames);
    expect(tail.keys.keys.last, 15, reason: 'the range\'s own key');
  });

  test('a menu steps on: its keys hold whatever the edges cut', () {
    final track = numbers({
      0: const PropertyKey(1),
      10: const PropertyKey(2),
      20: const PropertyKey(3),
    });
    final now = cleared(track, start: 12, end: 16, space: menuKeySpace);
    expectKept(track, now, start: 12, end: 16, space: menuKeySpace);
  });

  test('a colour rounded on its way keeps every frame — a key on each frame '
      'of a side the cut could not keep', () {
    final track = PropertyTrack<int>(
      keys: {
        0: const PropertyKey(0xFF000000),
        29: const PropertyKey(0xFFFFFFFF, incoming: EaseSide(speed: 0)),
      },
    );
    final now = trackClearedOver(
      track,
      start: 10,
      end: 12,
      frames: frames,
      rest: 0xFF808080,
      unkeyed: () => 0xFF808080,
      space: argbKeySpace,
      same: (a, b) => a == b,
    );
    for (var frame = 0; frame < frames; frame += 1) {
      final inside = frame >= 10 && frame < 12;
      expect(
        now.resolveAt(
          frameIndex: frame,
          orElse: () => 0,
          space: argbKeySpace,
        ),
        inside
            ? 0xFF808080
            : track.resolveAt(
                frameIndex: frame,
                orElse: () => 0,
                space: argbKeySpace,
              ),
        reason: 'frame $frame',
      );
    }
  });

  group('a key\'s name', () {
    test('leaves the key whose sides the cut set apart (Q15, while it is '
        'asked) — a name is one key, sides and all', () {
      final track = numbers({
        0: const PropertyKey(
          0,
          outgoing: EaseSide(influence: 0.6, speed: 0),
          name: 'A',
        ),
        20: const PropertyKey(100, name: 'B'),
        25: const PropertyKey(50, name: 'C'),
      });
      final now = cleared(track, start: 8, end: 12);
      expect(
        [for (final frame in [0, 20, 25]) now.keys[frame]!.name],
        [null, null, 'C'],
        reason: 'both halves of the eased way are paced anew; 25 is not cut',
      );
    });

    test('stays on a key the cut leaves as it was — an ease a third of its '
        'way, whose half is the same ease', () {
      final track = numbers({
        0: const PropertyKey(0, outgoing: EaseSide(), name: 'A'),
        20: const PropertyKey(100),
      });
      final now = cleared(track, start: 8, end: 12);
      expect(now.keys[0], track.keys[0]);
    });
  });

  group('a lane that walks a path (I-89 ④)', () {
    CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

    PropertyTrack<CanvasPoint> clearedPath(
      PropertyTrack<CanvasPoint> track, {
      required int start,
      required int end,
    }) => trackClearedOver(
      track,
      start: start,
      end: end,
      frames: frames,
      rest: p(50, 50),
      unkeyed: () => p(50, 50),
      space: pathKeySpace,
      same: (a, b) => (a.x - b.x).abs() < 1e-2 && (a.y - b.y).abs() < 1e-2,
    );

    CanvasPoint place(PropertyTrack<CanvasPoint> track, double time) =>
        track.resolveAtTime(
          time: time,
          orElse: () => p(50, 50),
          space: pathKeySpace,
        );

    void expectPlaces(
      PropertyTrack<CanvasPoint> was,
      PropertyTrack<CanvasPoint> now, {
      required int start,
      required int end,
    }) {
      for (var frame = 0; frame < frames; frame += 1) {
        final inside = frame >= start && frame < end;
        final want = inside ? p(50, 50) : place(was, frame.toDouble());
        final got = place(now, frame.toDouble());
        expect(got.x, closeTo(want.x, 1e-2), reason: 'frame $frame x');
        expect(got.y, closeTo(want.y, 1e-2), reason: 'frame $frame y');
      }
    }

    test('🎯a bend the range cuts keeps its path outside: the key before '
        'it bends as it did, its handle into the way shortened', () {
      final track = PropertyTrack<CanvasPoint>(
        keys: {
          0: PropertyKey(p(0, 0), path: KeyPath.auto),
          10: PropertyKey(p(100, 0), path: KeyPath.auto),
          20: PropertyKey(p(100, 100), path: KeyPath.auto),
        },
      );
      final now = clearedPath(track, start: 13, end: 17);
      expectPlaces(track, now, start: 13, end: 17);
      final key = now.keys[10]!.path;
      expect(key, isA<JoinedPath>(), reason: 'AE: an auto key set');
      expect(now.keys[12]!.path, isA<JoinedPath>());
      for (final time in [10.5, 11.25, 11.9]) {
        final want = place(track, time);
        final got = place(now, time);
        expect(got.x, closeTo(want.x, 1e-2), reason: '$time x');
        expect(got.y, closeTo(want.y, 1e-2), reason: '$time y');
      }
    });

    test('a run of roving keys the range cuts keeps each of its frames — a '
        'key on each of them', () {
      final track = PropertyTrack<CanvasPoint>(
        keys: {
          0: PropertyKey(p(0, 0)),
          10: PropertyKey(p(100, 0), roving: true),
          20: PropertyKey(p(100, 300)),
        },
      );
      final now = clearedPath(track, start: 6, end: 8);
      expectPlaces(track, now, start: 6, end: 8);
      expect(now.keys.keys.where((frame) => frame < 6), [0, 1, 2, 3, 4, 5]);
    });
  });
}
