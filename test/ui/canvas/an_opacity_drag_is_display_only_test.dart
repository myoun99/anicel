import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R4 #4/#6, DISPLAY only: while an opacity slider is under the hand the
/// canvas follows it WITHOUT a repository write per move. The dragged
/// rows' static opacity is substituted into the cut the composite walk
/// reads, so the picture changes and the project does not.
///
/// Both halves of the substitution are pinned here, because the walk asks
/// twice: once for the cut's own layers and once for the TRACK-owned SE
/// rows, which live outside the cut's stack and join the tree at the top
/// level. The second one had no test — an SE row could have gone on
/// showing its stored opacity through the whole drag and nothing would
/// have said so.
void main() {
  test('a layer opacity drag reaches the editing stack and leaves the cut '
      'alone', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayerId!;

    expect(
      s.editingCanvas.stack.activeLayerOpacity,
      closeTo(1, 1e-9),
      reason: 'the premise: nothing is dragging yet',
    );

    s.opacityVerbs.previewLayerOpacity(layerId, 0.35);

    expect(
      s.editingCanvas.stack.activeLayerOpacity,
      closeTo(0.35, 1e-9),
      reason: 'the canvas follows the drag',
    );
    expect(
      s.requireActiveCut.layers.firstWhere((l) => l.id == layerId).opacity,
      closeTo(1, 1e-9),
      reason: 'DISPLAY only — no repo write per move',
    );

    s.opacityVerbs.commitLayerOpacity(layerId, 0.35);
    expect(
      s.requireActiveCut.layers.firstWhere((l) => l.id == layerId).opacity,
      closeTo(0.35, 1e-9),
      reason: 'the release is the one write',
    );
  });

  test('the drag reaches the TRACK SE rows too, which join the stack at the '
      'top level', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final seLayer = s.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    s.selectLayer(seLayer.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '쿵');

    double? seOpacityIn(EditorSessionManager session) {
      for (final node in session.editingCanvas.stack.nodes) {
        if (node case CompositeLeaf(payload: final CanvasLayerImageRequest r)
            when r.frameKey.layerId == seLayer.id) {
          return r.opacity;
        }
      }
      return null;
    }

    expect(
      seOpacityIn(s),
      closeTo(1, 1e-9),
      reason:
          'the premise: the SE row composites read-only in the stack at its '
          'stored opacity',
    );

    s.opacityVerbs.previewLayerOpacity(seLayer.id, 0.4);
    expect(
      seOpacityIn(s),
      closeTo(0.4, 1e-9),
      reason:
          'the SE rows go through the SAME substitution as the cut layers — '
          'asking the stored value here is how one row would sit still '
          'through a drag every other row followed',
    );
  });

  test('an SE row dragged to zero leaves the stack entirely', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final seLayer = s.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    s.selectLayer(seLayer.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '쿵');

    bool seIsDrawn() => s.editingCanvas.stack.nodes.any(
      (node) =>
          node is CompositeLeaf<CanvasStackRow> &&
          node.payload is CanvasLayerImageRequest &&
          (node.payload as CanvasLayerImageRequest).frameKey.layerId ==
              seLayer.id,
    );

    expect(seIsDrawn(), isTrue, reason: 'the premise: it is drawn at 1.0');

    s.opacityVerbs.previewLayerOpacity(seLayer.id, 0);
    expect(
      seIsDrawn(),
      isFalse,
      reason: 'a row at zero is not a transparent node, it is no node',
    );
  });
}
