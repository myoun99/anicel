import '../models/attached_layer_resolve.dart';
import '../models/bitmap_surface.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cel_number_letters.dart';
import '../models/composite_tree.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/fx_plugin_binding.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_folder.dart';
import '../models/layer_id.dart';
import '../models/movie_cel.dart';
import '../models/property_track.dart';
import '../models/timeline_coverage.dart';
import '../models/transform_track.dart';
import 'layer_pose_matrix.dart' show pictureMoved;
import 'layer_pose_paint.dart';
import 'cel_numbered_row.dart';
import 'cel_source_effect_pass.dart';
import 'cel_surface_as_shown.dart';

/// One paintable layer of a composited cut frame, bottom → top order.
class CutFrameCompositeLayer {
  /// 🚨THE CPU HALF OF THE CHAIN IS APPLIED HERE, IN THE CONSTRUCTOR, and
  /// that placement is the point.
  ///
  /// The color keys ([EffectKind.runsOnSourcePixels]) are a pass over the
  /// cel's own bytes, so they have to happen before the surface is handed to
  /// anything that draws. Every route builds its layers through this one
  /// constructor — the shared plan, the tree plan, the cel-group export —
  /// so doing it here means no route can be the one that forgot, and
  /// [surface] and [effects] cannot disagree about whether the keys already
  /// ran ([[make-the-invariant-unrepresentable]]).
  ///
  /// The pass is cached on the source surface's identity and returns it
  /// unchanged when the chain has no keys, so the overwhelmingly common
  /// layer pays a list walk and nothing else.
  ///
  /// ★The cel's TEXTS are laid over its drawing in the same step, before
  /// the keys ([celSurfaceAsShown]) — they are part of the picture a key
  /// filters, and this constructor is where no route forgets them either.
  CutFrameCompositeLayer({
    required BitmapSurface surface,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.placement,
    List<ResolvedLayerEffect> effects = const [],
  }) : surface = celSurfaceAsShown(surface, effects),
       effects = splitSourceEffects(effects).paint;

  CutFrameCompositeLayer._paintedNormal(CutFrameCompositeLayer row)
    : surface = row.surface,
      opacity = row.opacity,
      blendMode = LayerBlendMode.normal,
      placement = row.placement,
      effects = row.effects;

  /// The same row painting normal — what a row in an advanced blend
  /// is, composed over its backdrop ([CompositeBackdropBlend]).
  ///
  /// ⛔Not through the constructor: [surface] and [effects] are the ones its
  /// CPU half already ran on, and running it again would key the keyed.
  CutFrameCompositeLayer paintedNormal() =>
      CutFrameCompositeLayer._paintedNormal(this);

  /// The pixels this layer draws — the cel's own surface, or the derived
  /// one its texts and the color keys produced from it.
  final BitmapSurface surface;

  /// The layer's composite blend against everything below (R26 #30).
  final LayerBlendMode blendMode;

  /// The layer's EFFECTIVE opacity: static layer opacity × animated
  /// Opacity sample × every enclosing folder's effective opacity (folded
  /// per member; overlapping members inside one translucent folder
  /// double-blend — see [resolveFolderChainAt] for why the exact buffered
  /// group is still a later slice).
  final double opacity;

  /// Where the layer lies at this frame — its own pose under every
  /// enclosing folder's (폴더째 이동); null = identity (no transform work —
  /// the overwhelmingly common case skips the canvas save/restore).
  final LayerPlacement? placement;

  /// The layer's EFFECT CHAIN sampled at this frame (R6), applied over the
  /// row's own picture before its opacity/blend meet the stack. Empty for
  /// every layer that carries no effects — the common case, which costs no
  /// filter at all.
  final List<ResolvedLayerEffect> effects;
}

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
/// the animated Opacity sample (1 while unkeyed), clamped to 0..1 — the
/// sample only while its fx is on: the Opacity lane is the TRANSFORM
/// group's, and the switch bypasses it as the composite does (R8).
///
/// ↩️The switch was read beside this by the caller that knew of it, and
/// the SE name tag did not (F-387: 「같은 fx인데 다른건 말이안됨」).
double resolveLayerEffectiveOpacityAt({
  required Layer layer,
  required int frameIndex,
}) => _ownStrengthAt(layer, layer, frameIndex).clamp(0.0, 1.0).toDouble();

/// [layer]'s OWN strength at [frameIndex], before any folder's: its static
/// opacity × its fx [carrier]'s animated Opacity sample — the sample only
/// while the carrier's fx is on (R8). Unclamped: the composite folds the
/// folders' strength in before it clamps ([_resolveLayerNode]).
double _ownStrengthAt(Layer layer, Layer carrier, int frameIndex) =>
    carrier.transformEnabled
    ? layer.opacity *
          resolveOpacityTrackAt(carrier.transformTrack.opacity, frameIndex)
    : layer.opacity;

/// Resolves the drawable surface for a layer's frame (e.g. by replaying the
/// brush store's paint commands); `null` when the frame has no artwork.
typedef LayerFrameSurfaceResolver =
    BitmapSurface? Function(Layer layer, Frame frame);

/// How a route reads each row's cel: its surface ([surfaces]), and
/// what runs the plugins the row's chain runs ([plugins]) — null for a
/// route that runs none.
typedef CelReading = ({
  LayerFrameSurfaceResolver surfaces,
  FxPluginBinding? plugins,
});

/// One ROW that paints in a cut frame's composite tree, bottom → top: an
/// entry resolved from stored pixels, or the row being DRAWN ON with none
/// exposed here.
///
/// Built by [resolveCutFrameCompositeTree] and mapped — never rebuilt —
/// into the shapes the routes need: surfaces for the paint routes
/// ([planCutFrameCompositeTree]) and identities for the playback cache
/// ([computeCutFrameCompositeSignature]). One structure, so playback,
/// export and the editing canvas cannot drift.
sealed class CutFrameCompositeRow {
  const CutFrameCompositeRow();

  /// The blend the row composites with against everything below it.
  LayerBlendMode get blendMode;

  /// The row's strength, folded.
  double get opacity;

  /// The row's effect chain sampled at this frame.
  List<ResolvedLayerEffect> get effects;

  /// The same row painting with [paint] — the row's picture under part of
  /// its chain, where a cel number splits it ([celNumberedRow]).
  CutFrameCompositeRow withPaint(RowPaint paint);

  /// The same row painting normal — what a row in an advanced blend
  /// is, composed over its backdrop ([CompositeBackdropBlend]).
  CutFrameCompositeRow paintedNormal();

  /// The same row painting normal at full strength — what the base of a
  /// clipping group is ([CompositeClip]), whose strength and blend are the
  /// group's.
  CutFrameCompositeRow paintedAsClipBase();
}

/// One resolved contributor to the cut's picture at a frame — the SHARED
/// visit both the composite plan and the composite cache signature consume,
/// so every route (playback, export, thumbnails, editing stack) agrees on
/// skip rules, exposure resolution AND the attach-layer expansion by
/// construction.
class CutFrameCompositeEntry extends CutFrameCompositeRow {
  const CutFrameCompositeEntry({
    required this.layer,
    required this.frame,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.placement,
    this.effects = const [],
  });

