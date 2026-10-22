import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// anchor-walks-a-path ① (유저 2026-10-13: 「구조는 최대한 AE랑
/// 통일하려고」 — After Effects' Anchor Point is a spatial property, as its
/// Position is): an anchor point's keys walk a path by the position's own
/// code — the walk, the roving keys placed where their run passes them,
/// the file that keeps them, and the name link reading what an edit wrote.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// A corner at 0, a key 100 right of it at 10, then 300 down to a corner
  /// at 20 — the middle one smooth, or roving.
  PropertyTrack<CanvasPoint> turning({bool roving = false}) => PropertyTrack(
    keys: {
      0: PropertyKey(p(0, 0)),
      10: roving
          ? PropertyKey(p(100, 0), roving: true)
          : PropertyKey(p(100, 0), path: KeyPath.auto),
      20: PropertyKey(p(100, 300)),
    },
  );

  /// The two lanes whose keys walk a path, each read off a track and laid
  /// on an empty one.
  final lanes = [
    (
      name: 'anchor point',
      of: (TransformTrack track) => track.anchorPoint,
      on: (PropertyTrack<CanvasPoint> lane) =>
          TransformTrack.empty().copyWith(anchorPoint: lane),
    ),
    (
      name: 'position',
      of: (TransformTrack track) => track.position,
      on: (PropertyTrack<CanvasPoint> lane) =>
          TransformTrack.empty().copyWith(position: lane),
    ),
  ];

  test('an anchor walks the path a position with the same keys walks', () {
    final lane = turning();
    final pose = TransformTrack.empty().copyWith(position: lane);
    for (var time = 0.0; time <= 20; time += 0.5) {
      expect(
        resolveAnchorTrackAtTime(lane, time),
        pose
            .resolveAtTime(
              time: time,
              orElse: () => TransformPose(center: p(0, 0)),
            )
            .center,
        reason: 'at $time',
      );
    }
    expect(
      resolveAnchorTrackAtTime(lane, 15),
      isNot(lane.resolveAtTime(
        time: 15,
        orElse: () => p(0, 0),
        space: pointKeySpace,
      )),
      reason: '⛔premise: the smooth key bends the way, off the line',
    );
  });

  test('a roving key stands where its run passes it, on a track and in its '
      'file, the anchor\'s as the position\'s', () {
    final placed = [
      for (final lane in lanes)
        lane.of(lane.on(turning(roving: true))).keys.keys.toList(),
    ];
    expect(placed.first, isNot([0, 10, 20]), reason: '⛔premise: placed');
    expect(placed.first, placed.last);
    for (final lane in lanes) {
      final track = lane.on(turning(roving: true));
      expect(
        lane.of(TransformTrack.fromJson(track.toJson())),
        lane.of(track),
        reason: lane.name,
      );
    }
  });

  group('the name link reads what an edit of a roving key wrote — where '
      'its run places it elsewhere', () {
    for (final lane in lanes) {
      test('on the ${lane.name}', () {
        final before = lane.on(turning(roving: true).withKeyName(10, 'A'));
        final at = lane.of(before).keys.entries
            .singleWhere((entry) => entry.value.name == 'A')
            .key;
        final written = lane.on(lane.of(before).withKey(at, p(300, 0)));
        expect(
          lane.of(written).keyAt(at),
          isNull,
          reason: '⛔premise: its run placed it elsewhere',
        );
        // …and an edit of another lane after it in the same write keeps
        // what this one wrote.
        final after = written.copyWith(
          rotation: PropertyTrack<double>().withKey(0, 90),
        );
        final changes = transformNamedKeyChanges(before, after);
        expect(
          [changes.anchorPoint['A']?.value, changes.position['A']?.value],
          lane.name == 'position' ? [null, p(300, 0)] : [p(300, 0), null],
        );
      });
    }
  });
}
