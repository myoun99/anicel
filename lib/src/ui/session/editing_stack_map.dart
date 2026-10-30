import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/transform_pose.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../../services/layer_pose_matrix.dart'
    show LayerPlacement, pictureMoved;
import '../canvas/canvas_layer_stack_view.dart';
import '../timeline/timeline_drag_preview.dart'
    show TimelineDragPreview, celPixelsOf;
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
    required ProjectAccess project,
    required this.cut,
    required this.stackCut,
    required this.frameIndex,
    required this.activeLayerId,
    required TransformPose? Function(BrushFrameKey key) movieLaidAt,
    required FxPluginBinding? plugins,
    this.dragPreview,
  }) : _opacityVerbs = opacityVerbs,
       _project = project,
       _movieLaidAt = movieLaidAt,
       _plugins = plugins;

  final OpacityVerbs _opacityVerbs;
  final ProjectAccess _project;
  final Cut cut;
  final Cut stackCut;
  final int frameIndex;
  final LayerId? activeLayerId;

  /// The drag [stackCut] shows, if any: a cel it carries onto another row,
  /// or a picture it hangs in another cel, shows the pixels where they still
  /// are ([celPixelsOf]).
  final TimelineDragPreview? dragPreview;

  /// Where a movie cel's picture was laid, while one is installed
  /// (`MovieCelHydrator.laidAt`) — a moved reference fx shows the picture
  /// it has until the move's own is decoded.
  final TransformPose? Function(BrushFrameKey key) _movieLaidAt;

  /// What runs the plugins the rows' chains run ([FxPluginBinding]) — so
  /// every row the stack hands on carries its plugin's run, the row drawn
  /// on and a ghost at its own frame among them.
  final FxPluginBinding? _plugins;

  /// [effects] — [row]'s chain at [frameIndex] — with its plugin run.
  List<ResolvedLayerEffect> _bound(
    Layer row,
    List<ResolvedLayerEffect> effects,
    int frameIndex,
  ) =>
      _plugins?.call(
        effects,
        cut: stackCut,
        row: row,
        frameIndex: frameIndex,
      ) ??
      effects;

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
      CutFrameCompositeGhost() => _ghost(row),
    },
  );

  /// An onion ghost, from its cel where a drag shows its pixels
  /// ([celPixelsOf]) — whether the plan laid it in place or the canvas lays
  /// it over the frame (`OnionSkin.ghostsAt`).
  CanvasGhostImageRequest _ghost(CutFrameCompositeGhost ghost) {
    final pixels = celPixelsOf(dragPreview, ghost.layer.id, ghost.frameId);
    return CanvasGhostImageRequest(
      frameKey: _project.brushFrameKeyForCut(cut, pixels.row, pixels.cel),
      opacity: ghost.opacity,
      blendMode: ghost.blendMode,
      tint: ghost.tint,
      effects: _bound(ghost.layer, ghost.effects, ghost.frameIndex),
    );
  }

  /// The cel the brush holds on the row being drawn on: the one [cut] — as
  /// COMMITTED — exposes at [frameIndex]. A drag moves the picture
  /// ([stackCut]); the brush stays on its cel until the release.
  late final FrameId? _heldCel = activeLayerId == null
      ? null
      : exposedCelIdAt(
          cut: cut,
          layerId: activeLayerId!,
          frameIndex: frameIndex,
        );

  /// The row being drawn on with NOTHING exposed at this frame — the plan
  /// still placed it, in its folder and at its z, so the first stroke
  /// lands where the picture says it should (유저 확정 2026-09-04: 재생과
  /// 똑같이). The hand-built block this replaced appended it at the top
  /// level and lost all three.
  ///
  /// Null — nothing drawn — while a drag has moved the brush's cel away
  /// from here: the live surface would show that cel where the drag shows
  /// none ([_leaf] says why the row still reports its opacity and keys).
  CanvasStackRow? _live(CutFrameCompositeLiveRow node) {
    activeLayerOpacity = _opacityVerbs.stackLayerOpacity(
      node.layer,
      stackCut.layers,
      frameIndex,
    );
    final effects = _bound(node.layer, node.render.effects, frameIndex);
    activeSourceEffects = splitSourceEffects(effects).source;
    if (_heldCel != null) {
      return null;
    }
    return CanvasActiveLayerRow(
      opacity: node.render.opacity,
      blendMode: node.render.blendMode,
      placement: node.render.placement,
      effects: effects,
    );
  }

  /// [entry]'s placement, with the picture of a file it shows moved from
  /// where its cel was LAID to where the row's reference lays it
  /// ([MediaReference.laid], I-68) — a movie's installed picture decoded
  /// where its file was laid before. The plan's own placement moves it on
  /// from there to where the fx stands it (F-374).
  ///
  /// Where a cel was laid: a still's where the committed row lays it — its
  /// picture is made anew in the same step that lays it — and a movie's
  /// wherever its installed picture was decoded.
  LayerPlacement? _whereTheFileStands(
    CutFrameCompositeEntry entry,
    BrushFrameKey key,
  ) {
    final shown = entry.layer.mediaReference;
    final laid = shown == null
        ? null
        : _movieLaidAt(key) ??
              cut.layers.byId(entry.layer.id)?.mediaReference?.laid;
    if (shown == null || laid == null || laid == shown.laid) {
      return entry.placement;
    }
    final moved = pictureMoved(
      from: laid,
      to: shown.laid,
      picture: shown.pictureSize,
    );
    if (moved == null) {
      return entry.placement;
    }
    return entry.placement?.compose(moved) ?? moved;
  }

  /// A cached row — or the ACTIVE one when the brush cannot draw on it, or
  /// while a drag shows another cel on it than the one the brush holds.
  ///
  /// A brush-banned active layer (SE/instruction, R6-④; a media REFERENCE
  /// layer, §6-z23) has no interactive surface — it composites like any
  /// other stack row so its existing cels keep displaying read-only.
  ///
  /// 🚨A DRAG THAT MOVES THE BRUSH'S CEL (canvas-follows-block-moves, 유저
  /// 2026-09-28 「따라가게」): the live surface draws the cel the brush holds,
  /// so while a block, a comma or a file puts another cel at the playhead the
  /// row composites THAT cel as an image, like every other row, and goes live
  /// again on the release. It still reports its opacity and its keys — they
  /// are the ROW's, and the panel wraps the live surface in them: an opacity
  /// that fell to the default would unwrap it and remount it twice per drag.
  CanvasStackRow _leaf(CutFrameCompositeEntry entry) {
    final effects = _bound(entry.layer, entry.effects, frameIndex);
    final active =
        entry.layer.id == activeLayerId && layerAcceptsBrushInput(entry.layer);
    if (active) {
      // ⛔MUTANT SURVIVES ON THE HIDDEN-ROW ARM BELOW, and the
      // classification is NEVER APPLIED (2026-09-08): `_resolveLayerNode`
      // asks the row's own eye BEFORE it builds an entry, so a hidden row
      // never reaches this walk at all — no entry, no leaf, no active node.
      // Kept as the local statement of "the eye is off ⇒ nothing shows" for
      // a caller that hands this map a tree built some other way.
      activeLayerOpacity = !entry.layer.isVisible
          ? 0.0
          : _opacityVerbs.stackLayerOpacity(
              entry.layer,
              stackCut.layers,
              frameIndex,
            );
      activeSourceEffects = splitSourceEffects(effects).source;
    }
    final pixels = celPixelsOf(dragPreview, entry.layer.id, entry.frame.id);
    final key = _project.brushFrameKeyForCut(cut, pixels.row, pixels.cel);
    // The brush's cel with a picture a drag is bringing it from another
    // (F-330) is another picture at the playhead all the same.
    final itsOwnPicture = pixels == (row: entry.layer.id, cel: entry.frame.id);
    if (!active || entry.frame.id != _heldCel || !itsOwnPicture) {
      return CanvasLayerImageRequest(
        frameKey: key,
        opacity: entry.opacity,
        blendMode: entry.blendMode,
        placement: _whereTheFileStands(entry, key),
        effects: effects,
      );
    }
    return CanvasActiveLayerRow(
      opacity: entry.opacity,
      // The active row's CEL key — the SAME key the image branch above
      // asks with. The build in which this cel leaves the active slot, the
      // stack reads it off the widget it replaces and composes the cel's
      // image on the spot, so the row does not go blank for the frames an
      // asynchronous build takes ([CanvasActiveLayerRow.frameKey]). A drag
      // that carries the cel onto another row keeps it: the image there is
      // asked where its pixels still are ([celPixelsOf]).
      frameKey: key,
      // The SAME entry the image branch above reads it from. It was
      // dropped right here — five fields arrived and four were forwarded,
      // so standing on a multiply row silently made it normal on the
      // editing canvas only.
      blendMode: entry.blendMode,
      placement: entry.placement,
      effects: effects,
    );
  }
}
