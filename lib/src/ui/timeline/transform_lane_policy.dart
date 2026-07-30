import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/layer_id.dart';
import '../../models/property_track.dart';
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/transform_track.dart';
import 'effect_lane_policy.dart';
import 'property_lane_model.dart';

/// The AE-style 'Transform' GROUP HEADER row leading the transform lanes —
/// the twirl-down's structural spine: Transform first, Effects stack below
/// on the same lane substrate later.
const PropertyLaneRow transformGroupHeaderLane = PropertyLaneRow(
  laneId: 'transform-group',
  label: 'Transform',
  keyedFrames: {},
  showsKeyNavigator: false,
  isGroupHeader: true,
);

/// [transformGroupHeaderLane] carrying the collapse state (the header's
/// chevron; tapping the header toggles it — AE group collapse).
///
/// [keyedFrames] is the member lanes' KEY UNION (UI-R20 #13, the camera
/// row's summary pattern): the header band shows every keyed frame at a
/// glance — display-only markers (a union diamond has no single lane to
/// edit); the range move shifts the keys through the LAYER row's
/// selection.
PropertyLaneRow transformGroupHeader({
  required bool expanded,
  Set<int> keyedFrames = const {},
  bool? enabled,
}) {
  return PropertyLaneRow(
    laneId: transformGroupHeaderLane.laneId,
    label: transformGroupHeaderLane.label,
    keyedFrames: keyedFrames,
    showsKeyNavigator: false,
    isGroupHeader: true,
    groupExpanded: expanded,
    // R8: the group's own bypass, the same switch every effect header
    // carries ([Layer.transformEnabled]). Null on rows that have no
    // transform of their own to bypass (the camera moves through the cut's
    // camera track; its row-level switch covers that).
    groupEnabled: enabled,
  );
}

/// The AE Transform-group lanes of a [TransformTrack], in AE order under
/// the 'Transform' group header — Anchor Point / Position / Scale /
/// Rotation / Opacity ([includeAnchorAndOpacity] gates the two layer-only
/// lanes; the camera's group stays the pose trio).
///
/// [poseAt]/[anchorAt]/[opacityAt] resolve the values for the value column
/// (AE display units: Position and Anchor Point in canvas px, Scale as
/// zoom·100 %, Rotation in clockwise degrees, Opacity ·100 %); null hides
/// the values.
List<PropertyLaneRow> transformPropertyLanes(
  TransformTrack track, {
  bool includeAnchorAndOpacity = false,
  TransformPose Function(int frameIndex)? poseAt,
  CanvasPoint Function(int frameIndex)? anchorAt,
  double Function(int frameIndex)? opacityAt,
}) {
  return [
    transformGroupHeaderLane,
    if (includeAnchorAndOpacity)
      _lane(
        'anchor-point',
        'Anchor Point',
        track.anchorPoint,
        valueLabel: anchorAt == null
            ? null
            : (frame) {
                final anchor = anchorAt(frame);
                return '${_number(anchor.x)}, ${_number(anchor.y)}';
              },
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('anchor-point', label, delta),
      ),
    _lane(
      'position',
      'Position',
      track.position,
      valueLabel: poseAt == null
          ? null
          : (frame) => formatTransformLaneValue('position', poseAt(frame)),
      scrubValue: (label, delta) =>
          scrubTransformLaneValue('position', label, delta),
    ),
    _lane(
      'scale',
      'Scale',
      track.scale,
      valueLabel: poseAt == null
          ? null
          : (frame) => formatTransformLaneValue('scale', poseAt(frame)),
      scrubValue: (label, delta) =>
          scrubTransformLaneValue('scale', label, delta),
    ),
    _lane(
      'rotation',
      'Rotation',
      track.rotation,
      valueLabel: poseAt == null
          ? null
          : (frame) => formatTransformLaneValue('rotation', poseAt(frame)),
      scrubValue: (label, delta) =>
          scrubTransformLaneValue('rotation', label, delta),
    ),
    if (includeAnchorAndOpacity)
      _lane(
        'opacity',
        'Opacity',
        track.opacity,
        valueLabel: opacityAt == null
            ? null
            : (frame) => '${_number(opacityAt(frame) * 100)}%',
        scrubValue: (label, delta) =>
            scrubTransformLaneValue('opacity', label, delta),
      ),
  ];
}

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