  final Layer layer;
  final Frame frame;
  @override
  final double opacity;

  /// The layer's composite blend against everything below (R26 #30).
  @override
  final LayerBlendMode blendMode;

  /// Where the layer lies at this frame — its own pose under every
  /// enclosing folder's (L3); null = identity.
  final LayerPlacement? placement;

  /// The row's effect chain sampled at this frame (R6) — from the FX
  /// CARRIER, so an attach row wears its base's effects exactly as it wears
  /// its base's pose, and the carrier's fx switch bypasses both.
  @override
  final List<ResolvedLayerEffect> effects;

  @override
  CutFrameCompositeEntry withPaint(RowPaint paint) => CutFrameCompositeEntry(
    layer: layer,
    frame: frame,
    opacity: paint.opacity,
    blendMode: paint.blendMode,
    placement: placement,
    effects: paint.effects,
  );

  @override
  CutFrameCompositeEntry paintedNormal() => CutFrameCompositeEntry(
    layer: layer,
    frame: frame,
    opacity: opacity,
    placement: placement,
    effects: effects,
  );

  @override
  CutFrameCompositeEntry paintedAsClipBase() => CutFrameCompositeEntry(
    layer: layer,
    frame: frame,
    opacity: 1,
    placement: placement,
    effects: effects,
  );
}

/// What the plan resolved about HOW a row draws, apart from its pixels —
/// the folded opacity, the blend it composites with, the pose the folder
/// chain composed outside it, and the effect chain from its fx carrier.
typedef ResolvedRowRender = ({
  double opacity,
  LayerBlendMode blendMode,

  /// Where the row lies: its own pose under the folder chain's; null =
  /// identity.
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
});

/// The row being DRAWN ON, standing in the tree at its own place with no
/// stored frame behind it — its pixels come from the live surface the
/// editing canvas owns.
///
/// ⛔THE PLAN PLACES IT; THE CANVAS ONLY FILLS IT. A row with nothing
/// exposed at this frame resolves no entry, and the editing stack used to
/// append its node at the TOP LEVEL by hand — losing the folder chain, the
/// group buffer and its z-position. So a stroke inside a 20% folder drew
/// at full strength on the canvas and at 20% in playback, and a stroke
/// inside a folder the user had switched off went on being drawn on the
/// canvas and nowhere else (유저 확정 2026-09-04, ARCH-active-node: 재생과
/// 똑같이).
///
/// ⚠️ONLY THE EDITING STACK ASKS FOR ONE. Playback, export and the cache
/// signature pass no live row, so they never see this node — but they
/// switch over it, because a route that started drawing live pixels would
/// otherwise do it silently.
final class CutFrameCompositeLiveRow extends CutFrameCompositeRow {
  const CutFrameCompositeLiveRow({required this.layer, required this.render});

  final Layer layer;

  /// Resolved exactly as an entry's is — same gates, same folds.
  final ResolvedRowRender render;

  @override
  LayerBlendMode get blendMode => render.blendMode;

  @override
  double get opacity => render.opacity;

  @override
  List<ResolvedLayerEffect> get effects => render.effects;

  @override
  CutFrameCompositeLiveRow withPaint(RowPaint paint) =>
      CutFrameCompositeLiveRow(
        layer: layer,
        render: (
          opacity: paint.opacity,
          blendMode: paint.blendMode,
          placement: render.placement,
          effects: paint.effects,
        ),
      );

  @override
  CutFrameCompositeLiveRow paintedNormal() => CutFrameCompositeLiveRow(
    layer: layer,
    render: (
      opacity: render.opacity,
      blendMode: LayerBlendMode.normal,
      placement: render.placement,
      effects: render.effects,
    ),
  );

  @override
  CutFrameCompositeLiveRow paintedAsClipBase() => CutFrameCompositeLiveRow(
    layer: layer,
    render: (
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      placement: render.placement,
      effects: render.effects,
    ),
  );
}

/// An onion GHOST of [layer]: its cel [frameId] of another frame, at a
/// peg's [opacity] and [tint] (`planOnionSkin`).
///
/// 🚨THE PLAN PLACES IT, as it places the live row: directly under the
/// row's own drawing, in its folder and cut by its clip, whether or not the
/// row shows a cel here (onion-ghosts-in-place-Q1 = a, 유저 2026-10-26 —
/// [resolveCutFrameCompositeTree]'s `ghostsOf`). ↩️The canvas slid the
/// ghosts in under the row a pen was on by hand (`stackNodesWithGhosts`,
/// retired 2026-10-25), so it had no place for a row that showed no cel.
///
/// ⚠️ONLY THE EDITING CANVAS ASKS FOR ONE. Playback, export and the cache
/// signature pass no ghosts, but they switch over it, as over a live row.
final class CutFrameCompositeGhost extends CutFrameCompositeRow {
  const CutFrameCompositeGhost({
    required this.layer,
    required this.frameId,
    required this.frameIndex,
    required this.opacity,
    this.tint,
    this.blendMode = LayerBlendMode.normal,
    this.effects = const [],
  });

  /// The onion row the ghost is of.
  final Layer layer;

  /// The cel it shows, of the frame its peg reaches.
  final FrameId frameId;

  /// The frame its peg reaches — where its chain is sampled, and the rows
  /// that chain reads are read ([readingTheirRows]).
  final int frameIndex;

  @override
  final double opacity;

  /// The side's tint (onion-skin Colors mode); null shows the artwork's own
  /// colours.
  final int? tint;

  @override
  final LayerBlendMode blendMode;

  /// The chain the row's pixels wear, sampled at the ghost's own frame.
  @override
  final List<ResolvedLayerEffect> effects;

  @override
  CutFrameCompositeGhost withPaint(RowPaint paint) => CutFrameCompositeGhost(
    layer: layer,
    frameId: frameId,
    frameIndex: frameIndex,
    opacity: paint.opacity,
    tint: tint,
    blendMode: paint.blendMode,
    effects: paint.effects,
  );

  @override
  CutFrameCompositeGhost paintedNormal() => CutFrameCompositeGhost(
    layer: layer,
    frameId: frameId,
    frameIndex: frameIndex,
    opacity: opacity,
    tint: tint,
    effects: effects,
  );

