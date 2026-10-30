import 'dart:ui' show Color, Offset;

import '../../models/camera_instruction.dart'
    show CameraInstructionDef;
import '../../models/camera_moves.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_camera.dart' show CutCamera;
import '../../models/key_mark.dart';
import '../../models/key_range_move.dart'
    show transformKeyMarkUnion, transformKeyNameUnion;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/property_track.dart';
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/transform_track.dart';
import '../../services/camera_pose_resolver.dart'
    show resolveCameraPoseAtTime;
import '../text/app_strings.dart';
import '../theme/lane_curve_palette.dart';
import '../text/readout_text.dart';
import 'property_lane_model.dart';
import 'scale_lane_form.dart';
import 'transform_lane_editing.dart' show opacityLaneNumbers;

/// The AE-style 'Transform' GROUP HEADER row leading the transform lanes —
/// the twirl-down's structural spine: Transform first, Effects stack below
/// on the same lane substrate later.
///
/// 🚨F-37 (유저 2026-09-15, F-37-Q1: 「전부 번역 — 레인 이름도 한국어로」 ·
/// 「ae도 애초에 언어설정따라서 트랜스폼이나 싹 다 번역되있잖아. 그러니 법
/// 하나로 다 번역」): the name is the program language's, so the row is built
/// on each read rather than held as a `const` — a constant cannot ask the
/// tables. `tlTransformGroup` sat tabled in five languages and read by
/// nobody, while this row said 'Transform' in all of them.
PropertyLaneRow get transformGroupHeaderLane => PropertyLaneRow(
  laneId: 'transform-group',
  label: AppText.strings.tlTransformGroup,
  keyMarks: const {},
  showsKeyNavigator: false,
  isGroupHeader: true,
  headsAGraph: true,
);

/// [transformGroupHeaderLane] carrying the collapse state (the header's
/// chevron; tapping the header toggles it — AE group collapse).
///
/// [keyMarks] is the member lanes' KEY UNION (UI-R20 #13, the camera row's
/// summary pattern) — see [transformKeyMarkUnion]: the header band shows
/// every keyed frame at a glance — display-only markers (a union mark has
/// no single lane to edit); the range move shifts the keys through the
/// LAYER row's selection.
PropertyLaneRow transformGroupHeader({
  required bool expanded,
  Map<int, KeyMark> keyMarks = const {},
  Map<int, String> keyNames = const {},
  bool? enabled,
  List<LaneStretchWord> stretchWords = const [],
}) {
  return PropertyLaneRow(
    laneId: transformGroupHeaderLane.laneId,
    label: transformGroupHeaderLane.label,
    keyMarks: keyMarks,
    // ㉚: the members' name where they agree, `...` where they do not —
    // see [transformKeyNameUnion].
    keyNames: keyNames,
    showsKeyNavigator: false,
    isGroupHeader: true,
    groupExpanded: expanded,
    headsAGraph: true,
    // R8: the group's own bypass, the same switch every effect header
    // carries ([Layer.transformEnabled]). Null on rows that have no
    // transform of their own to bypass (the camera moves through the cut's
    // camera track; its row-level switch covers that).
    groupEnabled: enabled,
    stretchWords: stretchWords,
  );
}

/// THE union summary of [track] as a lane row — mark union, name union —
/// the ONE derivation behind every union mark (2026-08-17 B4: 「한 로직으로
/// 통일이 요구의 본체」).
///
/// Two rows draw it: the fx TRANSFORM GROUP HEADER (its collapsed summary,
/// UI-R20 #13) and the CAMERA row, which since ㉙ *is* its own transform
/// group header. Both build their union through this function, so the mark
/// they draw — which frames key, which mark each wears, what they are
/// called — can never drift apart again. The camera's used to be a text
/// glyph channel with its own ◆/■/○ table, and the ○ is exactly what a
/// second derivation grows when nobody is looking.
PropertyLaneRow transformUnionHeader({
  required TransformTrack track,
  required bool expanded,
  bool? enabled,
  List<LaneStretchWord> stretchWords = const [],
}) {
  return transformGroupHeader(
    expanded: expanded,
    keyMarks: transformKeyMarkUnion(track),
    keyNames: transformKeyNameUnion(track),
    enabled: enabled,
    stretchWords: stretchWords,
  );
}

