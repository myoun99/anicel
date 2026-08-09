import '../../models/se_name_tag.dart';
import 'property_lane_model.dart';

/// The SE row's NAME TAG group (R5 #7) — a fixed group, sibling of
/// Transform, auto-present on every SE row and never removable.
///
/// Not an entry in the effect chain: like `Layer.transformTrack`, the tag
/// is a field the row simply HAS, so there is no add, no delete, and no
/// reorder to offer. The lane ids are plain names for that reason — an
/// effect lane carries an EffectId because a row may hold two Blurs; a row
/// has exactly one name tag.
const String seNameTagGroupLaneId = 'name-tag-group';

/// The member lane ids, in display order.
const String seNameTagSizeLaneId = 'name-tag:size';
const String seNameTagTrackingLaneId = 'name-tag:tracking';
const String seNameTagBoldLaneId = 'name-tag:bold';
const String seNameTagNameInkLaneId = 'name-tag:name-ink';
const String seNameTagBoxColorLaneId = 'name-tag:box-color';
const String seNameTagLineInkLaneId = 'name-tag:line-ink';
const String seNameTagShowLineLaneId = 'name-tag:show-line';

const List<String> seNameTagLaneDisplayOrder = [
  seNameTagSizeLaneId,
  seNameTagTrackingLaneId,
  seNameTagBoldLaneId,
  seNameTagNameInkLaneId,
  seNameTagBoxColorLaneId,
  seNameTagLineInkLaneId,
  seNameTagShowLineLaneId,
];

/// The rows as SELECTION sees them: the header leads, like Transform's.
List<String> get seNameTagLaneSelectionOrder => [
  seNameTagGroupLaneId,
  ...seNameTagLaneDisplayOrder,
];

/// Whether [laneId] belongs to the name-tag group (header included) — the
/// predicate every routing switch asks instead of matching seven strings.
bool laneIsSeNameTag(String? laneId) =>
    laneId == seNameTagGroupLaneId ||
    (laneId != null && laneId.startsWith('name-tag:'));

/// The display-ordered lane span from [anchorLaneId] to [headLaneId], the
/// name-tag twin of `transformLaneSpan`.
List<String> seNameTagLaneSpan(String anchorLaneId, String headLaneId) {
  final order = seNameTagLaneSelectionOrder;
  final anchor = order.indexOf(anchorLaneId);
  final head = order.indexOf(headLaneId);
  if (anchor < 0 || head < 0) {
    return [anchorLaneId];
  }
  final low = anchor < head ? anchor : head;
  final high = anchor < head ? head : anchor;
  return order.sublist(low, high + 1);
}

/// The value shown in a member's readout at [tag]'s RESOLVED state.
///
/// Colours read as `#RRGGBB` — the form the value editor parses back, and
/// short enough for the fixed value column. A missing box colour reads
/// `none`, which is a real state (the アフレコ box turned off) rather than
/// an absent one.
String formatSeNameTagLaneValue(String laneId, SeNameTag resolved) {
  String hex(int? argb) =>
      argb == null ? 'none' : '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  return switch (laneId) {
    seNameTagSizeLaneId => _number(resolved.style.fontSize),
    seNameTagTrackingLaneId => _number(resolved.style.letterSpacing),
    seNameTagBoldLaneId => resolved.style.bold ? 'on' : 'off',
    seNameTagNameInkLaneId => hex(resolved.style.color),
    seNameTagBoxColorLaneId => hex(resolved.style.backgroundColor),
    seNameTagLineInkLaneId => hex(resolved.lineStyle.color),
    seNameTagShowLineLaneId => resolved.showLine ? 'on' : 'off',
    _ => '',
  };
}

/// The lane rows for one SE row's name tag: the header, and its members
/// while the group is twirled open.
List<PropertyLaneRow> seNameTagPropertyLanes(
  SeNameTag tag, {
  required bool expanded,
  required SeNameTag Function(int frameIndex) resolveAt,
}) {
  final keys = tag.track ?? SeNameTagTrack.empty();
  Set<int> keyed(String laneId) => switch (laneId) {
    seNameTagSizeLaneId => keys.fontSize.keys.keys.toSet(),
    seNameTagTrackingLaneId => keys.letterSpacing.keys.keys.toSet(),
    seNameTagBoldLaneId => keys.bold.keys.keys.toSet(),
    seNameTagNameInkLaneId => keys.nameInk.keys.keys.toSet(),
    seNameTagBoxColorLaneId => keys.boxColor.keys.keys.toSet(),
    seNameTagLineInkLaneId => keys.lineInk.keys.keys.toSet(),
    seNameTagShowLineLaneId => keys.showLine.keys.keys.toSet(),
    _ => const {},
  };

  return [
    PropertyLaneRow(
      laneId: seNameTagGroupLaneId,
      label: 'Name Tag',
      // The members' key union, the summary every group header shows.
      keyedFrames: keys.keyedFrames,
      showsKeyNavigator: false,
      isGroupHeader: true,
      groupExpanded: expanded,
      // NO bypass switch: a fixed group has nothing to turn off — the SE
      // row's own eye already decides whether its tag shows at all.
    ),
    if (expanded)
      for (final laneId in seNameTagLaneDisplayOrder)
        PropertyLaneRow(
          laneId: laneId,
          label: seNameTagLaneLabel(laneId),
          keyedFrames: keyed(laneId),
          valueLabel: (frame) =>
              formatSeNameTagLaneValue(laneId, resolveAt(frame)),
        ),
  ];
}

/// The member's name in the rail. English here like every other lane label;
/// the localized strings are for controls a person reads as prose.
String seNameTagLaneLabel(String laneId) => switch (laneId) {
  seNameTagSizeLaneId => 'Size',
  seNameTagTrackingLaneId => 'Tracking',
  seNameTagBoldLaneId => 'Bold',
  seNameTagNameInkLaneId => 'Name Ink',
  seNameTagBoxColorLaneId => 'Box Colour',
  seNameTagLineInkLaneId => 'Dialogue Ink',
  seNameTagShowLineLaneId => 'Show Dialogue',
  _ => laneId,
};

String _number(double value) {
  final rounded = double.parse(value.toStringAsFixed(1));
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}
