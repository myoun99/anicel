import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/storyboard_rows.dart';

/// THE STORYBOARD RAIL'S ROWS — the list a cross-row range drag walks.
///
/// 🚨★★★**THE LIST ORDER IS THE VISUAL ORDER** (feedback #14, and the
/// real-device 「row-span select does nothing」 report). A range drag steps
/// through this list by row DELTA, so a positive delta has to mean
/// 「downward on screen」. The list used to lead with the CUT row, which
/// inverted every cross-row drag: dragging from an S row down toward the V
/// row walked the list away from it.
///
/// And the transition row heads the group on screen, so it heads the list
/// (user 2026-08-11) — a row missing from the list is unreachable, which is
/// what left a cross-row drag unable to start on it or arrive at it.
///
/// ⚠️Nothing named this order. `storyboardSelectedCutIds` has its pins in
/// `storyboard_cut_range_test`; the ORDER and the storyboard's next-cut
/// walk had none, and both are the sort of law that reads as correct in
/// every direction until a drag goes the wrong way on a device.
void main() {
  const trackId = TrackId('rail-track');
  const seLow = LayerId('rail-s0');
  const seHigh = LayerId('rail-s1');

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const [], timeline: {}),
    ],
  );

  Layer se(LayerId id, String name) =>
      Layer(id: id, name: name, kind: LayerKind.se, frames: const [], timeline: {});

  /// Three cuts on one track, and TWO SE slots — slot 0 sits just above the
  /// cut row on screen, slot 1 above that.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('rail'),
        name: 'Rail',
        createdAt: DateTime.utc(2026, 9, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'Video',
            cuts: [cut('cut-1', 6), cut('cut-2', 6), cut('cut-3', 6)],
            seLayers: [se(seLow, 'S1'), se(seHigh, 'S2')],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  StoryboardRows railOf(EditorSessionManager s) => s.storyboardRows;

  test('the rail lists its rows in the order it STACKS them: the transition '
      'row, then the SE slots highest-first, and the CUT row at the bottom',
      () {
    final s = session();
    final track = s.repository.requireProject().tracks.single;

    expect(railOf(s).storyboardRailRows(trackId), [
      LayerRowAddress(track.transitionLayer.id),
      const LayerRowAddress(seHigh),
      const LayerRowAddress(seLow),
      const TrackRowAddress(trackId),
    ]);
  });

  test('a row delta of +1 from the top row therefore lands on the row BELOW '
      'it on screen', () {
    final s = session();
    final rows = railOf(s).storyboardRailRows(trackId);

    expect(
      rows[rows.indexOf(const LayerRowAddress(seHigh)) + 1],
      const LayerRowAddress(seLow),
      reason: 'slot 0 sits just above the cut row, so slot 1 is ABOVE slot 0 '
          '— walking the list downward must reach the lower slot',
    );
    expect(
      rows.last,
      const TrackRowAddress(trackId),
      reason: '⛔leading with the cut row is what inverted every cross-row '
          'drag on a real device',
    );
  });

  test('a track the project no longer holds still offers its cut row — what '
      'is not on the list is unreachable, and an empty list is no rail', () {
    final s = session();

    expect(railOf(s).storyboardRailRows(const TrackId('gone')), const [
      TrackRowAddress(TrackId('gone')),
    ]);
  });

  test('the next cut in STORYBOARD order is the next one along the track, '
      'and the last cut has none', () {
    final s = session();
    final rail = railOf(s);

    expect(rail.nextCutIdInStoryboardOrder(const CutId('cut-1')),
        const CutId('cut-2'));
    expect(rail.nextCutIdInStoryboardOrder(const CutId('cut-2')),
        const CutId('cut-3'));
    expect(
      rail.nextCutIdInStoryboardOrder(const CutId('cut-3')),
      isNull,
      reason: 'the end of the film is an honest nothing, not a wrap to the '
          'first cut',
    );
  });

  test('a cut id the layout does not hold has no next cut either', () {
    final s = session();

    expect(
      railOf(s).nextCutIdInStoryboardOrder(const CutId('no-such-cut')),
      isNull,
    );
  });
}
