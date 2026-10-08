import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_paint.dart' show LayerPlacement;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/placement_reading.dart';

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
  LayerPlacement? painted(EditorSessionManager s) {
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
    return row!.placement;
  }

  final twice = TransformPose.uniform(
    center: CanvasPoint(x: 100, y: 100),
    zoom: 2,
  );

  test('a row in a posed folder takes the pen through the folder\'s pose', () {
    final (:s, :row) = inPosedFolder(keyed(twice));

    final wrap = s.frameVerbs.layerCanvasPoseSample(row);
    expect(wrap, isNotNull, reason: 'the folder moves the row');
    expect(wrap, painted(s));
  });

  test('its own pose composes under the folder\'s, as the stack paints it', () {
    final (:s, :row) = inPosedFolder(
      keyed(twice),
      rowTrack: keyed(
        TransformPose.uniform(center: CanvasPoint(x: 40, y: 30), zoom: 3),
      ),
    );

    final wrap = s.frameVerbs.layerCanvasPoseSample(row)!;
    expect(wrap, painted(s));
    expect(wrap.evenScale, 6, reason: 'zooms multiply');
  });

  test('a folder with its fx off moves nothing — the pen stays with the '
      'row\'s own pose', () {
    final (:s, :row) = inPosedFolder(keyed(twice));
    s.effectsAndFx.toggleLayerTransformFx(folder);

    expect(s.frameVerbs.layerCanvasPoseSample(row), isNull);
    expect(painted(s), isNull);
  });

  test('an ATTACH row takes the pen through its base\'s pose — the fx it '
      'wears (W5)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!;
    s.laneVerbs.updateLayerTransformTrack(base.id, keyed(twice));
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!;
    expect(attach.id, isNot(base.id), reason: 'fixture: on the attach row');

    final wrap = s.frameVerbs.layerCanvasPoseSample(attach.id);
    expect(wrap, isNotNull, reason: 'the base is posed');
    expect(wrap, painted(s));
  });

  test('a HIDDEN folder still places its row: what is drawn inside lands '
      'where it shows once the folder is shown again', () {
    final (:s, :row) = inPosedFolder(keyed(twice));
    s.layerSwitches.toggleLayerVisibility(folder);
    final whileHidden = s.frameVerbs.layerCanvasPoseSample(row);

    s.layerSwitches.toggleLayerVisibility(folder);
    expect(whileHidden, painted(s));
  });

  // Every row above is stood on with NOTHING exposed — the live slot the
  // plan keeps for it. A row that holds a cel arrives as an entry instead,
  // and the stack map hands that entry's placement on with two more hands:
  // to the live row when the row is stood on, to its image when it is not.
  group('a row that HOLDS a cel at the playhead', () {
    const cel = FrameId('pen-cel');
    const beside = LayerId('pen-beside');

    /// The drawing row wearing [pose] and holding a cel, with an empty row
    /// above it to stand on instead.
    ({EditorSessionManager s, LayerId posed}) holdingACel(TransformPose pose) {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      s.repository.replaceLayer(
        layer: row.copyWith(
          frames: [Frame(id: cel, duration: 1, strokes: const [])],
          timeline: const {0: TimelineExposure.drawing(cel, length: 1)},
          transformTrack: keyed(pose),
        ),
      );
      final at = s.requireActiveCut.layers.indexWhere(
        (layer) => layer.id == row.id,
      );
      s.repository.insertLayer(
        cutId: s.requireActiveCut.id,
        layer: Layer(
          id: beside,
          name: 'B',
          frames: const [],
          timeline: const {},
        ),
        index: at + 1,
      );
      s.refreshAfterCutCommand();
      return (s: s, posed: row.id);
    }

    /// The placement the stack paints [layerId]'s IMAGE with.
    LayerPlacement? imagePlacement(EditorSessionManager s, LayerId layerId) {
      CanvasLayerImageRequest? image;
      void walk(List<CompositeNode<CanvasStackRow>> nodes) {
        for (final node in nodes) {
          switch (node) {
            case CompositeLeaf(payload: final CanvasLayerImageRequest row)
                when row.frameKey.layerId == layerId:
              image = row;
            case CompositeGroup(:final children):
              walk(children);
            default:
          }
        }
      }

      walk(s.editingCanvas.stack.nodes);
      expect(image, isNotNull, reason: 'fixture: the row is an image');
      return image!.placement;
    }

    test('stood on, it is painted live through its pose', () {
      final (:s, :posed) = holdingACel(twice);
      s.selectLayer(posed);

      final wrap = s.frameVerbs.layerCanvasPoseSample(posed);
      expect(wrap, isNotNull, reason: 'the row is posed');
      expect(painted(s), wrap);
    });

    test('stood beside, its image is painted through the same pose', () {
      final (:s, :posed) = holdingACel(twice);
      s.selectLayer(beside);

      final wrap = s.frameVerbs.layerCanvasPoseSample(posed);
      expect(wrap, isNotNull, reason: 'the row is posed');
      expect(imagePlacement(s, posed), wrap);
    });
  });
}
