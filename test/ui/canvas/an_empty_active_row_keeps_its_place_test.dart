import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// 🚨★★★유저 확정 2026-09-04 (ARCH-active-node): **재생과 똑같이.**
///
/// The row being drawn on stands in the composite tree at ITS OWN PLACE —
/// inside its folder, at its z, with the folder's opacity on it. It used
/// to be appended at the top level by hand whenever it had no cel exposed
/// at the playhead, which lost all three: a stroke inside a 20% folder
/// drew at full strength on the canvas and at 20% in playback, and a
/// stroke inside a folder the user had switched off went on being drawn on
/// the canvas and nowhere else.
///
/// The case that matters is the EMPTY one: a row with a cel already
/// resolves an entry, so the plan placed it correctly all along.
void main() {
  ({EditorSessionManager session, LayerId folderId})
  sessionWithEmptyRowInFolder({
    double folderOpacity = 1,
    LayerBlendMode folderBlend = LayerBlendMode.passThrough,
  }) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    // A drawing row with a cel, folded into a folder — then step to a frame
    // where the row has nothing exposed, which is the whole case.
    s.createDrawingAtCurrentFrame();
    s.folders.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;
    if (folderBlend != LayerBlendMode.passThrough) {
      s.layerSwitches.setLayerBlendMode(folderId, folderBlend);
    }
    if (folderOpacity != 1) {
      s.opacityVerbs.setLayerOpacity(layerId: folderId, opacity: folderOpacity);
    }
    return (session: s, folderId: folderId);
  }

  CanvasActiveLayerRow? activeIn(List<CompositeNode<CanvasStackRow>> nodes) {
    for (final node in nodes) {
      if (node case CompositeLeaf(payload: final CanvasActiveLayerRow row)) {
        return row;
      }
      if (node is CompositeGroup<CanvasStackRow>) {
        final found = activeIn(node.children);
        if (found != null) {
          return found;
        }
      }
      if (node is CompositeAdjustment<CanvasStackRow>) {
        final found = activeIn(node.children);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  bool activeIsTopLevel(List<CompositeNode<CanvasStackRow>> nodes) => nodes.any(
    (node) =>
        node is CompositeLeaf<CanvasStackRow> &&
        node.payload is CanvasActiveLayerRow,
  );

  test('an EMPTY active row inside a buffering folder is INSIDE its group, '
      'not appended at the top', () {
    final made = sessionWithEmptyRowInFolder(folderOpacity: 0.2);
    final s = made.session;
    s.selectFrameIndex(40);

    final nodes = s.editingCanvasStack.nodes;
    expect(
      activeIn(nodes),
      isNotNull,
      reason: 'the row is still where the next stroke lands',
    );
    expect(
      activeIsTopLevel(nodes),
      isFalse,
      reason:
          'appended at the top level it would lose the folder buffer, '
          'the folder opacity and its z-position — the bug this closed',
    );
  });

  test('a hidden folder drops the EMPTY active row with the rest of its '
      'subtree', () {
    final made = sessionWithEmptyRowInFolder();
    final s = made.session;
    s.selectFrameIndex(40);

    expect(
      activeIn(s.editingCanvasStack.nodes),
      isNotNull,
      reason:
          'the premise: with the folder VISIBLE the row is in the tree — '
          'without this half the check below passes for a tree that has no '
          'live row at all',
    );

    s.layerSwitches.toggleLayerVisibility(made.folderId);

    expect(
      activeIn(s.editingCanvasStack.nodes),
      isNull,
      reason:
          'a switched-off folder hides what is inside it — the canvas '
          'used to go on drawing the active row anyway',
    );
  });

  test('the folder opacity reaches the empty active row', () {
    final made = sessionWithEmptyRowInFolder(
      folderOpacity: 0.2,
      folderBlend: LayerBlendMode.multiply,
    );
    final s = made.session;
    s.selectFrameIndex(40);

    final nodes = s.editingCanvasStack.nodes;
    final group = nodes.whereType<CompositeGroup<CanvasStackRow>>().single;
    expect(
      group.opacity,
      closeTo(0.2, 1e-9),
      reason: 'a buffering folder carries its own opacity on the group',
    );
    expect(
      activeIn(nodes),
      isNotNull,
      reason: 'and the live row sits inside that group',
    );
  });
}
