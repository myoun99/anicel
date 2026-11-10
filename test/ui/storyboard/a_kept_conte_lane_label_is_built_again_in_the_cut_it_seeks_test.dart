import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart'
    show trackCameraRowId;
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/storyboard_host.dart';

/// 🔬Card the-conte-rails-lane-rows-are-built-again-with-the-rail (11-11):
/// A KEPT CONTE LANE LABEL IS BUILT AGAIN IN THE CUT IT SEEKS.
///
/// The conte keeps a lane's label while what it shows holds, and a
/// projection row's labels edit and seek the layer and the cut the session
/// stands in. Two cuts can hold one camera layer, and their camera lanes
/// are then one list: standing in the other cut has to build the labels
/// again, or a press on one seeks the cut stood in before.
void main() {
  testWidgets('standing in another cut that holds the same camera builds '
      'the camera row\'s lane labels again', (tester) async {
    const trackId = TrackId('t0');
    final camera = Layer(
      id: const LayerId('camera'),
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
      lanesExpanded: true,
    );
    final cutCamera = CutCamera.empty();
    Cut cutOf(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      canvasSize: const CanvasSize(width: 1280, height: 720),
      camera: cutCamera,
      layers: [
        Layer(
          id: LayerId('$id-conte'),
          name: '$id conte',
          kind: LayerKind.storyboard,
          frames: const [],
        ),
        camera,
      ],
    );
    final session = await pumpStoryboardHost(
      tester,
      Project(
        id: const ProjectId('a-camera-in-two-cuts'),
        name: 'A camera in two cuts',
        createdAt: DateTime.utc(2026, 11, 11),
        tracks: [
          Track(id: trackId, name: 'T0', cuts: [cutOf('a'), cutOf('b')]),
        ],
      ),
    );
    TimelineLaneControlsRow cameraLabel() => tester
        .widgetList<TimelineLaneControlsRow>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TimelineLaneControlsRow &&
                widget.layer.id == trackCameraRowId(trackId),
          ),
        )
        .first;

    session.selectCut(const CutId('a'));
    await tester.pumpAndSettle();
    final inA = cameraLabel();
    session.selectCut(const CutId('b'));
    await tester.pumpAndSettle();
    final inB = cameraLabel();

    expect(
      identical(inB.lane, inA.lane) && identical(inB.layer, inA.layer),
      isTrue,
      reason: '⛔premise: in either cut the row wears one layer and shows '
          'one lane — nothing the label shows tells the cuts apart',
    );
    expect(
      identical(inB, inA),
      isFalse,
      reason: 'the label seeks and edits the cut it was built in: kept into '
          'cut b, a press on it would act on cut a',
    );
  });
}
