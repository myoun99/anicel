part of '../editor_session_manager.dart';

/// Maps the shared composite TREE onto the editing canvas's stack.
///
/// The cut layers ride the tree as it is (skip rules, fx sharing, the W5
/// attach-layer expansion AND the group buffers agree with playback by
/// construction); the ACTIVE row becomes a [CanvasActiveLayerNode] where
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

  CanvasLayerStackNode? map(CutFrameCompositeEntryNode node) => switch (node) {
    CutFrameCompositeEntryGroup() => _group(node),
    CutFrameCompositeEntryAdjustment() => _adjustment(node),
    CutFrameCompositeEntryLive() => _live(node),
    CutFrameCompositeEntryLeaf() => _leaf(node),
  };

  /// A folder's children, or null when every one of them was skipped —
  /// an empty group buffer is a `saveLayer` around nothing.
  List<CanvasLayerStackNode>? _childrenOf(
    List<CutFrameCompositeEntryNode> children,
  ) {
    final mapped = <CanvasLayerStackNode>[
      for (final child in children) ?map(child),
    ];
    // ⛔EQUIVALENT today — the shared tree already drops a folder whose
    // members are all skipped, so an empty list never reaches here, and
    // mutating this away leaves the suite green (2026-09-05). Kept as the
    // statement of what a group node MEANS: a buffer around nothing is a
    // `saveLayer` for nothing.
    return mapped.isEmpty ? null : List.unmodifiable(mapped);
  }

  CanvasLayerStackNode? _group(CutFrameCompositeEntryGroup node) {
    final children = _childrenOf(node.children);
    return children == null
        ? null
        : CanvasLayerGroupNode(
            children: children,
            opacity: node.opacity,
            blendMode: node.blendMode,
            effects: node.effects,
          );
  }

  CanvasLayerStackNode? _adjustment(CutFrameCompositeEntryAdjustment node) {
    final children = _childrenOf(node.children);
    return children == null
        ? null
        : CanvasLayerAdjustmentNode(
            children: children,
            effects: node.effects,
            mix: node.mix,
          );
  }

  /// The row being drawn on with NOTHING exposed at this frame — the plan
  /// still placed it, in its folder and at its z, so the first stroke
  /// lands where the picture says it should (유저 확정 2026-09-04: 재생과
  /// 똑같이). The hand-built block this replaced appended it at the top
  /// level and lost all three.
  CanvasLayerStackNode _live(CutFrameCompositeEntryLive node) {
    activeLayerOpacity = session._opacity.stackLayerOpacity(
      node.layer,
      stackCut.layers,
      frameIndex,
    );
    activeSourceEffects = splitSourceEffects(node.render.effects).source;
    return CanvasActiveLayerNode(
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
  CanvasLayerStackNode _leaf(CutFrameCompositeEntryLeaf node) {
    final entry = node.entry;
    if (entry.layer.id != activeLayerId ||
        !layerAcceptsBrushInput(entry.layer)) {
      return CanvasLayerImageNode(
        CanvasLayerImageRequest(
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
        ),
      );
    }
    activeLayerOpacity = !entry.layer.isVisible
        ? 0.0
        : session._opacity.stackLayerOpacity(
            entry.layer,
            stackCut.layers,
            frameIndex,
          );
    activeSourceEffects = splitSourceEffects(entry.effects).source;
    return CanvasActiveLayerNode(
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
