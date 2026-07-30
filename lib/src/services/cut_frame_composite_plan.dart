import '../models/attached_layer_resolve.dart';
import '../models/bitmap_surface.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/frame.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_folder.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/timeline_coverage.dart';
import '../models/transform_track.dart';
import '../ui/canvas/layer_pose_paint.dart';

/// One paintable layer of a composited cut frame, bottom → top order.
class CutFrameCompositeLayer {
  const CutFrameCompositeLayer({
    required this.surface,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  final BitmapSurface surface;

  /// The layer's composite blend against everything below (R26 #30).
  final LayerBlendMode blendMode;

  /// The layer's EFFECTIVE opacity: static layer opacity × animated
  /// Opacity sample × every enclosing folder's effective opacity (folded
  /// per member; overlapping members inside one translucent folder
  /// double-blend — see [resolveFolderChainAt] for why the exact buffered
  /// group is still a later slice).
  final double opacity;

  /// The layer's transform at this frame — WITH every enclosing folder's
  /// FX composed outside it (폴더째 이동); null = identity (no transform
  /// work — the overwhelmingly common case skips the canvas
  /// save/restore).
  final TransformPose? pose;

  /// The pose's anchor point; null = canvas center (see
  /// applyLayerPoseTransform).
  final CanvasPoint? anchorPoint;

  /// The layer's EFFECT CHAIN sampled at this frame (R6), applied over the
  /// row's own picture before its opacity/blend meet the stack. Empty for
  /// every layer that carries no effects — the common case, which costs no
  /// filter at all.
  final List<ResolvedLayerEffect> effects;
}

/// A layer's identity pose: content centered, unscaled, unrotated — the
/// same canvas-centered shape the camera defaults to, so an empty track
/// composites exactly as before.
TransformPose layerIdentityPose(CanvasSize canvasSize) => TransformPose(
  center: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
);

/// The layer's resolved GEOMETRIC pose at [frameIndex]; null while the
/// geometric tracks (anchor/position/scale/rotation) are empty — an
/// animated Opacity alone never forces the transform path. Shared by the
/// composite plan, the composite cache signature and the editing canvas's
/// layer stack so every route agrees.
TransformPose? resolveLayerPoseAt({
  required Layer layer,
  required CanvasSize canvasSize,
  required int frameIndex,
}) {
  final track = layer.transformTrack;
  if (track.anchorPoint.isEmpty &&
      track.position.isEmpty &&
      track.scale.isEmpty &&
      track.rotation.isEmpty) {
    return null;
  }
  return track.resolveAt(
    frameIndex: frameIndex,
    orElse: () => layerIdentityPose(canvasSize),
  );
}

/// The layer's resolved anchor point at [frameIndex]; null = canvas center
/// (the anchor-point lane's empty-track default).
CanvasPoint? resolveLayerAnchorPointAt({
  required Layer layer,
  required int frameIndex,
}) {
  return resolveAnchorTrackAt(layer.transformTrack.anchorPoint, frameIndex);
}

/// The layer's effective opacity at [frameIndex]: static layer opacity ×
/// the animated Opacity sample (1 while unkeyed), clamped to 0..1.
double resolveLayerEffectiveOpacityAt({
  required Layer layer,
  required int frameIndex,
}) {
  return (layer.opacity *
          resolveOpacityTrackAt(layer.transformTrack.opacity, frameIndex))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Resolves the drawable surface for a layer's frame (e.g. by replaying the
/// brush store's paint commands); `null` when the frame has no artwork.
typedef LayerFrameSurfaceResolver =
    BitmapSurface? Function(Layer layer, Frame frame);

/// One resolved contributor to the cut's picture at a frame — the SHARED
/// visit both the composite plan and the composite cache signature consume,
/// so every route (playback, export, thumbnails, editing stack) agrees on
/// skip rules, exposure resolution AND the attach-layer expansion by
/// construction.
class CutFrameCompositeEntry {
  const CutFrameCompositeEntry({
    required this.layer,
    required this.frame,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  final Layer layer;
  final Frame frame;
  final double opacity;

  /// The layer's composite blend against everything below (R26 #30).
  final LayerBlendMode blendMode;

  /// The layer's transform at this frame — WITH every enclosing folder's
  /// FX composed outside it (L3); null = identity.
  final TransformPose? pose;
  final CanvasPoint? anchorPoint;

  /// The row's effect chain sampled at this frame (R6) — from the FX
  /// CARRIER, so an attach row wears its base's effects exactly as it wears
  /// its base's pose, and the carrier's fx switch bypasses both.
  final List<ResolvedLayerEffect> effects;
}

/// One node of a cut frame's composite TREE, bottom → top: an entry that
/// paints, or a FOLDER's group buffer holding the ones inside it.
///
/// Built by [resolveCutFrameCompositeTree] and mapped — never rebuilt —
/// into the shapes the routes need: surfaces for the paint routes
/// ([planCutFrameComposite]) and identities for the playback cache
/// ([computeCutFrameCompositeSignature]). One structure, so playback,
/// export and the editing canvas cannot drift.
sealed class CutFrameCompositeEntryNode {
  const CutFrameCompositeEntryNode();
}

final class CutFrameCompositeEntryLeaf extends CutFrameCompositeEntryNode {
  const CutFrameCompositeEntryLeaf(this.entry);

  final CutFrameCompositeEntry entry;
}

/// A FOLDER's GROUP BUFFER (R27 #29, 유저 확정: "그룹 한번합쳐서 한번
/// 블렌드"). [children] compose into one buffer, and only then does the
/// folder's [opacity] and [blendMode] apply — once, to that buffer. So
/// overlapping members inside a multiply folder read as one picture
/// instead of darkening where they cross.
///
/// Only a folder that NEEDS a buffer becomes one of these
/// ([folderNeedsCompositeBuffer]); a plain pass-through folder leaves no
/// node at all and its members sit directly in the parent's list.
final class CutFrameCompositeEntryGroup extends CutFrameCompositeEntryNode {
  const CutFrameCompositeEntryGroup({
    required this.folder,
    required this.children,
    required this.opacity,
    required this.blendMode,
    this.effects = const [],
  });

  final Layer folder;

  /// Bottom → top; may hold nested groups.
  final List<CutFrameCompositeEntryNode> children;

  /// The FOLDER's effective opacity (static × animated sample).
  final double opacity;

  /// The FOLDER's blend against everything below the group.
  final LayerBlendMode blendMode;

  /// The FOLDER's effect chain sampled at this frame (R6), applied ONCE to
  /// the composed buffer — which is the whole reason effects force a folder
  /// to buffer ([folderNeedsCompositeBuffer]): a blur over the group is not
  /// the same picture as a blur over each member.
  final List<ResolvedLayerEffect> effects;
}

/// An ADJUSTMENT layer's SCOPE (R6b): everything composited below the row,
/// composed into one buffer so the row's [effects] can filter it as the
/// single picture it is.
///
/// The scope is decided by the folder rules Photoshop and CSP already
/// taught the stack (§6-z3): the walk collects every sibling below the
/// adjustment, keeps going OUT through pass-through folders (통과 — the
/// adjustment leaks past them, filtering what lies below the folder too)
/// and stops at the first BUFFERING one, whose buffer is a picture of its
/// own that nothing inside it can reach past.
///
/// [mix] is the row's opacity, and it means MIX, not fade: 0.5 is a
/// half-strength grade, never a half-transparent stack. See
/// [resolveAdjustmentScopePass] for how a route paints that.
final class CutFrameCompositeEntryAdjustment
    extends CutFrameCompositeEntryNode {
  const CutFrameCompositeEntryAdjustment({
    required this.adjustment,
    required this.children,
    required this.effects,
    required this.mix,
  });

  final Layer adjustment;

  /// Everything in scope, bottom → top; may hold nested groups.
  final List<CutFrameCompositeEntryNode> children;

  /// The row's chain sampled at this frame — never empty (an adjustment
  /// that resolves to nothing leaves no node at all).
  final List<ResolvedLayerEffect> effects;

  /// The effect MIX, 0…1 (the row's static opacity).
  final double mix;
}

/// Whether [folder] must compose into its own buffer at [frameIndex].
///
/// Three things, and only three, fail to distribute over compositing:
/// - a BLEND other than pass-through (there is nothing to blend until the
///   group exists),
/// - an OPACITY below 1 — `0.5·(A over B)` is not `(0.5·A) over (0.5·B)`
///   where A and B overlap, which is exactly the double-darkening the
///   per-member fold produced, and
/// - any EFFECT (R6): a filter reads the pixels it is given, so
///   `blur(A over B)` is not `blur(A) over blur(B)` and `bright(A over B)`
///   is not `bright(A) over bright(B)` wherever they overlap.
///
/// A POSE is deliberately NOT in the list: an affine transform DOES
/// distribute (`T(A over B) == T(A) over T(B)`), so folder FX keeps riding
/// each member's pose and costs no buffer. A plain organizing folder
/// therefore allocates nothing at all — the Photoshop/CSP 통과 default.
bool folderNeedsCompositeBuffer({
  required Layer folder,
  required int frameIndex,
}) {
  if (folder.blendMode.isolatesGroup) {
    return true;
  }
  if (resolveFolderEffectsAt(
    folder: folder,
    frameIndex: frameIndex,
  ).isNotEmpty) {
    return true;
  }
  return resolveFolderOpacityAt(
        folder: folder,
        frameIndex: frameIndex,
      ) <
      1.0;
}

/// A folder's own effect chain at [frameIndex].
///
/// R8: every effect carries its OWN switch ([LayerEffect.enabled]), so
/// there is nothing row-wide left to ask here. The layer-label master turns
/// those switches off, which is what makes "bypass this row" and "bypass
/// this one effect" the same mechanism instead of two that behave
/// differently.
List<ResolvedLayerEffect> resolveFolderEffectsAt({
  required Layer folder,
  required int frameIndex,
}) {
  return resolveLayerEffectsAt(effects: folder.effects, frameIndex: frameIndex);
}

/// A folder's own effective opacity at [frameIndex]: static × the animated
/// Opacity sample (1 while the row's TRANSFORM switch is off — an animated
/// opacity is transform FX; the STATIC one is a display property and stays).
double resolveFolderOpacityAt({
  required Layer folder,
  required int frameIndex,
}) {
  return (folder.opacity *
          (folder.transformEnabled
              ? resolveOpacityTrackAt(folder.transformTrack.opacity, frameIndex)
              : 1.0))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// A folder chain's composite-relevant state at [frameIndex]: whether the
/// subtree shows at all, the folded opacity factor (each folder's static
/// opacity × its animated Opacity sample), and the folder poses to apply
/// outermost-first. Folder FX lanes are per-use ("레인만 각자") — this
/// resolves THIS cut's folder rows.
///
/// A folder row carries [Layer.transformEnabled] like any other row: the
/// folder fx switch IS the layer fx switch.
({
  bool visible,
  double opacityFactor,
  LayerBlendMode blendMode,
  List<LayerPoseSample> poses,
})
resolveFolderChainAt({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
  /// When false, a BUFFERING folder's opacity and blend are left out —
  /// they belong to its [CutFrameCompositeEntryGroup] instead. Poses fold
  /// either way (see [folderNeedsCompositeBuffer] for why).
  bool foldBufferedFolders = true,
}) {
  final chain = cut.layers.ancestryOf(layer.folderId);
  if (chain.isEmpty) {
    return (
      visible: true,
      opacityFactor: 1.0,
      blendMode: LayerBlendMode.normal,
      poses: const [],
    );
  }
  var opacityFactor = 1.0;
  // R27 #29: the nearest ISOLATING folder wins for the members below it.
  // A pass-through folder contributes no blend at all — that is the whole
  // meaning of 통과. Flat-path limitation: an isolating folder's mode
  // rides each member's own composite draw rather than a folder-wide
  // buffer, so overlapping members blend individually.
  var chainBlend = LayerBlendMode.normal;
  final poses = <LayerPoseSample>[];
  // ancestryOf is nearest-first; walk reversed so poses apply outermost
  // first (the outer folder moves the inner one too).
  for (final folder in chain.reversed) {
    if (!folder.isVisible) {
      return (
        visible: false,
        opacityFactor: 0.0,
        blendMode: LayerBlendMode.normal,
        poses: const [],
      );
    }
    // A folder that owns a BUFFER carries its own opacity and blend on
    // that buffer; folding them here as well would apply them twice.
    final buffered =
        !foldBufferedFolders &&
        folderNeedsCompositeBuffer(
          folder: folder,
          frameIndex: frameIndex,
        );
    if (!buffered &&
        folder.blendMode.isolatesGroup &&
        folder.blendMode != LayerBlendMode.normal) {
      chainBlend = folder.blendMode;
    }
    // R28 #13: a BYPASSED folder contributes no FX — no pose, no animated
    // opacity — the layer fx switch's exact contract. Its static opacity
    // and blend are display properties, not FX, so they stay (matching a
    // bypassed layer, whose static opacity also survives).
    final fxEnabled = folder.transformEnabled;
    if (!buffered) {
      opacityFactor *=
          (folder.opacity *
                  (fxEnabled
                      ? resolveOpacityTrackAt(
                          folder.transformTrack.opacity,
                          frameIndex,
                        )
                      : 1.0))
              .clamp(0.0, 1.0);
    }
    if (!fxEnabled) {
      continue;
    }
    final track = folder.transformTrack;
    final hasGeometry =
        track.anchorPoint.isNotEmpty ||
        track.position.isNotEmpty ||
        track.scale.isNotEmpty ||
        track.rotation.isNotEmpty;
    if (hasGeometry) {
      poses.add((
        pose: track.resolveAt(
          frameIndex: frameIndex,
          orElse: () => layerIdentityPose(cut.canvasSize),
        ),
        anchorPoint: resolveAnchorTrackAt(track.anchorPoint, frameIndex),
      ));
    }
  }
  return (
    visible: true,
    opacityFactor: opacityFactor,
    blendMode: chainBlend,
    poses: List.unmodifiable(poses),
  );
}

/// [layerSample] with the folder chain's poses composed OUTSIDE it via
/// [composeLayerPoseSamples] — ONE pose per entry, so every consumer
/// (composite cache, camera renders, editing stack, signatures) applies
/// folder FX with zero changes. Null when neither the folders nor the
/// layer carry geometry.
LayerPoseSample? composeFolderAndLayerPose({
  required List<LayerPoseSample> folderPoses,
  required LayerPoseSample? layerSample,
  required CanvasSize canvasSize,
}) {
  if (folderPoses.isEmpty) {
    return layerSample;
  }
  var combined =
      layerSample ??
      (pose: layerIdentityPose(canvasSize), anchorPoint: null as CanvasPoint?);
  // Fold innermost-outward: outer ∘ (… ∘ (inner ∘ layer)).
  for (final folderPose in folderPoses.reversed) {
    combined = composeLayerPoseSamples(folderPose, combined, canvasSize);
  }
  return combined;
}

/// The visible contributors at [frameIndex], bottom → top.
///
/// Layers are visited in list order (first = bottom, later layers draw on
/// top, matching "add layer above"). The camera layer, hidden layers and
/// fully transparent layers are skipped. Exposure resolution matches the
/// timeline: the drawing block covering [frameIndex] shows; uncovered
/// cells contribute nothing.
///
/// ATTACH LAYERS (W5) ride their base: the cel resolves through the base's
/// exposure + the cell link, the POSE and the animated-opacity sample come
/// from the BASE's transform track (fx shared — the base's fx switch
/// governs both), while the eye, static opacity and cels stay the attach
/// layer's own. VISIBILITY is fully independent (UI-R24 #5): hiding the
/// base hides ONLY the base's own picture — its attach rows keep
/// compositing under their own eyes. Dangling links contribute nothing.
/// The layer list keeps attach layers adjacent to their base, so plain
/// list order already yields [below…, base, above…].
///
/// A row whose [Layer.transformEnabled] is false composes with its
/// TRANSFORM ignored — identity pose, no animated opacity. Its effects are
/// gated one level down, by each [LayerEffect.enabled]; the layer-label fx
/// button is the MASTER that writes both (R8).
///
/// Enclosing FOLDERS fold into the entry: a folder's opacity multiplies
/// into the member's, its blend substitutes for a member that sets none,
/// and its FX poses compose outside the member's. That is a flat
/// APPROXIMATION of the group buffer R27 #29 asks for — see
/// [resolveFolderChainAt].
List<CutFrameCompositeEntry> resolveCutFrameCompositeEntries({
  required Cut cut,
  required int frameIndex,
  bool foldBufferedFolders = true,
}) {
  final entries = <CutFrameCompositeEntry>[];
  for (final layer in cut.layers) {
    // Folder rows composite their MEMBERS, not a surface of their own —
    // their eye/opacity/blend/FX reach the picture through
    // [resolveFolderChainAt] (flat) or [CutFrameCompositeGroup] (tree).
    if (!layerKindPaintsArtwork(layer.kind)) {
      continue;
    }
    final base = isAttachedLayer(layer)
        ? attachedBaseOf(layer, cut.layers)
        : null;
    if (isAttachedLayer(layer) && base == null) {
      // Dangling attach link (base gone): the row contributes nothing.
      continue;
    }
    // Each row's OWN eye and static opacity gate it — the base's eye
    // never cascades (UI-R24 #5: hiding the base hides only the base's
    // own picture; its attach rows stay independent).
    if (!layer.isVisible || layer.opacity <= 0) {
      continue;
    }
    // Folder gates: a hidden ancestor hides the subtree; folder opacity
    // folds into the member's, folder poses ride the entry.
    final folderChain = resolveFolderChainAt(
      cut: cut,
      layer: layer,
      frameIndex: frameIndex,
      foldBufferedFolders: foldBufferedFolders,
    );
    if (!folderChain.visible) {
      continue;
    }
    final fxCarrier = base ?? layer;
    final fxEnabled = fxCarrier.transformEnabled;
    final opacity =
        ((fxEnabled
                    ? layer.opacity *
                          resolveOpacityTrackAt(
                            fxCarrier.transformTrack.opacity,
                            frameIndex,
                          )
                    : layer.opacity) *
                folderChain.opacityFactor)
            .clamp(0.0, 1.0)
            .toDouble();
    if (opacity <= 0) {
      continue;
    }

    // SYNCED attach cels resolve through the base's exposure + the cell
    // links; FREE attach rows (UI-R21 #3) expose their OWN timeline like
    // a normal layer — the base still carries eye cascade and FX above.
    final frame = base == null || !isSyncedAttachedLayer(layer)
        ? resolveExposedFrameAt(layer, frameIndex)
        : resolveAttachedFrameAt(
            attached: layer,
            base: base,
            frameIndex: frameIndex,
          );
    if (frame == null) {
      continue;
    }

    final layerPose = fxEnabled
        ? resolveLayerPoseAt(
            layer: fxCarrier,
            canvasSize: cut.canvasSize,
            frameIndex: frameIndex,
          )
        : null;
    // R6: effects ride the FX carrier exactly like the pose and the
    // animated opacity — an attach row wears its base's chain, and the
    // carrier's fx switch bypasses it.
    // R8: NOT gated on fxEnabled — that switch is the TRANSFORM group's.
    // Each effect carries its own ([LayerEffect.enabled]) and the master
    // writes them all, so gating here too would make the row switch reach
    // effects it had not turned off.
    final effects = resolveLayerEffectsAt(
      effects: fxCarrier.effects,
      frameIndex: frameIndex,
    );
    final combined = composeFolderAndLayerPose(
      folderPoses: folderChain.poses,
      layerSample: layerPose == null
          ? null
          : (
              pose: layerPose,
              anchorPoint: fxEnabled
                  ? resolveLayerAnchorPointAt(
                      layer: fxCarrier,
                      frameIndex: frameIndex,
                    )
                  : null,
            ),
      canvasSize: cut.canvasSize,
    );
    entries.add(
      CutFrameCompositeEntry(
        layer: layer,
        frame: frame,
        opacity: opacity,
        // The blend is the ROW's own (attach rows keep theirs — their
        // pixels are independent even when timing rides the base); a
        // member that sets none inherits its folder's (R27 #29).
        blendMode: layer.blendMode == LayerBlendMode.normal
            ? folderChain.blendMode
            : layer.blendMode,
        pose: combined?.pose,
        anchorPoint: combined?.anchorPoint,
        effects: effects,
      ),
    );
  }
  return entries;
}

/// Lowers an ADJUSTMENT row into the tree being built (R6b): the node that
/// wraps everything in its scope, and the bucket that node belongs to.
/// Null when the row filters nothing — hidden, bypassed, no effects, mix 0,
/// or simply nothing below it yet.
///
/// ★ The one-pass trick. A pass-through folder's members are re-parented
/// only when the walk REACHES the folder row, which sits ABOVE them — so at
/// the moment an adjustment inside that folder is visited, its siblings are
/// still in the folder's own bucket while the rows below the folder sit in
/// the parent's. Both are "below" in the flattened stack the user sees, and
/// [folderNeedsCompositeBuffer] is a pure function of the folder (it needs
/// no children), so the walk can decide RIGHT HERE how far the scope
/// reaches and take those buckets. Buckets are emptied as they are taken,
/// so the rows that arrive after the adjustment land on top of the wrap,
/// unfiltered — exactly the picture the stack shows.
({CutFrameCompositeEntryNode node, LayerId? targetFolderId})?
_adjustmentScopeNode({
  required Layer adjustment,
  required Cut cut,
  required int frameIndex,
  required Map<LayerId?, List<CutFrameCompositeEntryNode>> childrenOf,
}) {
  if (!adjustment.isVisible) {
    return null;
  }
  // A hidden ancestor hides this row with everything else in its subtree.
  if (!resolveFolderChainAt(
    cut: cut,
    layer: adjustment,
    frameIndex: frameIndex,
  ).visible) {
    return null;
  }
  final mix = adjustment.opacity.clamp(0.0, 1.0).toDouble();
  if (mix <= 0) {
    return null;
  }
  // R8: per-effect switches gate this, like every other row's chain.
  final effects = resolveLayerEffectsAt(
    effects: adjustment.effects,
    frameIndex: frameIndex,
  );
  if (effects.isEmpty) {
    return null;
  }

  // The buckets in scope, INNERMOST first: this row's own, then outward
  // through every pass-through ancestor, stopping at (and including) the
  // first that buffers — its buffer is a picture of its own and nothing
  // inside it reaches past. Reaching the top level with none buffering
  // adds the top-level bucket.
  final scopeKeys = <LayerId?>[];
  var stoppedAtBuffer = false;
  for (final folder in cut.layers.ancestryOf(adjustment.folderId)) {
    scopeKeys.add(folder.id);
    if (folderNeedsCompositeBuffer(
      folder: folder,
      frameIndex: frameIndex,
    )) {
      stoppedAtBuffer = true;
      break;
    }
  }
  if (!stoppedAtBuffer) {
    scopeKeys.add(null);
  }

  // Outermost bucket first: a folder's members are one contiguous run, so
  // everything already gathered in an OUTER bucket sits below that run.
  final children = <CutFrameCompositeEntryNode>[
    for (final key in scopeKeys.reversed) ...?childrenOf.remove(key),
  ];
  if (children.isEmpty) {
    return null; // Nothing below to filter.
  }
  return (
    node: CutFrameCompositeEntryAdjustment(
      adjustment: adjustment,
      children: List.unmodifiable(children),
      effects: effects,
      mix: mix,
    ),
    targetFolderId: scopeKeys.last,
  );
}

/// The cut's picture at [frameIndex] as a TREE, bottom → top: every
/// visible entry, with each BUFFERING folder's members wrapped in a
/// [CutFrameCompositeEntryGroup] so the folder's opacity and blend apply
/// ONCE to their composed buffer (R27 #29), and each ADJUSTMENT row's
/// scope wrapped in a [CutFrameCompositeEntryAdjustment] (R6b).
///
/// The stack list IS the structure: a folder's members occupy a
/// contiguous run with the folder row directly above it, so this single
/// bottom-to-top pass has already collected every child by the time it
/// reaches the folder. A plain pass-through folder leaves no node — its
/// members simply belong to the parent, which is what makes an organizing
/// folder cost exactly nothing.
List<CutFrameCompositeEntryNode> resolveCutFrameCompositeTree({
  required Cut cut,
  required int frameIndex,
}) {
  final entryByLayerId = {
    for (final entry in resolveCutFrameCompositeEntries(
      cut: cut,
      frameIndex: frameIndex,
      foldBufferedFolders: false,
    ))
      entry.layer.id: entry,
  };

  // folder id (null = top level) → the nodes gathered under it so far.
  final childrenOf = <LayerId?, List<CutFrameCompositeEntryNode>>{};
  void addTo(LayerId? folderId, CutFrameCompositeEntryNode node) =>
      (childrenOf[folderId] ??= <CutFrameCompositeEntryNode>[]).add(node);

  for (final layer in cut.layers) {
    if (layerKindFiltersBelow(layer.kind)) {
      final wrapped = _adjustmentScopeNode(
        adjustment: layer,
        cut: cut,
        frameIndex: frameIndex,
        childrenOf: childrenOf,
      );
      if (wrapped != null) {
        addTo(wrapped.targetFolderId, wrapped.node);
      }
      continue;
    }
    if (layerKindGroupsLayers(layer.kind)) {
      final children = childrenOf.remove(layer.id);
      if (children == null || children.isEmpty) {
        continue;
      }
      if (!layer.isVisible) {
        continue; // A hidden folder drops its whole subtree.
      }
      final opacity = resolveFolderOpacityAt(
        folder: layer,
        frameIndex: frameIndex,
      );
      if (opacity <= 0) {
        continue;
      }
      if (!folderNeedsCompositeBuffer(
        folder: layer,
        frameIndex: frameIndex,
      )) {
        // 통과, fully opaque: the folder is pure structure. Its members
        // belong to the parent exactly as if it were not there — no
        // buffer, no node, no cost.
        for (final child in children) {
          addTo(layer.folderId, child);
        }
        continue;
      }
      addTo(
        layer.folderId,
        CutFrameCompositeEntryGroup(
          folder: layer,
          children: List.unmodifiable(children),
          opacity: opacity,
          // A translucent PASS-THROUGH folder buffers for the opacity
          // alone; the buffer itself blends plainly.
          blendMode: layer.blendMode.isolatesGroup
              ? layer.blendMode
              : LayerBlendMode.normal,
          effects: resolveFolderEffectsAt(
            folder: layer,
            frameIndex: frameIndex,
          ),
        ),
      );
      continue;
    }
    final entry = entryByLayerId[layer.id];
    if (entry != null) {
      addTo(layer.folderId, CutFrameCompositeEntryLeaf(entry));
    }
  }
  return List.unmodifiable(
    childrenOf[null] ?? const <CutFrameCompositeEntryNode>[],
  );
}

/// Plans which surfaces make up the cut's picture at [frameIndex] — the
/// shared [resolveCutFrameCompositeEntries] visit with surfaces resolved
/// (entries whose frame has no artwork drop out).
///
/// FLAT: folder opacity/blend fold into the members. The paint routes use
/// [planCutFrameCompositeTree] instead; this stays for the consumers that
/// cannot nest (a pixel sample, a fill raster).
///
/// ⚠️ Flat-path limitation, the same class as the folder-blend
/// approximation above: a FOLDER's effects are dropped here (they have no
/// buffer to land on), and a LAYER's effects arrive as data the byte-level
/// consumers do not run — the eyedropper and the flood fill read the
/// artwork as DRAWN, not as filtered. Both are Dart byte walks with no
/// Skia in reach; the filtered picture lives on the paint routes.
List<CutFrameCompositeLayer> planCutFrameComposite({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
}) {
  final plan = <CutFrameCompositeLayer>[];
  for (final entry in resolveCutFrameCompositeEntries(
    cut: cut,
    frameIndex: frameIndex,
  )) {
    final surface = surfaceResolver(entry.layer, entry.frame);
    if (surface == null) {
      continue;
    }
    plan.add(
      CutFrameCompositeLayer(
        surface: surface,
        opacity: entry.opacity,
        blendMode: entry.blendMode,
        pose: entry.pose,
        anchorPoint: entry.anchorPoint,
        effects: entry.effects,
      ),
    );
  }
  return plan;
}

/// One node of a PAINTABLE composite tree — [resolveCutFrameCompositeTree]
/// with surfaces resolved.
sealed class CutFrameCompositeSurfaceNode {
  const CutFrameCompositeSurfaceNode();
}

final class CutFrameCompositeSurfaceLeaf extends CutFrameCompositeSurfaceNode {
  const CutFrameCompositeSurfaceLeaf(this.layer);

  final CutFrameCompositeLayer layer;
}

final class CutFrameCompositeSurfaceGroup extends CutFrameCompositeSurfaceNode {
  const CutFrameCompositeSurfaceGroup({
    required this.children,
    required this.opacity,
    required this.blendMode,
    this.effects = const [],
  });

  final List<CutFrameCompositeSurfaceNode> children;
  final double opacity;
  final LayerBlendMode blendMode;

  /// The group's effect chain (R6), applied once to the composed buffer.
  final List<ResolvedLayerEffect> effects;
}

/// An ADJUSTMENT row's scope with surfaces resolved (R6b).
final class CutFrameCompositeSurfaceAdjustment
    extends CutFrameCompositeSurfaceNode {
  const CutFrameCompositeSurfaceAdjustment({
    required this.children,
    required this.effects,
    required this.mix,
  });

  final List<CutFrameCompositeSurfaceNode> children;
  final List<ResolvedLayerEffect> effects;

  /// The effect MIX (the row's opacity), 0…1.
  final double mix;
}

/// [resolveCutFrameCompositeTree] with each leaf's surface resolved;
/// entries whose frame has no artwork drop out, and a group left empty by
/// that drops with them (an empty buffer is a wasted saveLayer).
List<CutFrameCompositeSurfaceNode> planCutFrameCompositeTree({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
}) {
  List<CutFrameCompositeSurfaceNode> mapNodes(
    List<CutFrameCompositeEntryNode> nodes,
  ) {
    final out = <CutFrameCompositeSurfaceNode>[];
    for (final node in nodes) {
      switch (node) {
        case CutFrameCompositeEntryLeaf(:final entry):
          final surface = surfaceResolver(entry.layer, entry.frame);
          if (surface == null) {
            continue;
          }
          out.add(
            CutFrameCompositeSurfaceLeaf(
              CutFrameCompositeLayer(
                surface: surface,
                opacity: entry.opacity,
                blendMode: entry.blendMode,
                pose: entry.pose,
                anchorPoint: entry.anchorPoint,
                effects: entry.effects,
              ),
            ),
          );
        case CutFrameCompositeEntryGroup(
          :final children,
          :final opacity,
          :final blendMode,
          :final effects,
        ):
          final mapped = mapNodes(children);
          if (mapped.isEmpty) {
            continue;
          }
          out.add(
            CutFrameCompositeSurfaceGroup(
              children: List.unmodifiable(mapped),
              opacity: opacity,
              blendMode: blendMode,
              effects: effects,
            ),
          );
        case CutFrameCompositeEntryAdjustment(
          :final children,
          :final effects,
          :final mix,
        ):
          final mapped = mapNodes(children);
          if (mapped.isEmpty) {
            continue; // Every row in scope turned out to have no artwork.
          }
          out.add(
            CutFrameCompositeSurfaceAdjustment(
              children: List.unmodifiable(mapped),
              effects: effects,
              mix: mix,
            ),
          );
      }
    }
    return out;
  }

  return List.unmodifiable(
    mapNodes(
      resolveCutFrameCompositeTree(
        cut: cut,
        frameIndex: frameIndex,
      ),
    ),
  );
}

/// The frame exposed at [frameIndex]: the drawing block covering the index
/// (same semantics as TimelineController.resolveFrameForLayer — uncovered
/// cells and marks in empty space show nothing). Shared by the composite
/// plan and the composite cache signature so both always agree on what a
/// frame shows.
Frame? resolveExposedFrameAt(Layer layer, int frameIndex) {
  final frameId = exposedFrameIdAt(layer.timeline, frameIndex);
  if (frameId == null) {
    return null;
  }

  for (final frame in layer.frames) {
    if (frame.id == frameId) {
      return frame;
    }
  }
  return null;
}
