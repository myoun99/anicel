import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../services/project_lookup.dart'
    show cutWritingRow, requireCut, rowPoseSpace;
import '../editor_session_manager.dart';
import 'lane_graph_seats.dart' show LaneGraphLine, laneGraphLineAmong;
import 'property_lane_model.dart';
import 'property_lanes_for_row.dart';
import 'timeline_drag_preview.dart' show timelineDragPreviewLayerFor;
import 'transform_lane_policy.dart'
    show cameraPropertyLanes, cameraUnionHeader;

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
///
/// ↩️The list itself is [propertyLanesForRow] now (F-101): the storyboard's S
/// rows are the same rows on a TRACK's rail, and a second copy had drifted
/// there exactly as this comment says one would. What stays here is what
/// only a CUT's rail can answer — the camera row, whose lanes are the cut's
/// camera track, and the projection a track-SE row is read through.
List<PropertyLaneRow> timelineLanesForLayer({
  required Layer layer,
  required EditorSessionManager session,
  required Set<String> expandedGroupKeys,
}) {
  if (layer.kind == LayerKind.camera) {
    return _cameraLanes(session, layer);
  }
  return propertyLanesForRow(
    layer: layer,
    rows: session.layers,
    expandedGroupKeys: expandedGroupKeys,
    // Where a lane on this row reads its VALUE at a frame: for a track-SE
    // row, the track's row at the global frame — the cut shows a projection
    // of it (F-102, 유저 「글로벌트랙은 fx든뭐던 로컬에선 글로벌을 투영해서
    // 보여주도록」). The KEYS each lane marks still come from [layer], which
    // is what this rail shows.
    valueSourceAt: (frameIndex) =>
        session.laneVerbs.laneValueSourceAt(layer, frameIndex),
    // An S row is posed in the shot (I-67-Q1), as the storyboard's rail
    // already read it.
    poseCentre: rowPoseSpace(
      session.repository.requireProject(),
      layer,
      standing: session.activeCutId,
    ),
    hasPlugin: session.fxPlugins.has,
  );
}

/// The CAMERA row's lanes: its cut's camera track, the member lanes alone.
List<PropertyLaneRow> _cameraLanes(EditorSessionManager session, Layer row) {
  // The cut that holds the row — the active one wherever the timeline
  // draws it, but the storyboard's camera row twirls any cut's camera, a
  // gap's included (I-73 ④ⓔ). ↩️It read the active cut, required: in a gap
  // the storyboard's twirl-all threw here.
  final project = session.repository.requireProject();
  final cutId = cutWritingRow(project, row.id, standing: session.activeCutId);
  if (cutId == null) {
    return const [];
  }
  final cut = requireCut(project, cutId);
  if (cut.id != session.activeCutId) {
    return cameraPropertyLanes(row, cut.camera.track, canvasSize: cut.canvasSize);
  }
  // ㉙ 유저 2026-08-12: 「카메라는 트랜스폼 헤더나 카메라나 똑같은 유니언의
  // 그룹이란 느낌인데, 중복이니까 카메라레이어는 트랜스폼헤더 삭제하자.
  // 펼치면 포지션/스케일/로테이션만 남도록.」
  //
  // ★The camera row IS the transform group. Its own band already draws
  // the member keys' union — the entire job a Transform header does for
  // every other row — so a header on top of it said the same noun twice
  // and cost a twirl to reach lanes the row was already summarising.
  //
  // The camera rides the cut's camera track rather than its own layer track,
  // and it goes through [EditorSessionManager.activeCutCameraTrack] rather
  // than the cut directly, so a lane-move drag in flight previews here.
  // Every other row gets that for free — the row's preview gate hands the
  // lane list a previewed LAYER — but a camera row's lanes are not built
  // from its Layer at all.
  //
  // 🚨B4-② (2026-08-17): NEVER `cut.camera.track` directly. That is the
  // preview-aware channel every other row gets for free from its previewed
  // Layer — reading the cut here is exactly why camera member lanes sat
  // still while every other transform lane followed its drag live.
  final cameraTrack = session.camera.activeCutCameraTrack ?? cut.camera.track;
  return cameraPropertyLanes(row, cameraTrack, canvasSize: cut.canvasSize);
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
      session.camera.activeCutCameraTrack ?? session.activeCutOrNull?.camera.track;
  if (track == null) {
    return null;
  }
  return cameraUnionHeader(
    track,
    defById: session.camera.cameraInstructionSet.defById,
  );
}

/// The lane the pin [key] names (I-89 ③, a `laneGroupKey`) among the
/// session's rows, as a header graph draws it ([laneGraphLineAmong]).
///
/// Read as a drag in flight shows its row — the one substitution every drag
/// makes ([timelineDragPreviewLayerFor]) — so a pin follows a handle pulled
/// on it, as its own row does.
LaneGraphLine? timelineLaneGraphLine(
  String key, {
  required EditorSessionManager session,
}) => laneGraphLineAmong(
  key,
  rows: session.layers.map(
    (row) =>
        timelineDragPreviewLayerFor(session.dragPreview.value, row.id) ?? row,
  ),
  lanesOf: (layer, expandedGroupKeys) => timelineLanesForLayer(
    layer: layer,
    session: session,
    expandedGroupKeys: expandedGroupKeys,
  ),
);