/// THE CAMERA ROW'S LANE — its keys' union ([transformUnionHeader]) with,
/// over the line between them, the move each stretch makes
/// ([cameraMoves], I-73 ⑤) by its name in the vocabulary [defById] reads,
/// in the row's key colour (`timelineStretchWordSpan`): the timeline's
/// camera row and the storyboard's draw this one lane.
PropertyLaneRow cameraUnionHeader(
  TransformTrack track, {
  required CameraInstructionDef? Function(String id) defById,
}) => transformUnionHeader(
  track: track,
  expanded: false,
  stretchWords: [
    for (final move in cameraMoves(track))
      (
        from: move.from,
        to: move.to,
        word: cameraMoveWord(move, defById),
      ),
  ],
);

/// THE CAMERA ROW'S LANES — the member lanes of the camera [track] its
/// [row] rides, valued by the camera's pose over a [canvasSize] frame: the
/// lanes the timeline's camera row twirls down, and the storyboard's camera
/// row each cut's (I-73 ④ⓔ). No [canvasSize] leaves them unvalued — a
/// rail with no cut to read them in.
///
/// ㉙ 유저 2026-08-12: 「카메라는 트랜스폼 헤더나 카메라나 똑같은 유니언의
/// 그룹이란 느낌인데, 중복이니까 카메라레이어는 트랜스폼헤더 삭제하자.
/// 펼치면 포지션/스케일/로테이션만 남도록.」 — the row IS the transform
/// group, so the header is not among them.
List<PropertyLaneRow> cameraPropertyLanes(
  Layer row,
  TransformTrack track, {
  required CanvasSize? canvasSize,
}) => transformPropertyLanes(
  track,
  scaleForm: scaleLaneFormOf(row),
  poseAt: canvasSize == null
      ? null
      : (time) => TransformPose.ofCamera(
          resolveCameraPoseAtTime(
            // The SAME track the lanes are built from, so the value column
            // follows an in-flight key move like the diamonds do.
            camera: CutCamera.fromTrack(track),
            canvasSize: canvasSize,
            time: time,
          ),
        ),
).where((lane) => !lane.isGroupHeader).toList();

/// The AE Transform-group lanes of a [TransformTrack], in AE order under
/// the 'Transform' group header — Anchor Point / Position / Scale /
/// Rotation / Opacity ([includeAnchorAndOpacity] gates the two layer-only
/// lanes; the camera's group stays the pose trio).
///
/// [poseAt]/[anchorAt]/[opacityAt] resolve the values at a time — a frame,
/// or between two: the value column reads them at its frame, a header
/// graph's curve between frames too (I-89 ③), so the two are one reading
/// (AE display units: Position and Anchor Point in canvas px, Scale as its
/// [scaleForm] prints it, Rotation in clockwise degrees, Opacity ·100 %);
/// null hides the values, and the curve with them.
///
/// [laneIdOf] names each member's row: a reference's fx is these lanes
/// under ids of its own (F-374, `reference:position`, …).
List<PropertyLaneRow> transformPropertyLanes(
  TransformTrack track, {
  required ScaleLaneForm scaleForm,
  bool includeAnchorAndOpacity = false,
  TransformPose Function(double time)? poseAt,
  CanvasPoint Function(double time)? anchorAt,
  double Function(double time)? opacityAt,
  String Function(String laneId) laneIdOf = _itsOwnLaneId,
}) {
  const point = [LaneCurvePalette.across, LaneCurvePalette.down];
  return [
    transformGroupHeaderLane,
    if (includeAnchorAndOpacity)
      _lane(
        laneIdOf('anchor-point'),
        AppText.strings.tlLaneAnchorPoint,
        track.anchorPoint,
        _reading(
          anchorAt,
          (anchor) => [anchor.x, anchor.y],
          parts: point,
          printed: (anchor) =>
              '${columnValueText(anchor.x)}, ${columnValueText(anchor.y)}',
        ),
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('anchor-point', label, delta),
        walks: pathKeySpace,
      ),
    transformPositionLane(
      track,
      laneId: laneIdOf('position'),
      label: AppText.strings.tlLanePosition,
      poseAt: poseAt,
    ),
    _lane(
      laneIdOf('scale'),
      AppText.strings.tlLaneScale,
      track.scale,
      _reading(
        poseAt,
        (pose) => scaleForm.numbers(pose.scale),
        parts: switch (scaleForm) {
          OneZoom() => const [LaneCurvePalette.scale],
          TwoScales() => const [
            LaneCurvePalette.scale,
            LaneCurvePalette.scaleDown,
          ],
        },
        printed: (pose) => scaleForm.label(pose.scale),
      ),
      scrubValue: scaleForm.scrubbed,
      linkable: scaleForm.links,
    ),
    _lane(
      laneIdOf('rotation'),
      AppText.strings.tlLaneRotation,
      track.rotation,
      _reading(
        poseAt,
        (pose) => [pose.rotationDegrees],
        parts: const [LaneCurvePalette.rotation],
        printed: (pose) => formatTransformLaneValue('rotation', pose),
      ),
      scrubValue: (label, delta) =>
          scrubTransformLaneValue('rotation', label, delta),
    ),
    if (includeAnchorAndOpacity)
      _lane(
        laneIdOf('opacity'),
        AppText.strings.tlLaneOpacity,
        track.opacity,
        _reading(
          opacityAt,
          (opacity) => [opacityLaneNumbers.shown(opacity)],
          parts: const [LaneCurvePalette.opacity],
          printed: (opacity) =>
              '${columnValueText(opacityLaneNumbers.shown(opacity))}%',
        ),
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('opacity', label, delta),
      ),
  ];
}

