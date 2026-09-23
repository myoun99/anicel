import '../../models/attached_layer_resolve.dart';
import '../../models/canvas_size.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show effectParameterValueAt;
import '../../models/layer_kind.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/transform_track.dart';
import '../../services/cut_frame_composite_plan.dart' show layerIdentityPose;
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

/// THE property lanes a row contributes on the rail that asks, in display
/// order.
///
/// 🚨F-101 (유저 2026-09-12): 「스토리보드패널 se랑 타임라인패널 se랑 통일
/// 안되어있음. 뭐냐면 타임라인패널 se엔 네임태그등 fx 있는데 스토리보드패널엔
/// 네임태그가 없음. 이런거 다른거 확인해서 법 하나로 통일」. The storyboard built
/// its S rows' lanes itself — the Transform group, with Audio beside it — so
/// the name tag and the effects this list gives an SE row never reached it.
///
/// A row is read on one of two rails. A CUT's (the timeline, the X-sheet)
/// shows a track-SE row as the projection of the track's row; a TRACK's (the
/// storyboard) stands on that row's own axis. Which lanes, in which order and
/// which groups are open is one law on both, so it is this function, and the
/// two things that ARE the rail's come in as arguments:
///
///  * [valueSourceAt] — the row and frame a lane's value at a rail frame is
///    read off;
///  * [poseCentre] — the frame an unkeyed pose sits in the middle of: the
///    open cut's canvas on a cut's rail, the camera frame on a track's rail,
///    where a row spans cuts and following the open one showed another
///    track's S row its defaults. Null leaves the pose and anchor lanes
///    without a value.
///
/// [rows] are the rows the attach question is asked among. No session is
/// read here, so a rail that has none — the storyboard panel — asks it too.
///
/// The camera row is not read here: its lanes are the cut's camera track,
/// which only a cut's rail stands on (`timelineLanesForLayer`).
List<PropertyLaneRow> propertyLanesForRow({
  required Layer layer,
  required List<Layer> rows,
  required Set<String> expandedGroupKeys,
  required ({Layer layer, int frame}) Function(int frameIndex) valueSourceAt,
  required CanvasSize? poseCentre,
}) {
  // Attach rows ride their BASE's transform/opacity lanes (W5 fx sharing)
  // — no lanes of their own in v1. R9: the 공정 ORGANIZER folder joins
  // them. It follows its base like its members do, so a transform or
  // effect chain here would be a second answer competing with the base's;
  // leaving the lanes up while the label has no fx switch would also let a
  // chain be added that nothing could bypass.
  if (attachRowWearsBaseComposite(layer, rows)) {
    return const [];
  }

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
        track: layer.transformTrack,
        expanded: expanded,
        // R8: the group's own switch — on every row that owns a transform.
        // The camera's lives on the cut's track, so its header shows none
        // and the row-level master covers it.
        enabled: layer.kind.hasLayerTransform
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
  List<PropertyLaneRow> layerTransformLanes() {
    final centre = poseCentre;
    return transformPropertyLanes(
      layer.transformTrack,
      includeAnchorAndOpacity: true,
      poseAt: centre == null
          ? null
          : (frameIndex) {
              final at = valueSourceAt(frameIndex);
              return at.layer.transformTrack.resolveAt(
                frameIndex: at.frame,
                orElse: () => layerIdentityPose(centre),
              );
            },
      anchorAt: centre == null
          ? null
          : (frameIndex) {
              final at = valueSourceAt(frameIndex);
              return resolveAnchorTrackAt(
                    at.layer.transformTrack.anchorPoint,
                    at.frame,
                  ) ??
                  layerIdentityPose(centre).center;
            },
      opacityAt: (frameIndex) {
        final at = valueSourceAt(frameIndex);
        return resolveOpacityTrackAt(at.layer.transformTrack.opacity, at.frame);
      },
    );
  }

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
      valueAt: (effectId, parameterId, frameIndex) {
        final at = valueSourceAt(frameIndex);
        return effectParameterValueAt(
          at.layer.effects,
          effectId,
          parameterId,
          at.frame,
        );
      },
    );
  }

  switch (layer.kind) {
    case LayerKind.camera:
      throw ArgumentError.value(
        layer.kind,
        'layer',
        'a camera row reads its cut — ask timelineLanesForLayer',
      );
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
          resolveAt: (frameIndex) {
            final at = valueSourceAt(frameIndex);
            return (at.layer.seNameTag ?? const SeNameTag()).resolveAt(
              at.frame,
            );
          },
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