  @override
  CutFrameCompositeGhost paintedAsClipBase() => CutFrameCompositeGhost(
    layer: layer,
    frameId: frameId,
    frameIndex: frameIndex,
    opacity: 1,
    tint: tint,
    effects: effects,
  );
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
///
/// And a CLIP (I-92-Q3 a, 유저 2026-10-24 「클튜처럼 — 폴더도 켜고, 폴더도
/// 바탕이 된다」): a folder that clips to the layer below, or that one
/// clips to, is cut or cuts as ONE picture — its members as one — even a
/// pass-through one. Asked of the rows as they stand, never of what shows
/// at the frame: hiding a row clipped to the folder must not change how
/// the folder's members blend.
bool folderNeedsCompositeBuffer({
  required Cut cut,
  required Layer folder,
  required int frameIndex,
}) {
  if (folder.blendMode.isolatesGroup || meetsAClip(cut, folder)) {
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

/// Whether [layer] CLIPS TO THE LAYER BELOW (I-92): its own switch
/// ([Layer.clipsToBelow]), on a row that can clip ([LayerKind.takesClipping]).
bool clipsToLayerBelow(Layer layer) =>
    layer.clipsToBelow && layer.kind.takesClipping;

/// What [row] clips to when it clips to the layer below — the BASE: the
/// first row under it in its own folder that does not clip itself
/// (I-92-Q2 a, 유저 2026-10-24 「프로툴과 같게 — 모두 그 아래 첫 바탕에
/// 잘린다」). Null at the bottom of its folder: there is nothing to clip to.
///
/// A row that takes no part in the picture — the camera, a transition
/// ([LayerKind.composites]) — is passed over: the composite never sees it.
Layer? clipBaseOf(Cut cut, Layer row) {
  final layers = cut.layers;
  for (var i = _rowIndexOf(cut, row) - 1; i >= 0; i -= 1) {
    final below = layers[i];
    // A folder's members are one run under it, so a row of this folder
    // lies under [row] only inside that run — anything else is a member of
    // a sibling folder.
    if (below.folderId == row.folderId &&
        below.kind.composites &&
        !clipsToLayerBelow(below)) {
      return below;
    }
  }
  return null;
}

/// Whether [row] is cut or cuts by the clip law (I-92) — it clips to the
/// layer below, or one clips to it — and so meets the clip as ONE picture:
/// a folder its members as one ([folderNeedsCompositeBuffer]), a row with
/// its cel number's letters ([celNumberedRow]). Asked of the rows as they
/// stand, not of what shows at a frame.
bool meetsAClip(Cut cut, Layer row) =>
    clipsToLayerBelow(row) || _isClipBase(cut, row);

/// Whether a row clips to [row] ([clipBaseOf]): the nearest row of its
/// folder above it, of those in the picture, clips to the layer below.
bool _isClipBase(Cut cut, Layer row) {
  if (clipsToLayerBelow(row)) {
    return false; // It clips itself: the run's base is under it.
  }
  final layers = cut.layers;
  for (var i = _rowIndexOf(cut, row) + 1; i < layers.length; i += 1) {
    final above = layers[i];
    if (above.id == row.folderId) {
      return false; // The folder's own row: nothing of it lies above.
    }
    if (above.folderId == row.folderId && above.kind.composites) {
      return clipsToLayerBelow(above);
    }
  }
  return false;
}

/// The outermost folder around [row] that a row clips to ([_isClipBase]),
/// or null where none is.
Layer? _clipBaseAround(Cut cut, Layer row) {
  Layer? outermost;
  for (final folder in cut.layers.ancestryOf(row.folderId)) {
    if (_isClipBase(cut, folder)) {
      outermost = folder;
    }
  }
  return outermost;
}

/// [row]'s place in [cut]'s stack — by id, as a row's identity is.
int _rowIndexOf(Cut cut, Layer row) =>
    cut.layers.indexWhere((layer) => layer.id == row.id);

/// Where the clip law lays a row ([clipTargetOf]).
enum ClipPlaced {
  /// By itself: it clips to nothing, or to a row that does not cut it.
  alone,

  /// Into the clipping group of the row it clips to.
  clipped,

  /// Nowhere: it clips to what paints nothing.
  nowhere,
}

/// How [row] meets [cut]'s picture by the clip law (I-92), before what a
/// frame draws is asked: [ClipPlaced.clipped] to [base] ([clipBaseOf] —
/// null for the other two), by itself, or nowhere.
({ClipPlaced placed, Layer? base}) clipTargetOf(Cut cut, Layer row) {
  if (!clipsToLayerBelow(row)) {
    return (placed: ClipPlaced.alone, base: null);
  }
  final base = clipBaseOf(cut, row);
  if (base == null) {
    // Nothing under it to clip to.
    return (placed: ClipPlaced.nowhere, base: null);
  }
  if (base.kind.filtersBelow) {
    // 🗣️I-92-Q4 a: an adjustment row has no picture of its own to cut by
    // — what clips to it is not cut, until the row is hidden.
    return (
      placed: base.isVisible ? ClipPlaced.alone : ClipPlaced.nowhere,
      base: null,
    );
  }
  return (placed: ClipPlaced.clipped, base: base);
}

/// THE CLIP LAW's placing half (I-92): rows met bottom-up, each laid by
/// itself into the list it stands in, or joined to the node of the row it
/// clips to ([clipTargetOf], [clippedOnto]), or nowhere. The cut's tree
/// and a cel's stack place through this one.
final class ClipPlacing<P> {
  ClipPlacing({required this.blendOf, required this.asClipBase});

  /// The blend a route's own row composites with ([clippedOnto]).
  final LayerBlendMode Function(P payload) blendOf;

  /// The same row as a clipping group's base ([clippedOnto]).
  final ({P base, double opacity, LayerBlendMode blendMode}) Function(
    P payload,
  )
  asClipBase;

  // Where each row's node stands — the list and the place in it — for the
  // rows that clip to it to join; by its cut too, as a cel lays rows of
  // more cuts than one.
  final _placeOf =
      <(CutId, LayerId), ({List<CompositeNode<P>> bucket, int at})>{};

  /// Lays [node], [row]'s picture in [cut], into [into] — the list its
  /// folder's members gather in — or onto the node of the row it clips
  /// to, or nowhere.
  void place(
    Cut cut,
    Layer row,
    CompositeNode<P> node, {
    required List<CompositeNode<P>> into,
  }) {
    final (:placed, :base) = clipTargetOf(cut, row);
    if (base == null) {
      if (placed == ClipPlaced.alone) {
        _placeOf[(cut.id, row.id)] = (bucket: into, at: into.length);
        into.add(node);
      }
      return;
    }
    final standing = _placeOf[(cut.id, base.id)];
    if (standing == null) {
      return; // The base paints nothing here, so neither does this.
    }
    // ⚠️A base's list is never taken by an adjustment before what clips to
    // it joins: anything between the two clips too, and a folder among
    // them buffers ([folderNeedsCompositeBuffer]) — so no adjustment's
    // scope reaches out past it.
    assert(
      identical(into, standing.bucket),
      'the list ${base.id} stands in was taken before ${row.id} joined it',
    );
    standing.bucket[standing.at] = clippedOnto(
      standing.bucket[standing.at],
      node,
      blendOf: blendOf,
      asClipBase: asClipBase,
    );
  }
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
  /// they belong to its [CompositeGroup] instead. Poses fold
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
          cut: cut,
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
    if (_folderPoseAt(folder, frameIndex, cut.canvasSize) case final pose?) {
      poses.add(pose);
    }
  }
  return (
    visible: true,
    opacityFactor: opacityFactor,
    blendMode: chainBlend,
    poses: List.unmodifiable(poses),
  );
}

/// A folder's own contribution to where its members land: its pose while
/// its fx is on and its track carries geometry, else null.
LayerPoseSample? _folderPoseAt(
  Layer folder,
  int frameIndex,
  CanvasSize canvasSize,
) {
  final track = folder.transformTrack;
  final hasGeometry =
      track.anchorPoint.isNotEmpty ||
      track.position.isNotEmpty ||
      track.scale.isNotEmpty ||
      track.rotation.isNotEmpty;
  if (!folder.transformEnabled || !hasGeometry) {
    return null;
  }
  return (
    pose: track.resolveAt(
      frameIndex: frameIndex,
      orElse: () => layerIdentityPose(canvasSize),
    ),
    anchorPoint: resolveAnchorTrackAt(track.anchorPoint, frameIndex),
  );
}

/// [carrier]'s own placement in [space] — the space its pose is keyed in:
/// its pose and anchor while its fx is on, null when the switch bypasses
/// them or the track carries no geometry.
///
/// ONE gate for every picture a row's transform lays: a layer's artwork on
/// the canvas, and an SE row's name tag in the shot (F-387: 「같은 fx인데
/// 다른건 말이안됨」). ↩️The tag read the transform track itself, so its
/// row's fx switch turned off nothing it drew.
LayerPoseSample? layerOwnPlacementAt({
  required Layer carrier,
  required CanvasSize space,
  required int frameIndex,
}) {
  final pose = carrier.transformEnabled
      ? resolveLayerPoseAt(
          layer: carrier,
          canvasSize: space,
          frameIndex: frameIndex,
        )
      : null;
  return pose == null
      ? null
      : (
          pose: pose,
          anchorPoint: resolveLayerAnchorPointAt(
            layer: carrier,
            frameIndex: frameIndex,
          ),
        );
}

/// Where [layer]'s pixels land on the canvas at [frameIndex] — THE placement
/// the composite paints it with: its FX carrier's own pose (the base's, for
/// an attach row) under every folder pose above it. Null = identity.
///
/// 🚨ONE answer for every trip between the canvas and a row's artwork: the
/// pen's draw-through, the fill's seed, the held pick, the pixel verbs'
/// marquee. The draw-through used to read the row's OWN pose, so inside a
/// posed folder a stroke landed where the folder then moved it — away from
/// the pen (measured 2026-09-25: a folder keyed to 2× gave the draw-through
/// identity while the stack painted the row at 2×). The pixel verbs read
/// the raw track value, which also ignored the anchor and the fx switch.
///
/// A hidden folder still places its members: what is drawn inside it lands
/// where it will show when the folder is shown again.
LayerPlacement? layerPlacementAt({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
}) => placementUnderFolders(
  folderPoses: _folderPosesAbove(cut, layer, frameIndex),
  layerSample: layerOwnPlacementAt(
    carrier: _fxCarrierOf(cut, layer),
    space: cut.canvasSize,
    frameIndex: frameIndex,
  ),
  canvasSize: cut.canvasSize,
  within: referenceMoveAt(layer, frameIndex),
);

/// Where [layer]'s REFERENCE FX stands its file's picture from — the row's
/// own pose under every folder above it, short of the move the fx makes at
/// [frameIndex] ([referenceMoveAt]): what the reference's box frames the
/// fx's values in. Null = the canvas itself.
LayerPlacement? layerReferenceSpaceAt({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
}) => placementUnderFolders(
  folderPoses: _folderPosesAbove(cut, layer, frameIndex),
  layerSample: layerOwnPlacementAt(
    carrier: _fxCarrierOf(cut, layer),
    space: cut.canvasSize,
    frameIndex: frameIndex,
  ),
  canvasSize: cut.canvasSize,
);

/// The row whose transform places [layer] ([fxCarrierOf]) — the row itself
/// where its base is gone.
Layer _fxCarrierOf(Cut cut, Layer layer) =>
    fxCarrierOf(layer, cut.layers) ?? layer;

/// The move [layer]'s REFERENCE FX makes at [frameIndex]: the file's
/// picture from where its pixels are laid ([MediaReference.laid]) to where
/// the fx stands it then ([MediaReference.poseAt]), in the row's own space
/// — under its transform, which still moves it. Null while the two agree:
/// every row that shows no file, and a reference laid where it stands.
///
/// 🗣️F-374 (유저 2026-10-17): 「참조fx도 똑같이 fx로서 법 통일. 지금 움직여도
/// 키 안생긴다거나」 — the fx keys, and a picture laid once stands at each
/// frame where its keys say. No switch of the row reaches it, as none
/// reaches where the file was laid (I-68-Q1: 「레이어의 fx버튼 꺼도 그 자리
/// 유지되고 출력시에도 fx 적용 해제되있어도 유지됨」) — an output's 끔 does,
/// handing the plan a reference that stands where it is laid (I-65-Q6
/// 「참조 fx 도 끈다(정말 날 것)」, `layerAsOutput`). ↩️None reached it.
LayerPlacement? referenceMoveAt(Layer layer, int frameIndex) {
  final reference = layer.mediaReference;
  if (reference == null) {
    return null;
  }
  final to = reference.poseAt(frameIndex);
  return to == reference.laid
      ? null
      : pictureMoved(
          from: reference.laid,
          to: to,
          picture: reference.pictureSize,
        );
}

/// Where [layer]'s OWN pose lives on the canvas at [frameIndex] — its
/// PARENT's placement: every folder pose above it and nothing of its own.
/// Null = the canvas itself (no posed folder above the row).
///
/// 🚨The gizmos edit the row's own pose, which is stated in THIS space: its
/// position crosshair, its anchor and its box stand where this placement
/// shows the value, and a drag comes back through it. Drawn as if the
/// canvas were the row's parent, the crosshair of a row in a folder moved
/// right by 200 stood 200 to the left of the picture it moves, and under a
/// 2× folder a drag moved the picture twice as far as the pointer
/// (measured 2026-09-25).
LayerPlacement? layerParentPlacementAt({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
}) => placementUnderFolders(
  folderPoses: _folderPosesAbove(cut, layer, frameIndex),
  layerSample: null,
  canvasSize: cut.canvasSize,
);

/// The posed folders above [layer] at [frameIndex], outermost first — the
/// part of [layerPlacementAt] that is the row's parent.
List<LayerPoseSample> _folderPosesAbove(
  Cut cut,
  Layer layer,
  int frameIndex,
) => [
  for (final folder in cut.layers.ancestryOf(layer.folderId).reversed)
    ?_folderPoseAt(folder, frameIndex, cut.canvasSize),
];

/// [layerSample] under the folder chain's poses — ONE placement per entry,
/// so every consumer (composite cache, camera renders, editing stack,
/// signatures) applies folder FX with zero changes. Null when neither the
/// folders nor the layer carry geometry.
///
/// The fold is the PRODUCT, and nothing else: a placement is an affine and
/// affines are closed under it ([LayerPlacement] says what that replaced).
///
/// [within] is a move inside the row's own space, before its pose: where
/// its reference fx stands the file at this frame ([referenceMoveAt]).
LayerPlacement? placementUnderFolders({
  required List<LayerPoseSample> folderPoses,
  required LayerPoseSample? layerSample,
  required CanvasSize canvasSize,
  LayerPlacement? within,
}) {
  final own = layerSample == null ? null : placementOf(layerSample, canvasSize);
  var combined = own == null || within == null
      ? own ?? within
      : own.compose(within);
  // Fold innermost-outward: outer ∘ (… ∘ (inner ∘ layer)).
  for (final folderPose in folderPoses.reversed) {
    final outer = placementOf(folderPose, canvasSize);
    combined = combined == null ? outer : outer.compose(combined);
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
/// governs both; a row riding the conte wears its own, [fxCarrierOf]),
/// while the eye, static opacity and cels stay the attach layer's own.
/// VISIBILITY is fully independent (UI-R24 #5): hiding the
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
///
/// ⚠️A row's entry is its own pixels: what a row that clips to the layer
/// below shows of them is [flatClipOf]'s, asked by a read of the whole
/// picture — a read of one row reads that row as drawn.
List<CutFrameCompositeEntry> resolveCutFrameCompositeEntries({
  required Cut cut,
  required int frameIndex,
  bool foldBufferedFolders = true,
}) => [
  for (final layer in cut.layers)
    if (_resolveLayerNode(cut, layer, (
          frameIndex: frameIndex,
          foldBufferedFolders: foldBufferedFolders,
          liveLayerId: null,
        ))
        case final CutFrameCompositeEntry entry)
      entry,
];

/// How a FLAT read ([resolveCutFrameCompositeEntries] — the eyedropper,
/// the fill) cuts [layer]'s pixels when it clips to the layer below
/// (I-92): null when nothing cuts it. Otherwise [cutBy] — its base's
/// entries among [entries], whose pixels laid together are where it shows
/// (none: nowhere) — and [strength], the base's own, which a clipping
/// group takes on (Photoshop).
///
/// The tree's law ([clipTargetOf], [CompositeClip]) read by pixels: the
/// base's pixels' alpha cuts, its strength and blend go to the group. A
/// folder's base is every entry inside it — the folder's picture, flat.
({List<CutFrameCompositeEntry> cutBy, double strength})? flatClipOf({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
  required List<CutFrameCompositeEntry> entries,
}) {
  final (:placed, :base) = clipTargetOf(cut, layer);
  if (base == null) {
    return placed == ClipPlaced.alone ? null : (cutBy: const [], strength: 0);
  }
  if (base.kind.groupsLayers) {
    return (
      cutBy: [
        for (final entry in entries)
          if (cut.layers
              .ancestryOf(entry.layer.folderId)
              .any((folder) => folder.id == base.id))
            entry,
      ],
      strength: resolveFolderOpacityAt(folder: base, frameIndex: frameIndex),
    );
  }
  return (
    cutBy: [
      for (final entry in entries)
        if (entry.layer.id == base.id) entry,
    ],
    strength:
        layerDrawingAt(
          cut: cut,
          layer: base,
          frameIndex: frameIndex,
        )?.render.opacity ??
        0,
  );
}

/// The cel [layerId] exposes at [frameIndex] in [cut] — the one this plan
/// composites for that row, asked before any gate (eye, opacity, folder), so
/// it names what the row SHOWS there rather than whether it is drawn. Null
/// when the row exposes nothing there or is not in [cut].
///
/// The editing canvas asks it of the row being drawn on, twice: of the cut
/// as committed — the cel the brush holds — and of the cut as a drag shows
/// it (`EditingStackMap`).
FrameId? exposedCelIdAt({
  required Cut cut,
  required LayerId layerId,
  required int frameIndex,
}) {
  final layer = cut.layers.byId(layerId);
  if (layer == null) {
    return null;
  }
  final base = isAttachedLayer(layer)
      ? attachedBaseOf(layer, cut.layers)
      : null;
  return _celOf(layer, base, frameIndex)?.id;
}

/// [layer]'s cel at [frameIndex]: a SYNCED attach row's through its [base]'s
/// exposure and the cell links; a FREE attach row (UI-R21 #3) exposes its OWN
/// timeline like a normal layer — the base still carries eye cascade and FX
/// above.
Frame? _celOf(Layer layer, Layer? base, int frameIndex) =>
    base == null || !isSyncedAttachedLayer(layer)
    ? resolveExposedFrameAt(layer, frameIndex)
    : resolveAttachedFrameAt(
        attached: layer,
        base: base,
        frameIndex: frameIndex,
      );

/// [layer] as a row that paints a picture of its own: the row whose fx it
/// wears ([fxCarrierOf]), and the base an attach row's cels ride. Null for
/// a row that paints nothing of its own: a folder composites its MEMBERS,
/// whose picture its eye, opacity, blend and FX reach through
/// [resolveFolderChainAt] (flat) or a [CompositeGroup] (tree); an
/// adjustment filters what is under it. And null for an attach row whose
/// base is gone — a dangling link contributes nothing.
({Layer carrier, Layer? base})? _paintingRowOf(Cut cut, Layer layer) {
  if (!layer.kind.paintsArtwork) {
    return null;
  }
  final carrier = fxCarrierOf(layer, cut.layers);
  if (carrier == null) {
    return null;
  }
  return (carrier: carrier, base: attachedBaseOf(layer, cut.layers));
}

/// The effect chain [layer] wears in [cut]: its own — or, for an attach
/// row, its base's short of the links only their own row wears
/// ([EffectKind.staysOnItsRow]: the cel number). Empty for a row that paints
/// nothing of its own ([_paintingRowOf]).
///
/// ⛔ONE answer for every route that lays a row's picture — the composite,
/// a file that keeps the rows apart, the delivery cel (I-65-Q4).
List<LayerEffect> chainWornBy(Cut cut, Layer layer) {
  final painting = _paintingRowOf(cut, layer);
  return painting == null ? const [] : _wornChain(layer, painting.carrier);
}

List<LayerEffect> _wornChain(Layer layer, Layer carrier) =>
    carrier.id == layer.id
    ? carrier.effects
    : [
        for (final effect in carrier.effects)
          if (!effect.kind.staysOnItsRow) effect,
      ];

/// What [layer] draws at [frameIndex] in [cut], shown or not: the cel it
/// exposes there — none where it exposes none — and how: its OWN strength,
/// its own blend, where it lies under every folder above it, and the chain
/// of the row whose fx it wears. Null for a row that paints nothing of its
/// own ([_paintingRowOf]).
///
/// The composite's answer for a row short of its gates — the eye, the
/// static opacity, a hidden folder — and of what it folds in from the
/// folders above, their strength and blend ([_resolveLayerNode]): what a
/// file that keeps every row apart lays each row by, a hidden one hidden
/// and each folder's strength and blend on the folder (I-117-Q2, 유저
/// 2026-10-22: 「층을 지키고 그 효과는 뺀다」).
({Frame? frame, ResolvedRowRender render})? layerDrawingAt({
  required Cut cut,
  required Layer layer,
  required int frameIndex,
}) {
  final painting = _paintingRowOf(cut, layer);
  if (painting == null) {
    return null;
  }
  return (
    frame: _celOf(layer, painting.base, frameIndex),
    render: (
      opacity: _ownStrengthAt(
        layer,
        painting.carrier,
        frameIndex,
      ).clamp(0.0, 1.0).toDouble(),
      blendMode: layer.blendMode,
      placement: layerPlacementAt(
        cut: cut,
        layer: layer,
        frameIndex: frameIndex,
      ),
      effects: resolveLayerEffectsAt(
        effects: _wornChain(layer, painting.carrier),
        frameIndex: frameIndex,
      ),
    ),
  );
}

/// What one layer contributes at a frame: its resolved
/// [CutFrameCompositeEntry], a [CutFrameCompositeLiveRow] when it is the
/// LIVE row and has no cel exposed here, or null when it contributes
/// nothing.
///
/// ⛔EVERY GATE IS IN THIS ONE FUNCTION — the eye, the static opacity, the
/// folder chain's visibility and its opacity factor, the dangling attach
/// link. The editing stack used to place the live row by hand instead, and
/// so it skipped every one of them: a stroke inside a folder the user had
/// switched off went on being drawn on the canvas and nowhere else, and a
/// stroke inside a 20% folder drew at full strength while playback showed
/// it at 20%.
CutFrameCompositeRow? _resolveLayerNode(
  Cut cut,
  Layer layer,
  ({int frameIndex, bool foldBufferedFolders, LayerId? liveLayerId}) at,
) {
  final frameIndex = at.frameIndex;
  final painting = _paintingRowOf(cut, layer);
  if (painting == null) {
    return null;
  }
  // Each row's OWN eye and static opacity gate it — the base's eye
  // never cascades (UI-R24 #5: hiding the base hides only the base's
  // own picture; its attach rows stay independent).
  if (!layer.isVisible || layer.opacity <= 0) {
    return null;
  }
  // Folder gates: a hidden ancestor hides the subtree; folder opacity
  // folds into the member's, folder poses ride the entry.
  final folderChain = resolveFolderChainAt(
    cut: cut,
    layer: layer,
    frameIndex: frameIndex,
    foldBufferedFolders: at.foldBufferedFolders,
  );
  if (!folderChain.visible) {
    return null;
  }
  final fxCarrier = painting.carrier;
  final opacity =
      (_ownStrengthAt(layer, fxCarrier, frameIndex) *
              folderChain.opacityFactor)
          .clamp(0.0, 1.0)
          .toDouble();
  if (opacity <= 0) {
    return null;
  }

  final frame = _celOf(layer, painting.base, frameIndex);

  // R6: effects ride the FX carrier exactly like the pose and the
  // animated opacity — an attach row wears its base's chain, short of its
  // cel number ([chainWornBy]), and the carrier's fx switch bypasses it.
  // R8: NOT gated on fxEnabled — that switch is the TRANSFORM group's.
  // Each effect carries its own ([LayerEffect.enabled]) and the master
  // writes them all, so gating here too would make the row switch reach
  // effects it had not turned off.
  final effects = resolveLayerEffectsAt(
    effects: _wornChain(layer, fxCarrier),
    frameIndex: frameIndex,
  );
  // The placement is [layerPlacementAt]'s: the same own part, under the
  // folder poses this walk already gathered with the chain's gates.
  final combined = placementUnderFolders(
    folderPoses: folderChain.poses,
    layerSample: layerOwnPlacementAt(
      carrier: fxCarrier,
      space: cut.canvasSize,
      frameIndex: frameIndex,
    ),
    canvasSize: cut.canvasSize,
    within: referenceMoveAt(layer, frameIndex),
  );
  // The blend is the ROW's own (attach rows keep theirs — their pixels
  // are independent even when timing rides the base); a member that sets
  // none inherits its folder's (R27 #29).
  final blendMode = layer.blendMode == LayerBlendMode.normal
      ? folderChain.blendMode
      : layer.blendMode;

  if (frame == null) {
    if (layer.id != at.liveLayerId) {
      return null;
    }
    return CutFrameCompositeLiveRow(
      layer: layer,
      render: (
        opacity: opacity,
        blendMode: blendMode,
        placement: combined,
        effects: effects,
      ),
    );
  }
  return CutFrameCompositeEntry(
    layer: layer,
    frame: frame,
    opacity: opacity,
    blendMode: blendMode,
    placement: combined,
    effects: effects,
  );
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
({CompositeNode<CutFrameCompositeRow> node, LayerId? targetFolderId})?
_adjustmentScopeNode({
  required Layer adjustment,
  required Cut cut,
  required int frameIndex,
  required Map<LayerId?, List<CompositeNode<CutFrameCompositeRow>>> childrenOf,
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
      cut: cut,
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
  final children = <CompositeNode<CutFrameCompositeRow>>[
    for (final key in scopeKeys.reversed) ...?childrenOf.remove(key),
  ];
  if (children.isEmpty) {
    return null; // Nothing below to filter.
  }
  return (
    node: CompositeAdjustment<CutFrameCompositeRow>(
      children: List.unmodifiable(children),
      effects: effects,
      mix: mix,
    ),
    targetFolderId: scopeKeys.last,
  );
}

/// The cut's picture at [frameIndex] as a TREE, bottom → top: every
/// visible entry, with each BUFFERING folder's members wrapped in a
/// [CompositeGroup] so the folder's opacity and blend apply
/// ONCE to their composed buffer (R27 #29), each ADJUSTMENT row's
/// scope wrapped in a [CompositeAdjustment] (R6b), each row that clips to
/// the layer below gathered with what it clips to into a [CompositeClip]
/// (I-92), and each row in an advanced blend composed over its scope
/// ([CompositeBackdropBlend], brush-fidelity-Q4).
///
/// The stack list IS the structure: a folder's members occupy a
/// contiguous run with the folder row directly above it, so this single
/// bottom-to-top pass has already collected every child by the time it
/// reaches the folder. A plain pass-through folder leaves no node — its
/// members simply belong to the parent, which is what makes an organizing
/// folder cost exactly nothing.
List<CompositeNode<CutFrameCompositeRow>> resolveCutFrameCompositeTree({
  required Cut cut,
  required int frameIndex,
  /// The row being DRAWN ON, when there is one. It stands in the tree even
  /// with no cel exposed at [frameIndex], as a [CutFrameCompositeLiveRow]
  /// — see that class for why the plan and not the canvas places it. Null
  /// for every route that composites stored pixels only.
  LayerId? liveLayerId,

  /// Each row's onion ghosts where a canvas lays them IN PLACE
  /// ([CutFrameCompositeGhost]), bottom → top. Null for every route that
  /// composites the film.
  List<CutFrameCompositeGhost> Function(Layer row)? ghostsOf,
}) {
  // folder id (null = top level) → the nodes gathered under it so far.
  final childrenOf = <LayerId?, List<CompositeNode<CutFrameCompositeRow>>>{};
  void addTo(LayerId? folderId, CompositeNode<CutFrameCompositeRow> node) =>
      (childrenOf[folderId] ??= <CompositeNode<CutFrameCompositeRow>>[])
          .add(node);
  final clips = ClipPlacing<CutFrameCompositeRow>(
    blendOf: (row) => row.blendMode,
    asClipBase: (row) => (
      base: row.paintedAsClipBase(),
      opacity: row.opacity,
      blendMode: row.blendMode,
    ),
  );
  void place(Layer row, CompositeNode<CutFrameCompositeRow> node) =>
      clips.place(cut, row, node, into: childrenOf[row.folderId] ??= []);

  for (final layer in cut.layers) {
    if (!layer.kind.composites) {
      continue; // Not in the picture: no node, and no base for a clip.
    }
    if (layer.kind.filtersBelow) {
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
    if (layer.kind.groupsLayers) {
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
        cut: cut,
        folder: layer,
        frameIndex: frameIndex,
      )) {
        // 통과, fully opaque: the folder is pure structure. Its members
        // belong to the parent exactly as if it were not there — no
        // buffer, no node, no cost. (Nothing clips to it, nor does it
        // clip: either would have buffered it.)
        for (final child in children) {
          addTo(layer.folderId, child);
        }
        continue;
      }
      place(
        layer,
        CompositeGroup<CutFrameCompositeRow>(
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
    // A row's ghosts go first, so its drawing lies over them — never in what
    // a clip cuts by, which they would widen: under the outermost folder
    // around the row that is a clip base, else by themselves where the row
    // stands alone (under a clip it is the base of), or onto the base it
    // clips to, cut as it is. ↩️As I-92 had `stackNodesWithGhosts` place
    // them.
    final ghosts = ghostsOf?.call(layer) ?? const <CutFrameCompositeGhost>[];
    final baseAround = ghosts.isEmpty ? null : _clipBaseAround(cut, layer);
    for (final ghost in ghosts) {
      final node = CompositeLeaf<CutFrameCompositeRow>(ghost);
      if (baseAround != null) {
        addTo(baseAround.folderId, node);
        continue;
      }
      switch (clipTargetOf(cut, layer).placed) {
        case ClipPlaced.alone:
          addTo(layer.folderId, node);
        case ClipPlaced.clipped:
          place(layer, node);
        case ClipPlaced.nowhere:
          break;
      }
    }
    final row = _resolveLayerNode(cut, layer, (
      frameIndex: frameIndex,
      foldBufferedFolders: false,
      liveLayerId: liveLayerId,
    ));
    if (row != null) {
      final [standing, ...over] = _rowNodes(
        cut,
        layer,
        row,
        asOnePicture: meetsAClip(cut, layer),
      );
      place(layer, standing);
      // The letters over a row that neither clips nor is clipped to — so
      // [place] laid it last in its list.
      for (final letters in over) {
        addTo(layer.folderId, letters);
      }
    }
  }
  // A row in an advanced blend goes over a picture of its scope — once
  // the tree is whole, because a scope is then simply a list (the law's own
  // doc says why) — and the rows a chain reads beside it, once that is.
  return readingTheirRows(
    composeOverTheirBackdrops(
      childrenOf[null] ?? const <CompositeNode<CutFrameCompositeRow>>[],
      blendOf: (row) => row.blendMode,
      paintedNormal: (row) => row.paintedNormal(),
    ),
    cut: cut,
    frameIndex: frameIndex,
    liveLayerId: liveLayerId,
  );
}

/// [row] — [layer]'s, at a frame — as its nodes in a tree, bottom → top:
/// its picture, and the letters of a cel number its chain writes
/// ([celNumberedRow]).
List<CompositeNode<CutFrameCompositeRow>> _rowNodes(
  Cut cut,
  Layer layer,
  CutFrameCompositeRow row, {
  required bool asOnePicture,
}) => celNumberedRow(
  paint: (opacity: row.opacity, blendMode: row.blendMode, effects: row.effects),
  rowOf: row.withPaint,
  text: celNumberText(
    rowName: layer.name,
    drawingName: switch (row) {
      CutFrameCompositeEntry(:final frame) => frame.name,
      // Drawn on where nothing is exposed yet: the drawing the pen
      // makes, which is born unnamed.
      CutFrameCompositeLiveRow() => null,
      CutFrameCompositeGhost() => throw StateError(
        'a row resolves to its own node, never to a ghost',
      ),
    },
    kind: layer.kind,
  ),
  paper: cut.canvasSize,
  asOnePicture: asOnePicture,
);

/// [nodes] of [cut]'s frame [frameIndex] with each whose own chain reads
/// rows of the cut — a camera lens blur's blur map (🗣️I-132-Q16 a) —
/// reading them ([withTheRowsTheyRead]): each as it draws there by itself
/// ([_rowAsRead]), a ghost's at the frame its peg reaches — a ghost shows
/// what the screen shows there (I-8-Q5). [liveLayerId] as
/// [resolveCutFrameCompositeTree]'s.
List<CompositeNode<CutFrameCompositeRow>> readingTheirRows(
  List<CompositeNode<CutFrameCompositeRow>> nodes, {
  required Cut cut,
  required int frameIndex,
  required LayerId? liveLayerId,
}) => withTheRowsTheyRead(
  nodes,
  effectsOf: (row) => row.effects,
  drawnOf: (row, by) => switch (by) {
    CutFrameCompositeGhost(frameIndex: final at) => _rowAsRead(
      cut,
      row,
      frameIndex: at,
      liveLayerId: null,
    ),
    _ => _rowAsRead(
      cut,
      row,
      frameIndex: frameIndex,
      liveLayerId: liveLayerId,
    ),
  },
);

/// Row [id] of [cut] at [frameIndex] as a chain that reads it reads it: as
/// it draws there by itself ([layerDrawingAt]) — where it lies
/// (🗣️I-132-Q21 a), its eye not asked (🗣️I-132-Q23 a), at its own strength
/// (🗣️I-132-Q24 b), on nothing, so in no blend — and naming no row of its
/// own (🗣️I-132-Q22 a). Nothing where it exposes no cel, save the row
/// drawn on ([liveLayerId]); a folder as what it holds ([_folderAsRead]);
/// null for no row of the cut or one that paints nothing of its own, which
/// reads as none.
List<CompositeNode<CutFrameCompositeRow>>? _rowAsRead(
  Cut cut,
  LayerId id, {
  required int frameIndex,
  required LayerId? liveLayerId,
}) {
  final layer = cut.layers.byId(id);
  if (layer != null && layer.kind.groupsLayers) {
    return _folderAsRead(
      cut,
      layer,
      frameIndex: frameIndex,
      liveLayerId: liveLayerId,
    );
  }
  final drawing = layer == null
      ? null
      : layerDrawingAt(cut: cut, layer: layer, frameIndex: frameIndex);
  if (layer == null || drawing == null) {
    return null;
  }
  final (:frame, :render) = drawing;
  final effects = [for (final effect in render.effects) effect.namingNoRow];
  final row = switch (frame) {
    final frame? => CutFrameCompositeEntry(
      layer: layer,
      frame: frame,
      opacity: render.opacity,
      placement: render.placement,
      effects: effects,
    ),
    null when layer.id == liveLayerId => CutFrameCompositeLiveRow(
      layer: layer,
      render: (
        opacity: render.opacity,
        blendMode: LayerBlendMode.normal,
        placement: render.placement,
        effects: effects,
      ),
    ),
    null => null,
  };
  return row == null
      ? const []
      : _rowNodes(cut, layer, row, asOnePicture: false);
}

/// Folder [folder] of [cut] at [frameIndex] as a chain that reads it reads
/// it: what it holds composed as it composes it, its own strength and
/// chain on that (🗣️I-132-Q25 a 「폴더는 안의 행들을 합친 그림으로 읽는다」)
/// — and otherwise as a row is read ([_rowAsRead]): under the poses of the
/// folders above it and none of their strength, blend, chain or eye, its
/// own eye not asked, on nothing, so in no blend, and naming no row, it or
/// any row it holds (one level).
///
/// The cut's one tree laid ([resolveCutFrameCompositeTree]) with every row
/// but the folder's hidden: the stack's structure as it stands, so a row it
/// holds that rides a base outside it rides it still (a base's eye never
/// reaches its attach rows). The folder and those above it pass through
/// and clip nowhere, nor does a row hidden, so none buffers but for what
/// the folder's own strength and chain ask ([folderNeedsCompositeBuffer]).
List<CompositeNode<CutFrameCompositeRow>> _folderAsRead(
  Cut cut,
  Layer folder, {
  required int frameIndex,
  required LayerId? liveLayerId,
}) {
  final above = {
    for (final layer in cut.layers.ancestryOf(folder.folderId)) layer.id,
  };
  final held = {
    for (final layer in cut.layers.subtreeMembersOf(folder.id)) layer.id,
  };
  Layer alone(Layer layer) {
    final namingNone = layer.copyWith(
      effects: effectsWithRowsRenamed(layer.effects, (_) => null),
    );
    if (layer.id == folder.id) {
      return namingNone.copyWith(
        isVisible: true,
        blendMode: LayerBlendMode.passThrough,
        clipsToBelow: false,
      );
    }
    if (above.contains(layer.id)) {
      return layer.copyWith(
        isVisible: true,
        opacity: 1,
        blendMode: LayerBlendMode.passThrough,
        clipsToBelow: false,
        effects: const [],
        transformTrack: layer.transformTrack.copyWith(
          opacity: PropertyTrack<double>(),
        ),
      );
    }
    return held.contains(layer.id)
        ? namingNone
        : namingNone.copyWith(isVisible: false, clipsToBelow: false);
  }

  return resolveCutFrameCompositeTree(
    cut: cut.copyWith(layers: [for (final layer in cut.layers) alone(layer)]),
    frameIndex: frameIndex,
    liveLayerId: liveLayerId,
  );
}

/// [resolveCutFrameCompositeTree] with each leaf's surface resolved;
/// entries whose frame has no artwork drop out, and a group left empty by
/// that drops with them (an empty buffer is a wasted saveLayer) — save one
/// a cel number is written on, which stands bare ([mapCompositeLeaves]).
///
/// [reading]: how each row's cel is read ([CelReading]).
List<CompositeNode<CutFrameCompositeLayer>> planCutFrameCompositeTree({
  required Cut cut,
  required int frameIndex,
  required CelReading reading,
}) => _withSurfaces(
  resolveCutFrameCompositeTree(cut: cut, frameIndex: frameIndex),
  cut: cut,
  frameIndex: frameIndex,
  reading: reading,
);

/// Row [row] of [cut] at [frameIndex] as a chain that reads it reads it
/// ([_rowAsRead]), its surfaces resolved as [planCutFrameCompositeTree]
/// resolves them: what a route that lays a row by itself hands
/// [withTheRowsTheyRead]. Null for no row there.
List<CompositeNode<CutFrameCompositeLayer>>? planRowAsRead({
  required Cut cut,
  required LayerId row,
  required int frameIndex,
  required CelReading reading,
}) => switch (_rowAsRead(cut, row, frameIndex: frameIndex, liveLayerId: null)) {
  final read? => _withSurfaces(
    read,
    cut: cut,
    frameIndex: frameIndex,
    reading: reading,
  ),
  null => null,
};

/// [nodes] of [cut] with each leaf's surface read by [reading]
/// ([planCutFrameCompositeTree]), and every chain's plugins run as it says.
List<CompositeNode<CutFrameCompositeLayer>> _withSurfaces(
  List<CompositeNode<CutFrameCompositeRow>> nodes, {
  required Cut cut,
  required int frameIndex,
  required CelReading reading,
}) {
  List<ResolvedLayerEffect> bound(List<ResolvedLayerEffect> chain) =>
      reading.plugins?.call(chain, cut: cut, frameIndex: frameIndex) ?? chain;
  CutFrameCompositeLayer? layerOf(
    CutFrameCompositeRow row,
    BitmapSurface? Function(CutFrameCompositeEntry entry) surfaceOf,
  ) => switch (row) {
    // ⛔THIS ROUTE HAS NO LIVE PIXELS. Only the editing stack asks the
    // tree for a live row, and only it owns the surface to fill the slot
    // with; every other route resolves surfaces from stored frames.
    // Reached here it would be a caller handing a live row to a route
    // that cannot draw it, so it contributes nothing rather than guessing.
    // Nor has the film a ghost: only the editing canvas lays one.
    CutFrameCompositeLiveRow() || CutFrameCompositeGhost() => null,
    CutFrameCompositeEntry() => switch (surfaceOf(row)) {
      final surface? => CutFrameCompositeLayer(
        surface: surface,
        opacity: row.opacity,
        blendMode: row.blendMode,
        placement: row.placement,
        effects: bound(row.effects),
      ),
      null => null,
    },
  };

  return List.unmodifiable(
    mapCompositeLeaves(
      nodes,
      (row) => layerOf(
        row,
        (entry) => reading.surfaces(entry.layer, entry.frame),
      ),
      bare: (row) =>
          layerOf(row, (_) => BitmapSurface(canvasSize: cut.canvasSize)),
      chains: bound,
    ),
  );
}

/// The frame exposed at [frameIndex]: the drawing block covering the index
/// (same semantics as TimelineController.resolveFrameForLayer — uncovered
/// cells and marks in empty space show nothing). Shared by the composite
/// plan and the composite cache signature so both always agree on what a
/// frame shows.
///
/// A MOVIE kept as a reference answers with the MOVIE CEL of the position
/// ([movieCelFrameId]): its one held cel shows a different picture at every
/// frame of the block. Here, in the visit the composite plan, its signature,
/// the editing stack and export all read — so no route can show a movie
/// another way.
Frame? resolveExposedFrameAt(Layer layer, int frameIndex) {
  final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
  if (block == null) {
    return null;
  }
  final frame = layer.frameById(block.frameId);
  if (frame == null || !isMovieReference(layer)) {
    return frame;
  }
  return frame.copyWith(
    id: movieCelFrameId(
      frame.id,
      movieElapsedAt(layer.mediaReference!, frameIndex - block.startIndex),
    ),
  );
}
