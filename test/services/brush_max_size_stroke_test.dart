import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// Pin for the CSP-parity size ceiling (maxSize 128 → 2000, FieldSlider
/// round): a dab at the FULL ceiling must ride the whole stamp/compose
/// pipeline — tip mask build, tile fan-out, commit — without blowing up,
/// and land geometrically correct ink. Tied to [BrushToolState.maxSize] so
/// any future ceiling change re-proves itself here.
void main() {
  test('a max-size dab commits and paints a correct disc', () {
    const canvasSize = CanvasSize(width: 2200, height: 2200);
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: const CutId('cut'),
        layerId: const LayerId('layer'),
        frameId: const FrameId('frame'),
      ),
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: BrushHistoryPolicy(userUndoLimit: 4, deferredBakeRatio: 0),
    );

    final outcome = coordinator.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1100.5, y: 1100.5),
          color: 0xFF000000,
          size: BrushToolState.maxSize,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );

    expect(outcome, isNotNull);
    expect(outcome!.dirtyTiles.isNotEmpty, isTrue);

    final surface = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    int alphaAt(int x, int y) => surfacePixelRgba(surface, x, y) ?? 0;

    // Radius = maxSize / 2 = 1000 around (1100.5, 1100.5).
    expect(alphaAt(1100, 1100), greaterThan(0), reason: 'center painted');
    expect(
      alphaAt(1100, 150),
      greaterThan(0),
      reason: 'inside the rim (distance ~950)',
    );
    expect(alphaAt(1100, 50), 0, reason: 'outside the rim (distance ~1050)');
    expect(alphaAt(10, 10), 0, reason: 'corner far outside the disc');
  });
}
