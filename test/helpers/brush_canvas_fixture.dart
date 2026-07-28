import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// Temporary Brush canvas fixture used by explicit fixture/test helper paths
/// until the real editor selection supplies Project / Track / Cut / Layer /
/// Frame identity.
///
/// This intentionally does not store drawing payload in Frame models. Drawing
/// state remains in [BrushFrameStore] and [BrushFrameEditSessionStore].
class BrushCanvasFixture {
  const BrushCanvasFixture._();

  static const projectId = ProjectId('brush-workspace-project');
  static const trackId = TrackId('brush-workspace-track');
  static const cutId = CutId('brush-workspace-cut');
  static const layerId = LayerId('brush-workspace-layer');
  static const canvasSize = defaultCutCanvasSize;

  static const frameIds = [
    FrameId('frame-1'),
    FrameId('frame-2'),
    FrameId('frame-3'),
  ];

  static List<BrushFrameKey> createFrameKeys() => frameIds
      .map(
        (frameId) => BrushFrameKey(
          projectId: projectId,
          trackId: trackId,
          cutId: cutId,
          layerId: layerId,
          frameId: frameId,
        ),
      )
      .toList(growable: false);

  static BrushFrameEditingCoordinator createCoordinator({
    List<BrushFrameKey>? frameKeys,
    CanvasSize canvasSize = BrushCanvasFixture.canvasSize,
    BrushHistoryPolicy historyPolicy = const BrushHistoryPolicy(
      userUndoLimit: defaultCutDuration,
      deferredBakeRatio: 0,
    ),
  }) {
    final keys = frameKeys ?? createFrameKeys();
    return BrushFrameEditingCoordinator(
      initialFrameKey: keys.first,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: historyPolicy,
    );
  }
}
