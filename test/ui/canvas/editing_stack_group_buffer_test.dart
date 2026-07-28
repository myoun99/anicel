import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The EDITING canvas composites the same tree playback does, so a folder
/// buffer looks the same while you draw as it will when you play.
///
/// The one exception is stated in the split's own contract and pinned
/// here: the folder that CONTAINS the active layer cannot buffer while the
/// canvas paints in three sibling widgets, so it alone folds per member.
void main() {
  EditorSessionManager sessionWithFolder({
    LayerBlendMode blend = LayerBlendMode.passThrough,
    double opacity = 1,
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    s.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;
    if (blend != LayerBlendMode.passThrough) {
      s.setLayerBlendMode(folderId, blend);
    }
    if (opacity != 1) {
      s.setLayerOpacity(layerId: folderId, opacity: opacity);
    }
    return s;
  }

  int countGroups(List<CanvasLayerStackNode> nodes) {
    var total = 0;
    for (final node in nodes) {
      if (node is CanvasLayerGroupNode) {
        total += 1 + countGroups(node.children);
      }
    }
    return total;
  }

  bool holdsActive(List<CanvasLayerStackNode> nodes) => nodes.any(
    (node) =>
        node is CanvasActiveLayerNode ||
        (node is CanvasLayerGroupNode && holdsActive(node.children)),
  );

  test('a PASS-THROUGH folder produces no group node on the editing canvas '
      'either — an organizing folder costs nothing anywhere', () {
    final s = sessionWithFolder();
    expect(countGroups(s.editingCanvasStack.nodes), 0);
  });

  test('the ACTIVE layer stands in the tree as its own node', () {
    final s = sessionWithFolder();
    expect(
      holdsActive(s.editingCanvasStack.nodes),
      isTrue,
      reason: 'the merged painter needs a place to draw the live surface',
    );
  });

  test('the folder CONTAINING the active layer buffers too — the merged '
      'painter closes the saveLayer it opened', () {
    final s = sessionWithFolder(blend: LayerBlendMode.multiply);
    final nodes = s.editingCanvasStack.nodes;

    expect(countGroups(nodes), 1);
    final group = nodes.whereType<CanvasLayerGroupNode>().single;
    expect(group.blendMode, LayerBlendMode.multiply);
    expect(
      holdsActive(group.children),
      isTrue,
      reason: 'the layer being drawn on sits INSIDE the buffer — this is '
          'what the three-sibling-painter split could never express',
    );
  });

  test('inside a buffering folder the member carries no folder state — it '
      'is on the buffer, so nothing double-applies', () {
    final s = sessionWithFolder(blend: LayerBlendMode.multiply, opacity: 0.5);
    final group = s.editingCanvasStack.nodes
        .whereType<CanvasLayerGroupNode>()
        .single;
    expect(group.opacity, closeTo(0.5, 1e-9));
    expect(group.blendMode, LayerBlendMode.multiply);

    final active = group.children.whereType<CanvasActiveLayerNode>().single;
    expect(
      active.opacity,
      1,
      reason: 'the folder opacity belongs to the buffer, not the member',
    );
  });

  test('a group NOT containing the active layer buffers as well', () {
    final s = sessionWithFolder();
    final cut = s.activeCutOrNull!;
    final outside = cut.layers.firstWhere(
      (layer) => layer.folderId == null && layer.id != s.activeLayerId,
    );
    final folderId = cut.layers.folderLayers.single.id;
    s.setLayerBlendMode(folderId, LayerBlendMode.multiply);
    s.selectLayer(outside.id);

    expect(countGroups(s.editingCanvasStack.nodes), 1);
  });
}
