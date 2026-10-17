import '../../models/key_range_move.dart'
    show transformKeyMarkUnion, transformKeyNameUnion;
import '../../models/media_reference.dart';
import '../../models/transform_pose.dart';
import '../text/app_strings.dart' show AppText;
import 'property_lane_model.dart';
import 'scale_lane_form.dart';
import 'transform_lane_policy.dart' show transformPropertyLanes;

/// A REFERENCE row's REFERENCE FX (I-68) — where the file it shows stands:
/// a fixed group, on every row that shows a file, never removable.
///
/// 🗣️유저 (I-68-Q1, 2026-10-10): 「참조fx만들고, 이 fx에는 헤더에 fx버튼
/// 안둠 … 레이어의 fx버튼 꺼도 그 자리 유지되고 출력시에도 fx 적용
/// 해제되있어도 유지됨 … 비슷한 다른 fx도 있었던것도같은데 있으면 통일」 —
/// the SE row's name tag is that other one (`se_name_tag_lane_policy.dart`):
/// a field the row simply HAS, with no switch to bypass it.
///
/// Its values are the transform tool's (10-10: 「담는값은 변형도구랑 같은거
/// 공유」) — Position, Scale, Rotation, in the transform lanes' own words —
/// and since F-374 its lanes ARE the transform lanes, keyed the same way
/// (유저 2026-10-17: 「참조fx도 똑같이 fx로서 법 통일. 지금 움직여도 키
/// 안생긴다거나 그런 각종 fx관련 싹 통일」). ↩️They held NO keys: where a
/// file's picture stands did not move over the cut (「키 없는 값 하나」).
const String referenceGroupLaneId = 'reference-group';

/// The member lane ids, in display order.
const String referencePositionLaneId = 'reference:position';
const String referenceScaleLaneId = 'reference:scale';
const String referenceRotationLaneId = 'reference:rotation';

const List<String> referenceLaneDisplayOrder = [
  referencePositionLaneId,
  referenceScaleLaneId,
  referenceRotationLaneId,
];

/// The rows as SELECTION sees them: the header leads, like Transform's.
List<String> get referenceLaneSelectionOrder => [
  referenceGroupLaneId,
  ...referenceLaneDisplayOrder,
];

/// Whether [laneId] belongs to the reference group (header included) — the
/// predicate every routing switch asks.
bool laneIsReference(String? laneId) =>
    laneId == referenceGroupLaneId ||
    (laneId != null && laneId.startsWith('reference:'));

/// The transform lane a member is — the value it holds, read, written and
/// scrubbed in that lane's words. Null for the header and any other id.
String? referenceMemberTransformLane(String laneId) => switch (laneId) {
  referencePositionLaneId => 'position',
  referenceScaleLaneId => 'scale',
  referenceRotationLaneId => 'rotation',
  _ => null,
};

/// The member that holds the transform lane [laneId] — the other way round.
String _referenceLaneOf(String laneId) => 'reference:$laneId';

/// [laneIds] split by the track each lives on: a row's OWN transform lanes,
/// and its reference fx's members as the transform lanes they hold (F-374)
/// — what every verb on transform lanes asks before it reads a track.
({List<String> own, List<String> reference}) transformLanesByHome(
  Iterable<String> laneIds,
) => (
  own: [
    for (final laneId in laneIds)
      if (!laneIsReference(laneId)) laneId,
  ],
  reference: [
    for (final laneId in laneIds) ?referenceMemberTransformLane(laneId),
  ],
);

/// How a reference's two scales read and are typed: a picture may stand
/// stretched along one axis (a stretch fit), so it is a layer's two.
const ScaleLaneForm referenceScaleForm = TwoScales();

/// The lane rows for [reference]: the header — its keys' union, as the
/// Transform header draws its members' — and its members while the group
/// is twirled open: the transform lanes of its fx ([transformPropertyLanes]),
/// valued where [poseAt] stands the picture. Null [poseAt] leaves them
/// unvalued — a rail with no cut to read them in.
List<PropertyLaneRow> referencePropertyLanes(
  MediaReference reference, {
  required bool expanded,
  required TransformPose Function(double time)? poseAt,
}) {
  final fx = reference.fx;
  return [
    PropertyLaneRow(
      laneId: referenceGroupLaneId,
      label: AppText.strings.tlReferenceGroup,
      keyMarks: transformKeyMarkUnion(fx),
      keyNames: transformKeyNameUnion(fx),
      showsKeyNavigator: false,
      isGroupHeader: true,
      groupExpanded: expanded,
      headsAGraph: true,
      // NO bypass switch (I-68-Q1 「헤더에 fx버튼 안둠」).
    ),
    if (expanded)
      for (final lane in transformPropertyLanes(
        fx,
        scaleForm: referenceScaleForm,
        poseAt: poseAt,
        laneIdOf: _referenceLaneOf,
      ))
        if (!lane.isGroupHeader) lane,
  ];
}
