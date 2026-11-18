import 'package:flutter/foundation.dart' show VoidCallback;

import '../../models/layer.dart';
import '../../models/track_id.dart';
import '../editor_session_manager.dart';
import 'property_lane_model.dart' show LaneGroupPress, PropertyLaneRow;

/// RESET in [layer]'s group header [lane] as the rail draws it
/// ([LaneGroupPress]), as `rasterizeLaneGroupOf` draws its RASTERIZE: its
/// press out where it would change nothing — 🗣️F-583 (유저 2026-11-11)
/// 「리셋버튼도 값 안바뀌었으면 동일하게 통일해서 비활성화」.
({VoidCallback? press}) resetLaneGroupOf(
  EditorSessionManager session,
  Layer layer,
  PropertyLaneRow lane,
) => (
  press: session.laneVerbs.resetsLaneGroup(layer.id, lane.laneId)
      ? () => session.laneVerbs.resetLaneGroup(layer.id, lane.laneId)
      : null,
);

/// RESET in a V track's effect group header [headerLaneId], as
/// [resetLaneGroupOf] is a layer's.
({VoidCallback? press}) resetTrackEffectGroupOf(
  EditorSessionManager session,
  TrackId trackId,
  String headerLaneId,
) => (
  press: session.effectsAndFx.resetsTrackEffectGroup(trackId, headerLaneId)
      ? () => session.effectsAndFx.resetTrackEffectGroup(trackId, headerLaneId)
      : null,
);
