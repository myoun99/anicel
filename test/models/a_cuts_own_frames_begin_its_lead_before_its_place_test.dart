import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track_frame_axis.dart';
import 'package:anicel/src/models/track_id.dart';

/// 🚨THE AXIS'S ONE CONVERSION (I-73-ol-index-space): a cut's own frame 0
/// stands its lead — the のりしろ an O.L arriving into it asks — BEFORE the
/// cut's place on the track, and every conversion between the cut's frames
/// and the track's counts from there.
///
/// Cuts a [0, 24) and b [24, 48) with a gap of four after, then c
/// [52, 60); b is drawn six frames early, so its own frame 0 is the
/// track's 18.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');

  StoryboardTimelineLayoutEntry at(CutId id, int index, int start, int end) =>
      StoryboardTimelineLayoutEntry(
        trackId: const TrackId('t'),
        cutId: id,
        trackIndex: 0,
        cutIndex: index,
        startFrame: start,
        endFrame: end,
        duration: end - start,
        cut: Cut(
          id: id,
          name: id.value,
          duration: end - start,
          canvasSize: const CanvasSize(width: 8, height: 8),
          layers: const [],
        ),
      );

  final axis = TrackFrameAxis([
    at(a, 0, 0, 24),
    at(b, 1, 24, 48),
    at(c, 2, 52, 60),
  ], leads: {b: 6});

  test('a cut\'s own frame 0: its place, less its lead', () {
    expect(axis.leadOf(b), 6);
    expect(axis.leadOf(a), 0, reason: 'a cut nothing arrives into');
    expect(axis.mediaStartOf(a), 0);
    expect(axis.mediaStartOf(b), 18);
    expect(axis.mediaStartOf(c), 52);
    expect(axis.mediaStartOf(const CutId('nowhere')), isNull);
  });

  test('a frame of the cut\'s own is the track frame it plays at', () {
    expect(axis.globalOf(b, 0), 18);
    expect(axis.globalOf(b, 12), 30);
    expect(axis.globalOf(a, 12), 12);
    expect(axis.globalOf(const CutId('nowhere'), 12), isNull);
  });

  test('…and back: the cut that STANDS on a frame of the track owns it, at '
      'the frame of its own that plays there', () {
    expect(axis.localOf(30), (cutId: b, localFrame: 12));
    expect(axis.localOf(24), (cutId: b, localFrame: 6));
    expect(
      axis.localOf(20),
      (cutId: a, localFrame: 20),
      reason: 'b\'s のりしろ plays over a\'s frames, which stay a\'s',
    );
    expect(
      axis.localOf(50),
      (cutId: b, localFrame: 32),
      reason: 'a gap is the runway of the cut before it',
    );
    final entry = axis.entryFor(b)!;
    expect(axis.localIn(entry, 30), 12);
    expect(axis.localIn(entry, 18), 0);
  });

  group('where the STORYBOARD draws a frame of a cut: inside its block', () {
    test('a frame of the conte, where it plays', () {
      expect(axis.clampedToCutGlobalOf(b, 6), 24);
      expect(axis.clampedToCutGlobalOf(b, 12), 30);
      expect(axis.clampedToCutGlobalOf(b, 29), 47);
    });

    test('a frame of the のりしろ before the conte, on the cut\'s first '
        'frame', () {
      expect(axis.clampedToCutGlobalOf(b, 0), 24);
      expect(axis.clampedToCutGlobalOf(b, 5), 24);
      expect(axis.clampedToCutGlobalOf(b, -3), 24);
    });

    test('a frame past the cut\'s end, on its last', () {
      expect(axis.clampedToCutGlobalOf(b, 30), 47);
      expect(axis.clampedToCutGlobalOf(b, 400), 47);
      expect(axis.clampedToCutGlobalOf(a, 26), 23);
    });

    test('no cut, nowhere', () {
      expect(axis.clampedToCutGlobalOf(const CutId('nowhere'), 3), isNull);
    });

    test('the editing playhead: a parking where it is parked, else the '
        'open cut\'s frame held to the cut', () {
      expect(
        axis.storyboardFrameOf(
          parkedGlobalFrame: 50,
          activeCutId: b,
          localFrame: 2,
        ),
        50,
      );
      expect(
        axis.storyboardFrameOf(
          parkedGlobalFrame: null,
          activeCutId: b,
          localFrame: 2,
        ),
        24,
      );
      expect(
        axis.storyboardFrameOf(
          parkedGlobalFrame: null,
          activeCutId: null,
          localFrame: 2,
        ),
        isNull,
      );
    });
  });
}
