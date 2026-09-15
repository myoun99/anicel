import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/timeline/timeline_defaults.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/track_se_display.dart';

/// A track-owned SE row keys its blocks on the track's GLOBAL frames, and a
/// cut edits it through ONE offset — [TrackSeDisplay.rowAxisOffset].
///
/// Two of the verbs that ask it had no test standing on a cut past the first,
/// where the offset is not zero: the timeline controller's edit index (every
/// create, delete and retime on the row) and the track-range fill, which
/// hands the controller GLOBAL gaps and so has to take the offset back off
/// first. Both would pass today with the offset forgotten in cut 1.
///
/// The collaborator the offset lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
TrackSeDisplay trackSeOf(EditorSessionManager session) => session.trackSe;

void main() {
  late EditorSessionManager session;
  late LayerId s1;
  late int cut2;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    s1 = session.activeTrack.seLayers.first.id;
    session.cutVerbs.createCut();
    cut2 = session.activeCutGlobalStartFrame;
    expect(
      cut2,
      defaultCutDurationFrames,
      reason: 'fixture premise: cut 2 is open and starts where cut 1 ends',
    );
  });
  tearDown(() => session.dispose());

  Layer row() =>
      session.activeTrack.seLayers.firstWhere((layer) => layer.id == s1);

  test('in cut 2, an SE entry made at local frame 1 is keyed at the cut\'s '
      'start + 1 on the track\'s row — and Delete there takes it', () {
    session.selectLayer(s1);
    session.selectFrameIndex(1);
    session.seEntries.createSeEntryAtCurrentFrame(name: 'a', lengthFrames: 2);

    expect(
      row().timeline.keys,
      [cut2 + 1],
      reason: 'the controller adds the row\'s axis offset to its edit index',
    );

    session.cells.deleteCellAtCurrentFrame();

    expect(row().timeline, isEmpty, reason: 'the delete finds it at the same key');
  });

  test('in cut 2, a track-range fill lands on the frames the range names — '
      'not shifted a second time', () {
    final created = trackSeOf(session).createTrackSeEntriesForRange(
      TrackFrameRangeSelection(
        trackId: session.selectedTrackId,
        anchorRow: LayerRowAddress(s1),
        startFrame: cut2 + 2,
        endFrameExclusive: cut2 + 4,
      ),
    );

    expect(created, isTrue, reason: 'premise: the range held an empty run');
    expect(row().timeline.keys, [cut2 + 2]);
    expect(row().timeline[cut2 + 2]!.length, 2);
  });
}