/// The display-ordered lane span from [anchorLaneId] to [headLaneId]
/// (R26 #3 — the cell selection's Excel span rule applied to lane rows,
/// within one layer's lane group). The group HEADER as either endpoint
/// selects the WHOLE group ("모두에 적용되는 그 행"). Ids outside the
/// canonical order fall back to the anchor lane alone.
List<String> transformLaneSpan(String anchorLaneId, String headLaneId) {
  if (anchorLaneId == transformGroupHeaderLane.laneId ||
      headLaneId == transformGroupHeaderLane.laneId) {
    return List.of(transformLaneDisplayOrder);
  }
  final anchor = transformLaneDisplayOrder.indexOf(anchorLaneId);
  final head = transformLaneDisplayOrder.indexOf(headLaneId);
  if (anchor < 0 || head < 0) {
    return [anchorLaneId];
  }
  final low = anchor < head ? anchor : head;
  final high = anchor < head ? head : anchor;
  return transformLaneDisplayOrder.sublist(low, high + 1);
}

/// Whether the lane selection covers [laneId]'s BAND ROW on [layerId]
/// (R26 #3) — member lanes read the span directly; the group HEADER row
/// counts as covered when the selection spans its WHOLE member group, so
/// the header washes, rings, and (follow-up) grabs the whole group for a
/// move. One predicate, shared by the paint and the gesture's
/// move-vs-select decision. A FOLDER row's lanes ride this same order —
/// they are layer lanes now, not a private `folder-fx:` address space.
bool laneSelectionCoversBandRow(
  TimelineLaneSelection? selection,
  LayerId layerId,
  String laneId,
) {
  if (selection == null) {
    return false;
  }
  // R6: an EFFECT's header row answers the same question against its own
  // members (the effect lane ids carry which effect they belong to).
  if (parseEffectLaneId(laneId) != null) {
    return selection.layerId == layerId &&
        (selection.coversLane(layerId, laneId) ||
            effectGroupHeaderCovered(laneId, selection.spanLaneIds));
  }
  if (laneId == transformGroupHeaderLane.laneId) {
    return selection.layerId == layerId &&
        transformLaneDisplayOrder.every(selection.spanLaneIds.contains);
  }
  return selection.coversLane(layerId, laneId);
}

// A folder's FX lanes used to carry a `folder-fx:<folderId>:<base>`
// ADDRESS in the lane id, so the one laneEdit callback set could route
// commits into a folder table the layer path could not reach. A folder is
// a layer now: its lanes ARE layer lanes, keyed by the plain base lane id
// and routed by the row's own layer id like every other row's.

/// AE-style value formatting for a transform lane.
String formatTransformLaneValue(String laneId, TransformPose pose) {
  return switch (laneId) {
    'position' => '${_number(pose.center.x)}, ${_number(pose.center.y)}',
    'scale' => '${_number(pose.zoom * 100)}%',
    'rotation' => '${_number(pose.rotationDegrees)}°',
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
  double? parse(String raw) =>
      double.tryParse(raw.replaceAll('%', '').replaceAll('°', '').trim());
  switch (laneId) {
    case 'position':
    case 'anchor-point':
      final parts = currentLabel.split(',');
      if (parts.length != 2) {
        return null;
      }
      final x = parse(parts[0]);
      final y = parse(parts[1]);
      if (x == null || y == null) {
        return null;
      }
      return '${_number(x + dragDelta.dx)}, ${_number(y + dragDelta.dy)}';
    case 'scale':
      final percent = parse(currentLabel);
      if (percent == null) {
        return null;
      }
      return '${_number(percent + dragDelta.dx * 0.5)}%';
    case 'rotation':
      final degrees = parse(currentLabel);
      if (degrees == null) {
        return null;
      }
      return '${_number(degrees + dragDelta.dx * 0.5)}°';
    case 'opacity':
      final percent = parse(currentLabel);
      if (percent == null) {
        return null;
      }
      final scrubbed = (percent + dragDelta.dx * 0.5).clamp(0.0, 100.0);
      return '${_number(scrubbed)}%';
  }
  return null;
}

String _number(double value) {
  final rounded = double.parse(value.toStringAsFixed(1));
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}

PropertyLaneRow _lane<T>(
  String id,
  String label,
  PropertyTrack<T> track, {
  String Function(int frameIndex)? valueLabel,
  String? Function(String currentLabel, Offset dragDelta)? scrubValue,
}) {
  return PropertyLaneRow(
    laneId: id,
    label: label,
    keyedFrames: track.keys.keys.toSet(),
    holdOutFrames: {
      for (final entry in track.keys.entries)
        if (entry.value.interpolation == PropertyKeyInterpolation.hold)
          entry.key,
    },
    valueLabel: valueLabel,
    scrubValue: scrubValue,
  );
}