/// [track]'s Position row, as [laneId] and named [label] — the transform's
/// own, and an effect's point's (I-132-Q12 b: a Position of its own, named
/// as its effect names it), valued where [poseAt] stands it.
PropertyLaneRow transformPositionLane(
  TransformTrack track, {
  required String laneId,
  required String label,
  TransformPose Function(double time)? poseAt,
}) => _lane(
  laneId,
  label,
  track.position,
  _reading(
    poseAt,
    (pose) => [pose.center.x, pose.center.y],
    parts: const [LaneCurvePalette.across, LaneCurvePalette.down],
    printed: (pose) => formatTransformLaneValue('position', pose),
  ),
  scrubValue: (label, delta) =>
      scrubTransformLaneValue('position', label, delta),
  walks: pathKeySpace,
);

String _itsOwnLaneId(String laneId) => laneId;

/// What a lane's value column prints and the line a header graph draws it
/// by (I-89 ③), off ONE reading of its value — so the two cannot come to
/// disagree. The line's keys are the track's ([_lane]).
typedef _LaneReading = ({
  String Function(int frameIndex)? label,
  ({List<Color> parts, List<double> Function(double time) at})? curve,
});

/// The lane's value [at] a time — null where the rail has nothing to read
/// it in, which hides the column and the line with it — as [printed] writes
/// it on a frame, and as the [numbers] it holds at any time, each in its
/// colour of [parts].
_LaneReading _reading<V>(
  V Function(double time)? at,
  List<double> Function(V value) numbers, {
  required List<Color> parts,
  required String Function(V value) printed,
}) => at == null
    ? (label: null, curve: null)
    : (
        label: (frame) => printed(at(frame.toDouble())),
        curve: (parts: parts, at: (time) => numbers(at(time))),
      );

/// Canonical display order of the transform lanes (the AE order
/// [transformPropertyLanes] emits) — the lane-row span (R26 #3) resolves
/// anchor→head against this.
const List<String> transformLaneDisplayOrder = [
  'anchor-point',
  'position',
  'scale',
  'rotation',
  'opacity',
];

/// What the CANVAS can be driven with, for one standing lane.
///
/// R5 #10 — the rule, in the user's words: **an fx declares its own
/// manipulators.** Not "the twirl is open", which is what the position
/// crosshair used to answer to: opening a row's lanes to read a Blur radius
/// put a Position handle on the artwork, and picking Opacity left it there
/// still moving Position. What is selected is what you can grab.
enum CanvasManipulator {
  /// The transform box: position, scale and rotation on one frame, the way
  /// the selection transform already reads.
  transformBox,

  /// The anchor point on its own — the thing scale and rotation turn about,
  /// so it has to be placeable without them moving.
  anchorPoint,
}

/// The manipulators [laneId] declares. The GROUP HEADER declares everything
/// its members do, because standing on the group is standing on all of it.
///
/// A lane that names no manipulator — Opacity, and every effect parameter —
/// answers with nothing, and nothing is drawn. That is a real answer: the
/// user's rule was that showing a control for a value you cannot grab on
/// the canvas is worse than showing none.
Set<CanvasManipulator> canvasManipulatorsForLane(String? laneId) {
  if (laneId == transformGroupHeaderLane.laneId) {
    return const {CanvasManipulator.transformBox, CanvasManipulator.anchorPoint};
  }
  return switch (laneId) {
    'position' || 'scale' || 'rotation' => const {
      CanvasManipulator.transformBox,
    },
    'anchor-point' => const {CanvasManipulator.anchorPoint},
    _ => const {},
  };
}

