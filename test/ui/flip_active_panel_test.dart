import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The panel being WORKED IN owns the frame-axis verbs (user, 2026-08-05):
/// picking a row is no longer the only way to move the flip's subject.
void main() {
  EditorSessionManager twoCutSession() {
    final project = Project(
      id: const ProjectId('p-active-panel'),
      name: 'Active Panel',
      createdAt: DateTime.utc(2026, 8, 5),
      tracks: [
        Track(
          id: const TrackId('default-track'),
          name: 'Video Track',
          cuts: [
            for (var index = 1; index <= 2; index += 1)
              createDefaultCut(
                cutId: CutId('cut-$index'),
                name: '$index',
                layerId: LayerId('layer-$index'),
              ),
          ],
        ),
      ],
    );
    return EditorSessionManager(initialProject: project);
  }

  test('touching the storyboard hands the flip its rail row — no row pick '
      'required', () {
    final session = twoCutSession();
    addTearDown(session.dispose);
    expect(session.currentRow, isA<LayerRowAddress>());

    session.claimStoryboardRow();

    expect(session.currentRow, isA<TrackRowAddress>());
    session.selectNextDrawing();
    expect(
      session.activeCutId,
      const CutId('cut-2'),
      reason: 'the storyboard counts CUTS',
    );
  });

  test('touching the timeline hands it back, on the row that panel had', () {
    final session = twoCutSession();
    addTearDown(session.dispose);
    final layerId = session.requireActiveCut.layers.first.id;

    session.claimStoryboardRow();
    expect(session.currentRow, isA<TrackRowAddress>());

    session.claimTimelineRow();
    expect(session.currentRow, LayerRowAddress(layerId));
  });

  test('★ the timeline gets back the LANE it was left on, not the layer '
      'row under it', () {
    final session = twoCutSession();
    addTearDown(session.dispose);
    final layerId = session.requireActiveCut.layers.first.id;
    const lane = LaneRowAddress(LayerId('layer-1'), 'opacity');
    expect(layerId, lane.layerId);

    session.selectRow(lane);
    expect(session.currentRow, lane);

    // Away to the storyboard and back.
    session.claimStoryboardRow();
    expect(session.currentRow, isA<TrackRowAddress>());
    session.claimTimelineRow();

    expect(
      session.currentRow,
      lane,
      reason: 'coming back must not drop to the layer the lane hangs under',
    );
  });

  test('a claim is QUIET — it moves the verb, it does not redraw', () {
    // It fires on pointer-DOWN, and a ruler drag's whole contract is that
    // it stays silent per move and commits once on release.
    final session = twoCutSession();
    addTearDown(session.dispose);
    var notifies = 0;
    session.addListener(() => notifies += 1);

    session.claimStoryboardRow();
    session.claimTimelineRow();
    session.claimStoryboardRow();

    expect(notifies, 0);
    expect(session.currentRow, isA<TrackRowAddress>());
  });
}
