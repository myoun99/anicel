import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// D40 — WHAT A TRACK ROW'S SPAN IS, and where a drag on it snaps.
///
/// A characterisation test written BEFORE the cut/track cluster left the
/// session host (G3, round 8): the readers below are the whole of "select
/// this row's span" and "expand this drag to whole blocks", and nothing
/// pinned them. Every expectation is the behaviour as it stood at the
/// move, so the collaborator that owns them now cannot quietly answer
/// differently.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('the CUT row spans the first cut start through the last cut end', () {
    final s = session();
    s.createCut();
    final trackId = s.repository.requireProject().tracks.single.id;
    final entries = s.axisForTrack(trackId).entries;
    final span = s.trackCutSpan(trackId);
    expect(span, isNotNull);
    expect(span!.startFrame, entries.first.startFrame);
    expect(span.endFrameExclusive, entries.last.endFrame);
  });
  test('a track with NO cuts on the axis has no cut span at all', () {
    final s = session();
    expect(s.trackCutSpan(const TrackId('no-such-track')), isNull);
  });
  test('an S row spans its first authored block through its last, and an '
      'empty row spans nothing', () {
    final s = session();
    final se = s.activeTrack.seLayers.first;
    expect(
      s.trackRowAuthoredSpan(se.id),
      isNull,
      reason: 'nothing authored on the row yet',
    );
    s.selectLayer(se.id);
    s.selectFrameIndex(2);
    s.createSeEntryAtCurrentFrame(name: 'boom', lengthFrames: 3);
    final span = s.trackRowAuthoredSpan(se.id);
    expect(span, isNotNull);
    expect(span!.startFrame, 2);
    expect(span.endFrameExclusive, 5);
  });
  test('an id that is no track row at all has no span', () {
    final s = session();
    expect(s.trackRowAuthoredSpan(const LayerId('not-a-row')), isNull);
  });
  test('the CUT row snaps to whole cut blocks', () {
    final s = session();
    s.createCut();
    final trackId = s.repository.requireProject().tracks.single.id;
    final axis = s.axisForTrack(trackId);
    final lane = s.trackRowSnapLane(TrackRowAddress(trackId), axis);
    expect(lane, isNotNull);
    final first = axis.entries.first;
    final block = lane!(first.startFrame);
    expect(block, isNotNull);
    expect(block!.startIndex, first.startFrame);
    expect(block.endIndexExclusive, first.endFrame);
  });
  test('an S row snaps to its own exposure blocks, on its OWN track', () {
    final s = session();
    final se = s.activeTrack.seLayers.first;
    s.selectLayer(se.id);
    s.selectFrameIndex(2);
    s.createSeEntryAtCurrentFrame(name: 'boom', lengthFrames: 3);
    final trackId = s.repository.requireProject().tracks.single.id;
    final lane = s.trackRowSnapLane(
      LayerRowAddress(se.id),
      s.axisForTrack(trackId),
    );
    expect(lane, isNotNull);
    final block = lane!(3);
    expect(block, isNotNull);
    expect(block!.startIndex, 2);
    expect(block.endIndexExclusive, 5);
    expect(lane(20), isNull, reason: 'past the authored block there is none');
  });
  test('a LANE row has no snap lane — lane keys are points', () {
    final s = session();
    final trackId = s.repository.requireProject().tracks.single.id;
    expect(
      s.trackRowSnapLane(
        const LaneRowAddress(LayerId('any'), 'any-lane'),
        s.axisForTrack(trackId),
      ),
      isNull,
    );
  });
  test('a cut local frame reads back as its GLOBAL frame on the track '
      'axis', () {
    final s = session();
    s.createCut();
    final track = s.repository.requireProject().tracks.single;
    final second = track.cuts[1].id;
    final start = s.axisForTrack(track.id).entryFor(second)!.startFrame;
    expect(s.trackGlobalFrameOf(second, 2), start + 2);
  });
}