/// Whether the lane selection covers [laneId]'s BAND ROW on [layerId]
/// (R26 #3): whether the row is IN the span — a group header as every
/// other row (R9 #20), not when its members happen to all be. One
/// predicate, shared by the paint and the gesture's move-vs-select
/// decision.
///
/// ↩️It asked an effect's header, the Transform header and every other row
/// apart, from when a header was covered by its whole member group; each
/// branch had come to ask the one membership question.
bool laneSelectionCoversBandRow(
  TimelineLaneSelection? selection,
  LayerId layerId,
  String laneId,
) => selection?.coversLane(layerId, laneId) ?? false;

/// Whether the lane selection holds [laneId]'s key cell at [frame] on
/// [layerId] ([laneSelectionCoversBandRow]): what a lane's band takes a
/// press there to MOVE rather than select, what its key mark rings for,
/// and what a header graph's key does both by (I-3) — so what reads as
/// picked is what a drag carries, wherever the key is drawn.
bool laneSelectionPicksKey(
  TimelineLaneSelection? selection,
  LayerId layerId,
  String laneId,
  int frame,
) =>
    selection != null &&
    laneSelectionCoversBandRow(selection, layerId, laneId) &&
    selection.contains(frame);

// A folder's FX lanes used to carry a `folder-fx:<folderId>:<base>`
// ADDRESS in the lane id, so the one laneEdit callback set could route
// commits into a folder table the layer path could not reach. A folder is
// a layer now: its lanes ARE layer lanes, keyed by the plain base lane id
// and routed by the row's own layer id like every other row's.

/// AE-style value formatting for a transform lane.
String formatTransformLaneValue(String laneId, TransformPose pose) {
  return switch (laneId) {
    'position' => '${columnValueText(pose.center.x)}, ${columnValueText(pose.center.y)}',
    'rotation' => turnsReadoutText(pose.rotationDegrees),
    _ => '',
  };
}

/// AE-style value scrubbing for a transform lane: horizontal drag drives
/// the (first) component, vertical drag drives the point lanes' y. The
/// result is the SAME text form the value editor parses — the release
/// commits it through the normal onSetValue path (one undo). Null = not
/// scrubbable.
String? scrubTransformLaneValue(
  String laneId,
  String currentLabel,
  Offset dragDelta,
) {
  switch (laneId) {
    case 'position':
    case 'anchor-point':
      return switch (columnPairOf(currentLabel)) {
        (final x, final y) =>
          '${columnValueText(x + dragDelta.dx)}, ${columnValueText(y + dragDelta.dy)}',
        null => null,
      };
    case 'rotation':
      final degrees = columnValueOf(currentLabel);
      if (degrees == null) {
        return null;
      }
      return turnsReadoutText(scrubbedAngle(degrees, dragDelta));
    case 'opacity':
      final percent = columnValueOf(currentLabel);
      if (percent == null) {
        return null;
      }
      final scrubbed = scrubbedNumber(percent, dragDelta).clamp(0.0, 100.0);
      return '${columnValueText(scrubbed)}%';
  }
  return null;
}

/// [track]'s lane, its line drawn off [reading] — walking the path [walks]
/// lays, where it is given one ([LaneCurve.way]).
PropertyLaneRow _lane<T>(
  String id,
  String label,
  PropertyTrack<T> track,
  _LaneReading reading, {
  String? Function(String currentLabel, Offset dragDelta)? scrubValue,
  bool linkable = false,
  KeyValueSpace<T>? walks,
}) {
  return PropertyLaneRow(
    laneId: id,
    label: label,
    keyMarks: keyMarksOf(track),
    keyNames: track.namedKeysByFrame,
    valueLabel: reading.label,
    scrubValue: scrubValue,
    linkable: linkable,
    curve: switch (reading.curve) {
      (:final parts, :final at) => (
        parts: parts,
        at: at,
        sides: track.sidesByFrame,
        way: walks == null ? null : (from) => track.wayFrom(from, walks),
      ),
      null => null,
    },
  );
}
