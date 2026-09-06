import '../../models/se_name_tag.dart';
import '../text/app_strings.dart' show AppText;
import 'property_lane_lens.dart';
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

/// The value shown in a member's readout at [tag]'s RESOLVED state.
///
/// Colours read as `#RRGGBB` — the form the value editor parses back, and
/// short enough for the fixed value column. A missing box colour reads
/// `none`, which is a real state (the アフレコ box turned off) rather than
/// an absent one.
String formatSeNameTagLaneValue(String laneId, SeNameTag resolved) {
  const hex = formatLaneColorValue;
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

/// The name-tag family's lane table: where each member lane lives on the
/// track — the name-tag twin of `transformLaneLens`, and the family's arm
/// of the lane-scoped range move (UI-R23 #3 part 2) through
/// `trackWithLaneKeysShifted`. Null for the header and for any id that is
/// not a member lane.
LaneLens<SeNameTagTrack>? seNameTagLaneLens(String laneId) =>
    switch (laneId) {
      seNameTagSizeLaneId => PropertyLaneLens<SeNameTagTrack, double>(
        get: (keys) => keys.fontSize,
        set: (keys, lane) => keys.copyWith(fontSize: lane),
      ),
      seNameTagTrackingLaneId => PropertyLaneLens<SeNameTagTrack, double>(
        get: (keys) => keys.letterSpacing,
        set: (keys, lane) => keys.copyWith(letterSpacing: lane),
      ),
      seNameTagBoldLaneId => PropertyLaneLens<SeNameTagTrack, bool>(
        get: (keys) => keys.bold,
        set: (keys, lane) => keys.copyWith(bold: lane),
      ),
      seNameTagNameInkLaneId => PropertyLaneLens<SeNameTagTrack, int>(
        get: (keys) => keys.nameInk,
        set: (keys, lane) => keys.copyWith(nameInk: lane),
      ),
      seNameTagBoxColorLaneId => PropertyLaneLens<SeNameTagTrack, int>(
        get: (keys) => keys.boxColor,
        set: (keys, lane) => keys.copyWith(boxColor: lane),
      ),
      seNameTagLineInkLaneId => PropertyLaneLens<SeNameTagTrack, int>(
        get: (keys) => keys.lineInk,
        set: (keys, lane) => keys.copyWith(lineInk: lane),
      ),
      seNameTagShowLineLaneId => PropertyLaneLens<SeNameTagTrack, bool>(
        get: (keys) => keys.showLine,
        set: (keys, lane) => keys.copyWith(showLine: lane),
      ),
      _ => null,
    };

/// The member lane's keyed frames — the ONE per-lane key reader (the lane
/// builder, the move machine's keyed gate and the keyframe navigator all
/// read this; the name-tag twin of `transformLaneKeyFrames`).
Set<int> seNameTagLaneKeyFrames(SeNameTagTrack keys, String laneId) =>
    seNameTagLaneLens(laneId)?.keyFrames(keys) ?? const {};

/// The lane rows for one SE row's name tag: the header, and its members
/// while the group is twirled open.
List<PropertyLaneRow> seNameTagPropertyLanes(
  SeNameTag tag, {
  required bool expanded,
  required SeNameTag Function(int frameIndex) resolveAt,
}) {
  final keys = tag.track ?? SeNameTagTrack.empty();
  Set<int> keyed(String laneId) => seNameTagLaneKeyFrames(keys, laneId);

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
      //
      // The preview's strings are FIXED and localized: it shows the look,
      // never the block's own text, so it says the same thing wherever the
      // playhead parks (the user: "프리뷰는 그냥 어떤식으로 될지 확인만
      // 하는거니까"). The dialogue sample disappears with the Show
      // Dialogue member, which is the one thing it does follow.
      previewText: (
        name: AppText.strings.seNameTagPreviewName,
        line: AppText.strings.seNameTagPreviewLine,
        tagAt: resolveAt,
      ),
    ),
    if (expanded)
      for (final laneId in seNameTagLaneDisplayOrder)
        PropertyLaneRow(
          laneId: laneId,
          label: seNameTagLaneLabel(laneId),
          keyedFrames: keyed(laneId),
          valueKind: seNameTagLaneValueKind(laneId),
          colorCanBeNone: seNameTagLaneColorCanBeNone(laneId),
          valueLabel: (frame) =>
              formatSeNameTagLaneValue(laneId, resolveAt(frame)),
        ),
  ];
}

/// What KIND of value a member holds — the one place that knows, since it
/// is the same place that formats and parses it (F-22).
///
/// 🚨THE THREE INK LANES ARE COLOURS (유저 2026-08-26: 「아직도 멤버의
/// 색부분이 텍스트편집임. **색버튼으로.**」).
///
/// ⚠️They spent a round as [PropertyLaneValueKind.number] for a reason worth
/// keeping in view, because it was real: a colour circle cannot say `none`,
/// which the box colour IS when the アフレコ box is off, and typing the word
/// into the value editor was the only way back to it. Swapping the editor
/// for a circle would have deleted a state.
///
/// `Q-f22-none` put that to the user and the answer was **1번** — the shared
/// picker grows a 「없음」 row, live where absence is a real value and dead
/// where it is not. So all three are circles and the rule is one rule.
PropertyLaneValueKind seNameTagLaneValueKind(String laneId) => switch (laneId) {
  seNameTagBoldLaneId ||
  seNameTagShowLineLaneId => PropertyLaneValueKind.boolean,
  seNameTagNameInkLaneId ||
  seNameTagBoxColorLaneId ||
  seNameTagLineInkLaneId => PropertyLaneValueKind.color,
  _ => PropertyLaneValueKind.number,
};

/// Whether this lane's colour can be ABSENT — the box behind the name is
/// the one that can be turned off.
///
/// ⛔Asked of the lane, in the same file that formats and parses it, for the
/// reason [seNameTagLaneValueKind] is: a switch on lane ids anywhere else
/// would be a second place to keep the same knowledge.
bool seNameTagLaneColorCanBeNone(String laneId) =>
    laneId == seNameTagBoxColorLaneId;

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
