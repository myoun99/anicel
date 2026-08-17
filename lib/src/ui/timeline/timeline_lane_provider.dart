import '../../models/attached_layer_resolve.dart';
import '../../models/cut_camera.dart' show CutCamera;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/transform_track.dart';
import '../../services/camera_pose_resolver.dart' show resolveCameraPoseAt;
import '../editor_session_manager.dart';
import 'effect_lane_policy.dart' show effectGroupLaneId, effectPropertyLanes;
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show seAudioLanesFor;
import 'se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagPropertyLanes;
import 'transform_lane_policy.dart'
    show
        transformGroupHeaderLane,
        transformPropertyLanes,
        transformUnionHeader;

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
      // The header carries the member lanes' KEY UNION (UI-R20 #13) —
      // one glance shows where the layer's transform keys sit even while
      // the group is collapsed. [transformUnionHeader] is THE union
      // derivation, shared with the camera row's summary markers (B4).
      transformUnionHeader(
        track: laneTrackOf(layer),
        expanded: expanded,
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
      // ㉙ 유저 2026-08-12: 「카메라는 트랜스폼 헤더나 카메라나 똑같은 유니언의
      // 그룹이란 느낌인데, 중복이니까 카메라레이어는 트랜스폼헤더 삭제하자.
      // 펼치면 포지션/스케일/로테이션만 남도록.」
      //
      // ★The camera row IS the transform group. Its own band already draws
      // the member keys' union — the entire job a Transform header does for
      // every other row — so a header on top of it said the same noun twice
      // and cost a twirl to reach lanes the row was already summarising.
      //
      // 🚨B4-② (2026-08-17): through [laneTrackOf], NEVER `cut.camera.track`
      // directly. That is the preview-aware channel every other row gets
      // for free from its previewed Layer — reading the cut here is exactly
      // why camera member lanes sat still while every other transform lane
      // followed its drag live.
      final cameraTrack = laneTrackOf(layer);
      return transformPropertyLanes(
        cameraTrack,
        poseAt: (frameIndex) => resolveCameraPoseAt(
          // The SAME track the lanes are built from, so the value column
          // follows an in-flight key move like the diamonds do.
          camera: CutCamera.fromTrack(cameraTrack),
          canvasSize: cut.canvasSize,
          frameIndex: frameIndex,
        ),
      ).where((lane) => !lane.isGroupHeader).toList();
    case LayerKind.se:
      // Audio controls lead the SE twirl-down (the row's main tool); the
      // Transform group sits below, collapsed by default.
      //
      // R5 #7: the NAME TAG group is Transform's SIBLING — not a member of
      // it, and not an effect. The row simply HAS one, the way it has a
      // transform track, so it sits directly above Transform.
      final nameTag = layer.seNameTag ?? const SeNameTag();
      return [
        ...seAudioLanesFor(layer),
        ...layerEffectLanes(),
        ...seNameTagPropertyLanes(
          nameTag,
          expanded: expandedGroupKeys.contains(
            laneGroupKey(layer.id, seNameTagGroupLaneId),
          ),
          resolveAt: nameTag.resolveAt,
        ),
        ...collapsibleTransformGroup(layerTransformLanes()),
      ];
    case LayerKind.adjustment:
      // R6b: an adjustment row has no picture to move, so its twirl-down is
      // the Effects groups alone — its whole content.
      return layerEffectLanes();
    case LayerKind.transition:
      // Nothing to twirl down: the row carries transition spans and no
      // authoring of its own inside a cut. A lane here would be a second
      // place to edit what the global axis owns.
      return const [];
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

/// The CAMERA row's union summary lane — the row band's key markers.
///
/// ㉙ made the camera row its own transform group header, and B4
/// (2026-08-17) made that literal: the summary is a [transformUnionHeader]
/// lane, THE same constructor the fx transform header builds its union
/// from, drawn by the same marker widgets ([TimelineLaneKeyMarker]) at the
/// same union size. It read a private ◆/■ text-glyph table before, which
/// is how the mark could turn into a ○ mid-drag and sit at a subtly
/// different size than every other union mark.
///
/// Built from [EditorSessionManager.activeCutCameraTrack] — the
/// preview-aware channel — so an in-flight key move (lane move or block
/// ride) moves these markers live, exactly as a previewed Layer moves a
/// transform header's.
///
/// Null for every non-camera row: their union already rides their
/// transform group header lane.
PropertyLaneRow? timelineCameraUnionLane({
  required Layer layer,
  required EditorSessionManager session,
}) {
  if (layer.kind != LayerKind.camera) {
    return null;
  }
  final track =
      session.activeCutCameraTrack ?? session.activeCutOrNull?.camera.track;
  if (track == null) {
    return null;
  }
  return transformUnionHeader(track: track, expanded: false);
}
