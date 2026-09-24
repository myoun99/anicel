import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_paint.dart' show LayerPoseSample;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The pen maps through the placement the stack PAINTS the row with.
///
/// 🔬Measured before the fix (2026-09-25, `a-posed-folder-and-the-pen`):
/// inside a folder keyed to 2×, the draw-through wrap answered identity while
/// the stack painted the row at 2× — so a stroke landed where the folder then
/// moved it, away from the pen. Both now read `layerPlacementAt`.
void main() {
  const folder = LayerId('pen-folder');

  TransformTrack keyed(TransformPose pose) =>
      TransformTrack(keyframes: {0: pose});

  /// The drawing row made the member of [folderTrack]'s folder, and stood on.
  ({EditorSessionManager s, LayerId row}) inPosedFolder(
    TransformTrack folderTrack, {
    TransformTrack? rowTrack,
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    final row = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    s.repository.replaceLayer(
      layer: row.copyWith(
        folderId: folder,
        transformTrack: rowTrack ?? row.transformTrack,
      ),
    );
    final at = s.requireActiveCut.layers.indexWhere(
      (layer) => layer.id == row.id,
    );
    s.repository.insertLayer(
      cutId: cutId,
      layer: createFolderLayer(
        id: folder,
        name: 'F',
      ).copyWith(transformTrack: folderTrack),
      index: at + 1,
    );
    s.refreshAfterCutCommand();
    s.selectLayer(row.id);
    return (s: s, row: row.id);
  }

  /// The placement the merged stack paints the row being drawn on with.
  LayerPoseSample? painted(EditorSessionManager s) {
    CanvasActiveLayerRow? active;
    void walk(List<CompositeNode<CanvasStackRow>> nodes) {
      for (final node in nodes) {
        switch (node) {
          case CompositeLeaf(payload: final CanvasActiveLayerRow row):
            active = row;
          case CompositeGroup(:final children):
            walk(children);
          default:
        }
      }
    }

    walk(s.editingCanvas.stack.nodes);
    final row = active;
    expect(row, isNotNull, reason: 'fixture: the row is painted live');
    return row!.pose == null
        ? null
        : (pose: row.pose!, anchorPoint: row.anchorPoint);
  }

  final twice = TransformPose(center: CanvasPoint(x: 100, y: 100), zoom: 2);

  test('a row in a posed folder takes the pen through the folder\'s pose', () {
    final (:s, :row) = inPosedFolder(keyed(twice));

    final wrap = s.frameVerbs.layerCanvasPoseSample(row);
    expect(wrap, isNotNull, reason: 'the folder moves the row');
    expect(wrap, painted(s));
  });

  test('its own pose composes under the folder\'s, as the stack paints it', () {
    final (:s, :row) = inPosedFolder(
      keyed(twice),
      rowTrack: keyed(TransformPose(center: CanvasPoint(x: 40, y: 30), zoom: 3)),
    );

    final wrap = s.frameVerbs.layerCanvasPoseSample(row)!;
    expect(wrap, painted(s));
    expect(wrap.pose.zoom, 6, reason: 'zooms multiply');
  });

  test('a folder with its fx off moves nothing — the pen stays with the '
      'row\'s own pose', () {
    final (:s, :row) = inPosedFolder(keyed(twice));
    s.effectsAndFx.toggleLayerTransformFx(folder);

    expect(s.frameVerbs.layerCanvasPoseSample(row), isNull);
    expect(painted(s), isNull);
  });

  test('a HIDDEN folder still places its row: what is drawn inside lands '
      'where it shows once the folder is shown again', () {
    final (:s, :row) = inPosedFolder(keyed(twice));
    s.layerSwitches.toggleLayerVisibility(folder);
    final whileHidden = s.frameVerbs.layerCanvasPoseSample(row);

    s.layerSwitches.toggleLayerVisibility(folder);
    expect(whileHidden, painted(s));
  });
}
