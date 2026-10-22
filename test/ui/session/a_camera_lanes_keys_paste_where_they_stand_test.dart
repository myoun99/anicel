import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;

/// F-388 on the CAMERA row (관제 10-22: the Surface's run copied the
/// camera's position lane over 1–8, stood on 4 and pasted — and nothing
/// came). The camera's keys live on the cut's camera, not on its row.
void main() {
  late EditorSessionManager s;
  late Layer camera;
  late ToolbarPanelContext pill;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    camera = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    s.selectLayer(camera.id);
    pill = TimelineToolbarPanelContext(s);
  });
  tearDown(() => s.dispose());

  Set<int> keys() =>
      transformLaneKeyFrames(s.requireActiveCut.camera.track, 'position');

  void standOn(int at, Layer row) {
    s.selectFrameIndex(at);
    s.standOnRow(LaneRowAddress(row.id, 'position'));
  }

  void keyAt(int frame, Layer row) {
    standOn(frame, row);
    expect(s.cellInstances.createInstancesForSelection(), isTrue);
  }

  /// [row]'s position lane copied over 1–8, and its lane stood on at 4.
  void copyOneToEightStandOnFour(Layer row) {
    standOn(1, row);
    s.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row.id,
      laneId: 'position',
      startIndex: 1,
      endIndexExclusive: 9,
    );
    pill.copyFrame();
    expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');
    s.laneRangeSelection.value = null;
    standOn(4, row);
  }

  test('a band copied off the camera\'s position lane goes in where the '
      'lane is stood on, the keys after it moved back', () {
    for (final frame in [1, 5, 8, 12]) {
      keyAt(frame, camera);
    }
    expect(keys(), {1, 5, 8, 12}, reason: '⛔전제');
    copyOneToEightStandOnFour(camera);

    expect(pill.canPasteIndependentFrame, isTrue, reason: '⛔전제');
    pill.pasteIndependentFrame();

    expect(keys(), {1, 4, 8, 11, 13, 16, 20});
  });

  test('🚨a paste that would push a key past the cut\'s end is DARK — '
      'the button answers what its press writes (T25), not lit over a '
      'write the camera refuses', () {
    final last = s.requireActiveCut.duration - 1;
    for (final frame in [1, 5, 8, last]) {
      keyAt(frame, camera);
    }
    expect(keys(), {1, 5, 8, last}, reason: '⛔전제');
    copyOneToEightStandOnFour(camera);

    expect(pill.canPasteIndependentFrame, isFalse);
    expect(pill.canPasteLinkedFrame, isFalse);
    pill.pasteIndependentFrame();
    expect(keys(), {1, 5, 8, last}, reason: 'and the press writes nothing');
  });

  test('a drawing row\'s keys are not the camera\'s: pushed past the cut\'s '
      'end they go there — the refusal asks the camera row alone', () {
    final row = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind != LayerKind.camera,
    );
    s.selectLayer(row.id);
    Set<int> rowKeys() => transformLaneKeyFrames(
      s.requireActiveCut.layers
          .firstWhere((layer) => layer.id == row.id)
          .transformTrack,
      'position',
    );
    final last = s.requireActiveCut.duration - 1;
    for (final frame in [1, 5, 8, last]) {
      keyAt(frame, row);
    }
    expect(rowKeys(), {1, 5, 8, last}, reason: '⛔전제');
    copyOneToEightStandOnFour(row);

    expect(pill.canPasteIndependentFrame, isTrue);
    pill.pasteIndependentFrame();
    expect(rowKeys(), {1, 4, 8, 11, 13, 16, last + 8});
  });
}
