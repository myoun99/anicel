import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_section_defaults.dart';
import '../../core/timeline/timeline_defaults.dart';
import 'default_layer_helpers.dart';
import 'run_id_mint.dart' show mintFrameId;

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

/// A cut with the fixtures every cut carries and NO drawing row — what a
/// NEW cut is.
///
/// 🗣️F-211 (유저 2026-09-28): 「새 컷 생성의 초기값은 프레임도 없고 나아가서
/// **A라는 기본 레이어도 존재안하도록**」. ↩️A new cut was the default cut:
/// it arrived with a blank layer A, the row a new PROJECT starts with.
Cut createBareCut({
  required CutId cutId,
  required String name,
  CanvasSize canvasSize = defaultCutCanvasSize,
}) {
  return Cut(
    id: cutId,
    name: name,
    layers: [
      // The timesheet fixture row every cut carries: DIR 1. (The SE rows
      // S1·S2 are TRACK fixtures — see createDefaultTrack.)
      createInstructionLayer(cutId: cutId),
      // Last = bottom timeline row.
      createCameraLayer(cutId: cutId),
    ],
    duration: defaultCutDuration,
    canvasSize: canvasSize,
  );
}

/// The bare cut ([createBareCut]) with a blank layer A over its fixtures —
/// the cut a new PROJECT starts with, and the base an importer replaces the
/// drawing row of ([importedCut]).
///
/// Layer A is the row Add Layer bears in that bare cut ([bornRowOfKind]) —
/// its name and its kind's label (F-76) — which is what the first row of a
/// NEW cut is too, now that the user makes it (F-211). ↩️It was a birth
/// written out here a second time.
Cut createDefaultCut({
  required CutId cutId,
  required String name,
  required LayerId layerId,
  CanvasSize canvasSize = defaultCutCanvasSize,
}) {
  final bare = createBareCut(cutId: cutId, name: name, canvasSize: canvasSize);
  return bare.copyWith(
    layers: [
      // First, so the drawing layer is the default active layer (selection
      // falls back to layers.first).
      bornRowOfKind(
        LayerKind.animation,
        layerId: layerId,
        // Add Layer's own argument; an animation row never asks for it.
        coveringFrameId: () => mintFrameId(layerId),
        cut: bare,
      ),
      ...bare.layers,
    ],
  );
}

/// A default cut with [layers] standing in for its drawing row, keeping
/// the fixtures the default brought.
///
/// ⛔EVERY IMPORTER BUILDS ITS CUT THIS WAY. The default cut arrives with
/// an instruction row and a camera row as well as a blank drawing layer,
/// and an importer replaces only the drawing: dropping the fixtures would
/// give the imported cut no camera, which nothing downstream expects.
///
/// ⚠️AN EMPTY [layers] KEEPS THE DEFAULT'S OWN — an import that parsed no
/// drawings still has to be a usable cut, not a cut with no rows at all.
Cut importedCut({
  required Cut defaultCut,
  required List<Layer> layers,
  required int duration,
}) {
  final fixtureLayers = [
    for (final layer in defaultCut.layers)
      if (layer.kind != LayerKind.animation) layer,
  ];
  return defaultCut.copyWith(
    duration: duration,
    layers: layers.isEmpty ? defaultCut.layers : [...layers, ...fixtureLayers],
  );
}
