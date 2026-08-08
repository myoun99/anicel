import '../../models/attached_layer_resolve.dart';
import '../../models/key_range_move.dart' show transformKeyFrameUnion;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/transform_track.dart';
import '../../services/camera_pose_resolver.dart' show resolveCameraPoseAt;
import '../editor_session_manager.dart';
import 'effect_lane_policy.dart' show effectGroupLaneId, effectPropertyLanes;
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show seAudioLanesFor;
import 'transform_lane_policy.dart'
    show
        transformGroupHeader,
        transformGroupHeaderLane,
        transformPropertyLanes;

/// THE property lanes a layer contributes, in display order.
///
/// R10 lifted this out of the timeline tab host because it has a second
/// caller now: the ↑/↓ row nav, which lives in the workspace and until now
/// built its rows with `lanesForLayer: (_) => const []` — so lane rows were
/// not merely skipped by the walk, they were never created, and the two
/// `!row.isLane` guards inside it were dead code. Standing on a property
/// row (R10 #19) means the nav has to be able to LAND on one.
///
/// A second copy would have drifted from what the grids actually draw, so
/// there is one function and both callers read it.
List<PropertyLaneRow> timelineLanesForLayer({
  required Layer layer,
  required EditorSessionManager session,
  required Set<String> expandedGroupKeys,
}) {
  // Attach rows ride their BASE's transform/opacity lanes (W5 fx sharing)
  // — no lanes of their own in v1. R9: the 공정 ORGANIZER folder joins
  // them. It follows its base like its members do, so a transform or
  // effect chain here would be a second answer competing with the base's;
  // leaving the lanes up while the label has no fx switch would also let a
  // chain be added that nothing could bypass.
  if (attachRowWearsBaseComposite(layer, session.layers)) {
    return const [];
  }

  /// The track a layer's transform lanes edit: the camera rides the cut's
  /// camera track, every other kind its own layer track.
  ///
  /// The camera's goes through [EditorSessionManager.activeCutCameraTrack]
  /// rather than the cut directly, so a lane-move drag in flight previews
  /// here. Every other row gets that for free — the row's preview gate
  /// hands this function a previewed LAYER — but a camera row's lanes are
  /// not built from its Layer at all.
  TransformTrack laneTrackOf(Layer target) => target.kind == LayerKind.camera
      ? (session.activeCutCameraTrack ?? session.requireActiveCut.camera.track)
      : target.transformTrack;

  /// AE group collapse: the Transform group header always shows; its member
  /// lanes only while the layer's group is twirled open (default collapsed,
  /// host-owned per layer so it survives tab switches).
  List<PropertyLaneRow> collapsibleTransformGroup(
    List<PropertyLaneRow> group,
  ) {
    final expanded = expandedGroupKeys.contains(
      laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
    );
    return [
      // The header carries the member lanes' KEY UNION (UI-R20 #13, the
      // camera row's summary pattern) — one glance shows where the layer's
      // transform keys sit even while the group is collapsed.
      transformGroupHeader(
        expanded: expanded,
        keyedFrames: transformKeyFrameUnion(laneTrackOf(layer)),
        // R8: the group's own switch — on every row that owns a transform.
        // The camera's lives on the cut's track, so its header shows none
        // and the row-level master covers it.
        enabled: layerKindHasLayerTransform(layer.kind)
            ? layer.transformEnabled
            : null,
      ),
      if (expanded) ...group.where((lane) => !lane.isGroupHeader),
    ];
  }

  /// The full AE Transform group — Anchor Point / Position / Scale /
  /// Rotation / Opacity — identical on EVERY layer-track kind (R6-④:
  /// SE/instruction match the drawing layers exactly; unified feel is the
  /// point, per user).
  List<PropertyLaneRow> layerTransformLanes() => transformPropertyLanes(
    layer.transformTrack,
    includeAnchorAndOpacity: true,
    poseAt: (frameIndex) => session.layerPoseAtFrame(layer, frameIndex),
    anchorAt: (frameIndex) =>
        session.layerAnchorPointAtFrame(layer, frameIndex),
    opacityAt: (frameIndex) => session.layerOpacityAtFrame(layer, frameIndex),
  );

  /// The row's EFFECT lanes (R6), below its Transform group: one
  /// collapsible header per effect with its parameter lanes inside. Empty
  /// for every row that carries no effects, which is the default
  /// everywhere.
  List<PropertyLaneRow> layerEffectLanes() {
    if (layer.effects.isEmpty) {
      return const [];
    }
    return effectPropertyLanes(
      layer.effects,
      isExpanded: (effectId) => expandedGroupKeys.contains(
        laneGroupKey(layer.id, effectGroupLaneId(effectId)),
      ),
      valueAt: (effectId, parameterId, frameIndex) => session
          .layerEffectParameterAtFrame(layer, effectId, parameterId, frameIndex),
    );
  }

  switch (layer.kind) {
    case LayerKind.camera:
      // A camera row on screen implies an active cut.
      final cut = session.requireActiveCut;
      return collapsibleTransformGroup(
        transformPropertyLanes(
          cut.camera.track,
          poseAt: (frameIndex) => resolveCameraPoseAt(
            camera: cut.camera,
            canvasSize: cut.canvasSize,
            frameIndex: frameIndex,
          ),
        ),
      );
    case LayerKind.se:
      // Audio controls lead the SE twirl-down (the row's main tool); the
      // Transform group sits below, collapsed by default.
      return [
        ...seAudioLanesFor(layer),
        ...layerEffectLanes(),
        ...collapsibleTransformGroup(layerTransformLanes()),
      ];
    case LayerKind.adjustment:
      // R6b: an adjustment row has no picture to move, so its twirl-down is
      // the Effects groups alone — its whole content.
      return layerEffectLanes();
    case LayerKind.animation:
    case LayerKind.image:
    case LayerKind.text:
    case LayerKind.storyboard:
    case LayerKind.instruction:
    // A folder's FX lanes ARE layer lanes (R27 #26 asked for the layer lane
    // grammar verbatim; now it is literally the same code path).
    case LayerKind.folder:
      // R9 #24: the list IS the pipeline — further from the row means
      // applied later. Effects first, then Transform at the bottom, which
      // is both AE's twirl-down (Masks → Effects → Transform) and what this
      // app already DOES: the pose wraps the draw while the effect filters
      // sit inside it, so the transform is genuinely last. Only the reading
      // order was upside down.
      return [
        ...layerEffectLanes(),
        ...collapsibleTransformGroup(layerTransformLanes()),
      ];
  }
}
