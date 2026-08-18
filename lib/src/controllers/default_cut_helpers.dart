import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/layer_section_defaults.dart';
import '../core/timeline/timeline_defaults.dart';
import 'default_layer_helpers.dart';

const defaultCutCanvasSize = CanvasSize(width: 2340, height: 1654);
const defaultCutDuration = defaultCutDurationFrames;

/// The camera layer id derived from its cut: exactly one per cut, so the cut
/// id keys it uniquely.
LayerId cameraLayerIdForCut(CutId cutId) => LayerId('${cutId.value}-camera');

/// The cut's camera timeline row. It carries no drawing frames; its cells
/// reflect the cut's camera keyframes and selecting it switches the canvas
/// into camera manipulation mode.
Layer createCameraLayer({required CutId cutId}) {
  return Layer(
    id: cameraLayerIdForCut(cutId),
    name: 'Camera',
    frames: const [],
    timeline: const {},
    kind: LayerKind.camera,
  );
}

Cut createDefaultCut({
  required CutId cutId,
  required String name,
  required LayerId layerId,
  CanvasSize canvasSize = defaultCutCanvasSize,
}) {
  return Cut(
    id: cutId,
    name: name,
    layers: [
      createDefaultAnimationLayer(
        layerId: layerId,
        cut: Cut(
          id: cutId,
          name: name,
          layers: const [],
          duration: defaultCutDuration,
          canvasSize: canvasSize,
        ),
      ),
      // The timesheet fixture row every cut carries: DIR 1. (The SE rows
      // S1·S2 are TRACK fixtures — see createDefaultTrack.)
      createInstructionLayer(cutId: cutId),
      // Last = bottom timeline row, and keeps the drawing layer as the
      // default active layer (selection falls back to layers.first).
      createCameraLayer(cutId: cutId),
    ],
    duration: defaultCutDuration,
    canvasSize: canvasSize,
  );
}
