import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_row_reach.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transition_geometry.dart';

/// 🗣️I-73 ④ (유저 2026-10-08): 「카메라행은 ol떄 2줄로 만드는거 ok」.
///
/// A cut's camera is drawn over the cut's OWN frames — its place on the
/// track, and the のりしろ an O.L asks before and after it — and where two
/// cuts' own frames run at once the row splits: the leaving cut on the
/// upper line, the arriving cut on the lower.
///
/// Cuts a [0, 24) and b [24, 48), a gap of four, then c [52, 60). A 12-frame
/// O.L at [18, 30) joins a and b: a is drawn to 30, b from 18.
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

  final entries = [at(a, 0, 0, 24), at(b, 1, 24, 48), at(c, 2, 52, 60)];
  const ol = (start: 18, length: 12, mark: CameraInstructionMarkType.ol);

  CameraRowReach reachOf(List<CameraRowReach> reaches, CutId id) =>
      reaches.singleWhere((reach) => reach.entry.cutId == id);

  test('with no transition a cut reaches its place alone, on one line', () {
    final reaches = cameraRowReachesOf(entries, const <TransitionSpan>[]);
    final ra = reachOf(reaches, a);
    expect((ra.mediaStart, ra.mediaEnd), (0, 24));
    expect(
      (ra.arrivingUntil, ra.leavingFrom),
      (0, 24),
      reason: 'it shares nothing with a neighbour',
    );
    for (final frame in [0, 12, 23]) {
      expect(ra.lineAt(frame), CameraRowLine.middle);
    }
    expect(ra.reaches(24), isFalse, reason: 'b\'s first frame is not a\'s');
    expect(ra.reaches(-1), isFalse);
  });

  test('an O.L draws each cut over its のりしろ and splits the stretch '
      'they share', () {
    final reaches = cameraRowReachesOf(entries, const [ol]);
    final ra = reachOf(reaches, a);
    final rb = reachOf(reaches, b);
    expect((ra.mediaStart, ra.mediaEnd), (0, 30), reason: 'a leaves late');
    expect((rb.mediaStart, rb.mediaEnd), (18, 48), reason: 'b arrives early');
    // The stretch they share is the span itself.
    expect(ra.leavingFrom, 18);
    expect(rb.arrivingUntil, 30);

    expect(ra.lineAt(17), CameraRowLine.middle);
    expect(ra.lineAt(18), CameraRowLine.upper, reason: 'a leaves above');
    expect(ra.lineAt(29), CameraRowLine.upper);
    expect(rb.lineAt(18), CameraRowLine.lower, reason: 'b arrives below');
    expect(rb.lineAt(29), CameraRowLine.lower);
    expect(rb.lineAt(30), CameraRowLine.middle);
  });

  test('a band over a cut lays a piece a line, each on the line its first '
      'frame is drawn on', () {
    final rb = reachOf(cameraRowReachesOf(entries, const [ol]), b);
    // b's own frames 0..30 run on the track from 18 to 48: below to 30,
    // where the O.L ends, and in the middle after.
    expect(rb.stretchesOf(0, 30), [
      (from: 18, to: 30, line: CameraRowLine.lower),
      (from: 30, to: 48, line: CameraRowLine.middle),
    ]);
  });

  test('a cut\'s own frame is counted from its media start', () {
    final rb = reachOf(cameraRowReachesOf(entries, const [ol]), b);
    expect(rb.trackFrameOf(0), 18, reason: 'b\'s frame 0 plays at 18');
    expect(rb.ownFrameAt(24), 6, reason: 'b\'s place is its own frame 6');
    expect(rb.ownFrameAt(rb.trackFrameOf(11)), 11);
  });

  test('a のりしろ into a gap is drawn on the one line — no neighbour '
      'shares it', () {
    // An O.L across c's start, where only a gap stands before it.
    const intoGap = (start: 50, length: 4, mark: CameraInstructionMarkType.ol);
    final rc = reachOf(cameraRowReachesOf(entries, const [intoGap]), c);
    expect((rc.mediaStart, rc.mediaEnd), (50, 60));
    expect(rc.arrivingUntil, 50, reason: 'nothing to share the のりしろ with');
    expect(rc.lineAt(50), CameraRowLine.middle);
  });

  test('a one-sided transition owes no のりしろ, so it splits nothing', () {
    const fade = (start: 20, length: 4, mark: CameraInstructionMarkType.fo);
    final reaches = cameraRowReachesOf(entries, const [fade]);
    final ra = reachOf(reaches, a);
    expect((ra.mediaStart, ra.mediaEnd), (0, 24));
    expect(ra.leavingFrom, 24);
  });
}
