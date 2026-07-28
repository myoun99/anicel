import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';

void main() {
  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  test('keeps frame edit sessions isolated by BrushFrameKey', () {
    final store = BrushFrameEditSessionStore(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: 4,
    );
    final frameA = key('frame-a');
    final frameB = key('frame-b');

    final sessionA = store.getOrCreate(frameA);
    final updatedA = sessionA.copyWith(
      canvasState: sessionA.canvasState.clearLastEdit(),
    );
    store.update(frameA, updatedA);

    final sessionB = store.getOrCreate(frameB);

    expect(store.getOrCreate(frameA), same(updatedA));
    expect(sessionB, isNot(same(updatedA)));
    expect(store.sessionOrNull(frameB), same(sessionB));
  });
}
