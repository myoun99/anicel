import 'package:anicel/src/models/camera_row_reach.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/lane_key_walk.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-625 (유저 2026-11-21): 「콘티패널에선 로컬트랙이더라도 키 < > 누를수있는
/// 판정이나 이동이 글로벌로 작동하도록 … 로컬은 지금대로 컷 내에서 < > 판정」
/// — one search, asked of a cut's keys or of the film's.
///
/// Cuts a [0, 24) and b [24, 48), four frames of gap, then c [52, 64). a
/// keys its own 0, 12, 20 and 30 — the last past its end; b its own 2, 6
/// and 12; c none.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');
  final keys = {
    a: {0, 12, 20, 30},
    b: {2, 6, 12},
    c: <int>{},
  };
  Set<int> ownKeysOf(Cut cut) => keys[cut.id]!;

  const size = CanvasSize(width: 640, height: 360);
  Cut cutOf(CutId id, int duration, {int gap = 0}) => Cut(
    id: id,
    name: id.value,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: size,
    layers: const [],
  );

  final entries = buildStoryboardTimelineLayout(
    Project(
      id: const ProjectId('film'),
      name: 'Film',
      createdAt: DateTime.utc(2026, 11, 22),
      tracks: [
        Track(
          id: const TrackId('t1'),
          name: 'V1',
          cuts: [cutOf(a, 24), cutOf(b, 24), cutOf(c, 12, gap: 4)],
        ),
      ],
    ),
  );

  /// Each cut over its own place, no のりしろ.
  final apart = cameraRowReachesOf(entries, const []);

  /// a and b joined by an O.L over [18, 30): a's own frames run to 30, b's
  /// begin at 18 — its own 2 is drawn at 20, where a's own 20 is.
  final joined = [
    CameraRowReach(
      entry: entries[0],
      mediaStart: 0,
      mediaEnd: 30,
      arrivingUntil: 0,
      leavingFrom: 18,
    ),
    CameraRowReach(
      entry: entries[1],
      mediaStart: 18,
      mediaEnd: 48,
      arrivingUntil: 30,
      leavingFrom: 48,
    ),
    apart[2],
  ];

  group('keysAbout', () {
    test('the nearest before and the nearest after, in whatever order they '
        'come', () {
      expect(keysAbout([20, 0, 12, 30], 13), (previous: 12, next: 20));
    });

    test('the frame stood on is neither: the arrows leave it', () {
      expect(keysAbout([0, 12, 20], 12), (previous: 0, next: 20));
    });

    test('none before the first, none after the last, none of none', () {
      expect(keysAbout([4, 9], 4), (previous: null, next: 9));
      expect(keysAbout([4, 9], 9), (previous: 4, next: null));
      expect(keysAbout(const [], 3), (previous: null, next: null));
    });
  });

  group('filmKeyFrames', () {
    test('each cut\'s keys at the track frames its own frames stand on, '
        'ascending — a key past its cut\'s own frames is not one', () {
      expect(apart[1].mediaStart, 24, reason: '⛔전제');
      expect(filmKeyFrames(apart, ownKeysOf), [0, 12, 20, 26, 30, 36]);
    });

    test('over an O.L a cut\'s own frames begin before its place: its keys '
        'stand where they are drawn, and a frame two cuts key is one', () {
      expect(filmKeyFrames(joined, ownKeysOf), [0, 12, 20, 24, 30]);
    });

    test('🚨a key past its cut\'s own frames is none where no other cut '
        'keys the frame either', () {
      expect(
        filmKeyFrames(apart, (cut) => cut.id == c ? {3, 12} : const {}),
        [55],
        reason: 'c\'s own 12 is past its twelve frames',
      );
    });

    test('a film with no key has none', () {
      expect(filmKeyFrames(apart, (_) => const <int>{}), isEmpty);
    });
  });

  group('filmKeyHolderAt', () {
    test('the cut that keys the frame, at the frame of its own', () {
      expect(
        filmKeyHolderAt(apart, ownKeysOf, 26),
        (cutId: b, ownFrame: 2),
      );
      expect(
        filmKeyHolderAt(apart, ownKeysOf, 30),
        (cutId: b, ownFrame: 6),
        reason: 'b\'s own 6 — a\'s own 30 is past a\'s frames',
      );
    });

    test('none where no cut draws a key', () {
      expect(filmKeyHolderAt(apart, ownKeysOf, 27), isNull);
      expect(filmKeyHolderAt(apart, ownKeysOf, 50), isNull);
    });

    test('🚨where two cuts key one frame the walk stays in the cut stood in '
        '— and takes the first, in track order, stood in neither', () {
      expect(
        filmKeyHolderAt(joined, ownKeysOf, 20, stoodIn: b),
        (cutId: b, ownFrame: 2),
      );
      expect(
        filmKeyHolderAt(joined, ownKeysOf, 20, stoodIn: a),
        (cutId: a, ownFrame: 20),
      );
      expect(
        filmKeyHolderAt(joined, ownKeysOf, 20, stoodIn: c),
        (cutId: a, ownFrame: 20),
      );
      expect(
        filmKeyHolderAt(joined, ownKeysOf, 20),
        (cutId: a, ownFrame: 20),
      );
    });

    test('the cut stood in is asked only where it keys the frame', () {
      expect(
        filmKeyHolderAt(joined, ownKeysOf, 24, stoodIn: a),
        (cutId: b, ownFrame: 6),
      );
    });
  });
}
