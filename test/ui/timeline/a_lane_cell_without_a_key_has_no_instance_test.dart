import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/dialogs/rename_frame_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';

/// A LANE row's instance is its KEY (F-17 · 유저 2026-09-11: 「트랜스폼행에서
/// 더블클릭으로 편집창 안열리는것등 이런거 싹 법 하나로 통일」): a lane cell
/// with no key has none — whatever cel its owner holds under the playhead —
/// and the camera row, being its transform header, answers the same way.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    session.createDrawingAtCurrentFrame();
  });
  tearDown(() => session.dispose());

  test('standing on an EMPTY lane cell, Edit has nothing to open — not the '
      "owner's cel under the playhead", () {
    final layerId = session.activeLayer!.id;
    expect(
      session.selectedFrame,
      isNotNull,
      reason: 'fixture: a cel IS under the playhead',
    );
    session.standOnRow(LaneRowAddress(layerId, 'rotation'), frameIndex: 0);
    expect(session.cellInstances.canEditCellInstanceAtCurrentFrame, isFalse);

    expect(session.cellInstances.createInstancesForSelection(), isTrue);
    expect(
      session.cellInstances.canEditCellInstanceAtCurrentFrame,
      isTrue,
      reason: 'a key there is its instance',
    );
  });

  test('standing on the CAMERA row: its key is its instance, and without one '
      'there is nothing to edit — the ＋ keys every member', () {
    final camera = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    session.standOnRow(LayerRowAddress(camera.id), frameIndex: 3);
    expect(session.cellInstances.canEditCellInstanceAtCurrentFrame, isFalse);

    expect(session.cellInstances.createInstancesForSelection(), isTrue);
    final track = session.activeCutOrNull!.camera.track;
    expect(track.position.keyAt(3), isNotNull);
    expect(track.scale.keyAt(3), isNotNull);
    expect(track.rotation.keyAt(3), isNotNull);
    expect(session.cellInstances.canEditCellInstanceAtCurrentFrame, isTrue);
  });

  test('under a cell band that holds more than the camera, the camera row '
      'has no instance of its own to edit — the band claims the press', () {
    final drawingId = session.activeLayer!.id;
    final camera = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    session.standOnRow(LayerRowAddress(camera.id), frameIndex: 3);
    session.camera.setCameraKeyframeAtCurrentFrame(
      session.camera.cameraPoseAtCurrentFrame,
    );
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: camera.id,
      startIndex: 0,
      endIndexExclusive: 6,
      layerIds: [camera.id, drawingId],
    );
    expect(session.cellInstances.canEditCellInstanceAtCurrentFrame, isFalse);
  });

  testWidgets('the cell editor on an EMPTY lane cell opens nothing — the '
      "owner's cel is not the lane's instance", (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    final layerId = session.activeLayer!.id;
    session.standOnRow(LaneRowAddress(layerId, 'rotation'), frameIndex: 0);

    unawaited(
      activateCellEditor(context, session, layerId: layerId, frameIndex: 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RenameFrameDialog), findsNothing);
  });
}
