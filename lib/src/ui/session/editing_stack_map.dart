import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../canvas/canvas_layer_stack_view.dart';
import 'opacity_verbs.dart';
import 'session_roles.dart';

/// Maps the shared composite TREE onto the editing canvas's stack.
///
/// The cut layers ride the tree as it is (skip rules, fx sharing, the W5
/// attach-layer expansion AND the group buffers agree with playback by
/// construction); the ACTIVE row becomes a [CanvasActiveLayerRow] where
/// the tree placed it.
///
/// ⛔It also CARRIES OUT two facts about the active row — its display
/// opacity and its source effects — because this walk is where the
/// active node's chain is already resolved. Asking a second time
/// somewhere else is how the panel and the stack would come to disagree.
class EditingStackMap {
  EditingStackMap({
    required OpacityVerbs opacityVerbs,
    required SessionInternals internals,
    required this.cut,
    required this.stackCut,
    required this.frameIndex,
    required this.activeLayerId,
  }) : _opacityVerbs = opacityVerbs,
       _internals = internals;

  final OpacityVerbs _opacityVerbs;
  final SessionInternals _internals;
  final Cut cut;
  final Cut stackCut;
  final int frameIndex;
  final LayerId? activeLayerId;

  double activeLayerOpacity = 1.0;

  /// 🚨THE ACTIVE ROW'S CPU HALF, CARRIED OUT WITH THE OPACITY.
  ///
  /// The row you are DRAWING on is painted tile by tile by the brush
  /// panel's own painter, which never sees a CutFrameCompositeLayer and
  /// never asks the image cache — the two places the colour keys are
  /// applied. Without this the keyed colour comes back the moment you
  /// stand on the row, and goes again when you step off: exactly the
  /// "발신자에 따라 길이 갈렸다" shape #1280 was about.
  List<ResolvedLayerEffect> activeSourceEffects = const <ResolvedLayerEffect>[];

  /// The tree the plan resolved, with each ROW turned into the stack node
  /// that draws it — the shared fold carries the "a group left empty is a
  /// `saveLayer` around nothing" law.
  List<CompositeNode<CanvasStackRow>> mapTree(
    List<CompositeNode<CutFrameCompositeRow>> nodes,
  ) => mapCompositeLeaves(
    nodes,
    (row) => switch (row) {
      CutFrameCompositeLiveRow() => _live(row),
      CutFrameCompositeEntry() => _leaf(row),
    },
  );

  /// The row being drawn on with NOTHING exposed at this frame — the plan
  /// still placed it, in its folder and at its z, so the first stroke
  /// lands where the picture says it should (유저 확정 2026-09-04: 재생과
  /// 똑같이). The hand-built block this replaced appended it at the top
  /// level and lost all three.
  CanvasStackRow _live(CutFrameCompositeLiveRow node) {
    activeLayerOpacity = _opacityVerbs.stackLayerOpacity(
      node.layer,
      stackCut.layers,
      frameIndex,
    );
    activeSourceEffects = splitSourceEffects(node.render.effects).source;
    return CanvasActiveLayerRow(
      opacity: node.render.opacity,
      blendMode: node.render.blendMode,
      pose: node.render.placement?.pose,
      anchorPoint: node.render.placement?.anchorPoint,
      effects: node.render.effects,
    );
  }

  /// A cached row — or the ACTIVE one when the brush cannot draw on it.
  ///
  /// A brush-banned active layer (SE/instruction, R6-④; a media REFERENCE
  /// layer, §6-z23) has no interactive surface — it composites like any
  /// other stack row so its existing cels keep displaying read-only.
  CanvasStackRow _leaf(CutFrameCompositeEntry entry) {
    if (entry.layer.id != activeLayerId ||
        !layerAcceptsBrushInput(entry.layer)) {
      return CanvasLayerImageRequest(
        frameKey: _internals.brushFrameKeyForCut(
          cut,
          entry.layer.id,
          entry.frame.id,
        ),
        opacity: entry.opacity,
        blendMode: entry.blendMode,
        pose: entry.pose,
        anchorPoint: entry.anchorPoint,
        effects: entry.effects,
      );
    }
    // ⛔MUTANT SURVIVES ON THE HIDDEN-ROW ARM BELOW, and the classification
    // is NEVER APPLIED (2026-09-08): `_resolveLayerNode` asks the row's own
    // eye BEFORE it builds an entry, so a hidden row never reaches this
    // walk at all — no entry, no leaf, no active node. Kept as the local
    // statement of "the eye is off ⇒ nothing shows" for a caller that hands
    // this map a tree built some other way.
    activeLayerOpacity = !entry.layer.isVisible
        ? 0.0
        : _opacityVerbs.stackLayerOpacity(
            entry.layer,
            stackCut.layers,
            frameIndex,
          );
    activeSourceEffects = splitSourceEffects(entry.effects).source;
    return CanvasActiveLayerRow(
      opacity: entry.opacity,
      // The active row's CEL key — the SAME key the image branch above
      // asks with. The build in which this cel leaves the active slot, the
      // stack reads it off the widget it replaces and composes the cel's
      // image on the spot, so the row does not go blank for the frames an
      // asynchronous build takes ([CanvasActiveLayerRow.frameKey]).
      frameKey: _internals.brushFrameKeyForCut(
        cut,
        entry.layer.id,
        entry.frame.id,
      ),
      // The SAME entry the image branch above reads it from. It was
      // dropped right here — five fields arrived and four were forwarded,
      // so standing on a multiply row silently made it normal on the
      // editing canvas only.
      blendMode: entry.blendMode,
      pose: entry.pose,
      anchorPoint: entry.anchorPoint,
      effects: entry.effects,
    );
  }
}
