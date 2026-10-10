import '../../models/media_reference.dart';
import '../text/app_strings.dart' show AppText;
import 'property_lane_model.dart';
import 'scale_lane_form.dart';
import 'transform_lane_policy.dart'
    show formatTransformLaneValue, scrubTransformLaneValue;

/// A REFERENCE row's REFERENCE FX (I-68) — where the file it shows stands:
/// a fixed group, on every row that shows a file, never removable.
///
/// 🗣️유저 (I-68-Q1, 2026-10-10): 「참조fx만들고, 이 fx에는 헤더에 fx버튼
/// 안둠 … 레이어의 fx버튼 꺼도 그 자리 유지되고 출력시에도 fx 적용
/// 해제되있어도 유지됨 … 비슷한 다른 fx도 있었던것도같은데 있으면 통일」 —
/// the SE row's name tag is that other one (`se_name_tag_lane_policy.dart`):
/// a field the row simply HAS, with no switch to bypass it. The pose is
/// laid when the picture's pixels are made, so no switch reaches it.
///
/// Its values are the transform tool's (10-10: 「담는값은 변형도구랑 같은거
/// 공유」) — Position, Scale, Rotation, in the transform lanes' own words —
/// and they hold NO keys: where a file's picture stands does not move over
/// the cut (「키 없는 값 하나」).
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

/// How a reference's two scales read and are typed: a picture may stand
/// stretched along one axis (a stretch fit), so it is a layer's two.
const ScaleLaneForm referenceScaleForm = TwoScales();

/// The lane rows for [reference]: the header, and its members while the
/// group is twirled open.
List<PropertyLaneRow> referencePropertyLanes(
  MediaReference reference, {
  required bool expanded,
}) {
  final pose = reference.pose;
  return [
    PropertyLaneRow(
      laneId: referenceGroupLaneId,
      label: AppText.strings.tlReferenceGroup,
      keyMarks: const {},
      showsKeyNavigator: false,
      isGroupHeader: true,
      groupExpanded: expanded,
      // NO bypass switch (I-68-Q1 「헤더에 fx버튼 안둠」).
    ),
    if (expanded) ...[
      PropertyLaneRow(
        laneId: referencePositionLaneId,
        label: AppText.strings.tlLanePosition,
        keyMarks: const {},
        showsKeyNavigator: false,
        valueLabel: (_) => formatTransformLaneValue('position', pose),
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('position', label, delta),
      ),
      PropertyLaneRow(
        laneId: referenceScaleLaneId,
        label: AppText.strings.tlLaneScale,
        keyMarks: const {},
        showsKeyNavigator: false,
        valueLabel: (_) => referenceScaleForm.label(pose.scale),
        scrubValue: referenceScaleForm.scrubbed,
        linkable: referenceScaleForm.links,
      ),
      PropertyLaneRow(
        laneId: referenceRotationLaneId,
        label: AppText.strings.tlLaneRotation,
        keyMarks: const {},
        showsKeyNavigator: false,
        valueLabel: (_) => formatTransformLaneValue('rotation', pose),
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('rotation', label, delta),
      ),
    ],
  ];
}
