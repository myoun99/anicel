import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R5 — the V track's own lane rows are a place the lane VERBS work.
///
/// They resolve a Layer, and a V row's lanes hang off a synthetic carrier
/// id that is not one. The lookup found nothing and the verbs reported
/// "no keys here", so Delete fell through to the CEL path: standing on a
/// V lane and pressing Delete removed the active layer's drawing instead
/// of the keys under the cursor — or did nothing at all, depending on
/// whether that layer had a cel there. Both answers are wrong.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('Delete on a V transform lane removes THAT lane\'s key, and leaves '
      'the active layer\'s cel alone', () {
    final manager = session();
    final trackId = manager.activeTrack.id;
    manager.updateTrackTransformTrack(
      trackId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 5, y: 5),
        ),
      ),
    );
    final celsBefore = manager.activeLayer!.timeline.length;

    manager.selectRow(
      LaneRowAddress(trackTransformLaneCarrierId(trackId), 'position'),
    );
    expect(
      manager.canDeleteCellAtCurrentFrame,
      isTrue,
      reason: 'the key under the cursor is what Delete is offered for',
    );

    manager.deleteCellAtCurrentFrame();

    expect(
      manager.activeTrack.transformTrack.position.isEmpty,
      isTrue,
      reason: 'the lane key is gone',
    );
    expect(
      manager.activeLayer!.timeline.length,
      celsBefore,
      reason: 'and the drawing the user was NOT pointing at survived',
    );
  });

  test('Add Key on a V transform lane keys the track', () {
    final manager = session();
    final trackId = manager.activeTrack.id;
    expect(manager.activeTrack.transformTrack.position.isEmpty, isTrue);

    manager.selectRow(
      LaneRowAddress(trackTransformLaneCarrierId(trackId), 'position'),
    );
    manager.createInstancesForSelection();

    expect(
      manager.activeTrack.transformTrack.position.isNotEmpty,
      isTrue,
      reason: 'the verb reached the TRACK behind the carrier',
    );
  });
}
