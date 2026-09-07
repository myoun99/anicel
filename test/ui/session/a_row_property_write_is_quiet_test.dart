import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// **A per-layer PROPERTY write is not a structural cut edit.**
///
/// It runs against the active cut, banks one undo step, and then does a
/// BARE notify — quoting the rule stated beside the fx switches: "a switch
/// flip is not a structural cut edit, and refreshing as one threw away the
/// frame-range selection the user keeps while A/B-ing the switch."
///
/// Three verbs wrote that envelope out (the effect chain, the instruction
/// spans, the layer mark). This pins what they must all do, so the one
/// envelope cannot quietly become a refreshing one.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// A range the user is holding while they poke at a row property.
  void holdARange(EditorSessionManager s) {
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: s.requireActiveCut.layers.first.id,
      startIndex: 0,
      endIndexExclusive: 3,
    );
  }

  test('the EFFECT CHAIN write keeps the range and still notifies', () {
    final s = session();
    final layer = s.requireActiveCut.layers.firstWhere(
      (row) => row.kind.hasLayerEffects,
    );
    holdARange(s);
    var notified = 0;
    s.addListener(() => notified += 1);

    s.effectsAndFx.updateLayerEffects(layer.id, [
      LayerEffect.defaults(id: const EffectId('fx-q'), kind: EffectKind.blur),
    ]);

    expect(
      s.layers.firstWhere((row) => row.id == layer.id).effects,
      hasLength(1),
      reason: 'LIVENESS — the write has to have landed',
    );
    expect(notified, greaterThan(0));
    expect(
      s.frameRangeSelection.value,
      isNotNull,
      reason: 'refreshing as a cut command would have cleared it',
    );
  });

  test('the INSTRUCTION span write keeps the range and still notifies', () {
    final s = session();
    final layer = s.requireActiveCut.layers.firstWhere(
      (row) => row.kind == LayerKind.instruction,
    );
    holdARange(s);
    var notified = 0;
    s.addListener(() => notified += 1);

    s.instructionVerbs.updateLayerInstructions(
      layer.id,
      {0: const InstructionEvent(instructionId: 'pan', length: 2)},
    );

    expect(
      s.layers.firstWhere((row) => row.id == layer.id).instructions,
      isNotEmpty,
      reason: 'LIVENESS — the write has to have landed',
    );
    expect(notified, greaterThan(0));
    expect(s.frameRangeSelection.value, isNotNull);
  });

  test('the LAYER MARK write keeps the range and still notifies', () {
    final s = session();
    final layer = s.requireActiveCut.layers.first;
    holdARange(s);
    var notified = 0;
    s.addListener(() => notified += 1);

    s.layerMarks.setLayerMark(layer.id, const LayerMark(process: LayerProcess.layout));

    expect(
      s.layers.firstWhere((row) => row.id == layer.id).mark,
      const LayerMark(process: LayerProcess.layout),
      reason: 'LIVENESS — the write has to have landed',
    );
    expect(notified, greaterThan(0));
    expect(s.frameRangeSelection.value, isNotNull);
  });
}
