part of '../editor_session_manager.dart';

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
    required this.session,
    required this.cut,
    required this.stackCut,
    required this.frameIndex,
    required this.activeLayerId,
  });

  final EditorSessionManager session;
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
    activeLayerOpacity = session.opacityVerbs.stackLayerOpacity(
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
        frameKey: session.brushFrameKeyForCut(
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
    activeLayerOpacity = !entry.layer.isVisible
        ? 0.0
        : session.opacityVerbs.stackLayerOpacity(
            entry.layer,
            stackCut.layers,
            frameIndex,
          );
    activeSourceEffects = splitSourceEffects(entry.effects).source;
    return CanvasActiveLayerRow(
      opacity: entry.opacity,
      // The active row's CEL key — the SAME key the image branch above
      // would have requested, so the stack can keep that route's image as
      // the first-activation stand-in while the promoted surface's tiles
      // decode.
      frameKey: session.brushFrameKeyForCut(
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
