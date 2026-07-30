import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

/// The R6 effect chain through the SESSION — the wiring the timeline host
/// drives: add, edit, undo, and the editing canvas reading it back.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  List<ResolvedLayerEffect> stackEffectsOf(List<CanvasLayerStackNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case CanvasActiveLayerNode(:final effects):
          return effects;
        case CanvasLayerImageNode(:final request):
          if (request.effects.isNotEmpty) {
            return request.effects;
          }
        case CanvasLayerGroupNode(:final children):
          final inner = stackEffectsOf(children);
          if (inner.isNotEmpty) {
            return inner;
          }
      }
    }
    return const [];
  }

  test('adding an effect is one undo step and changes no pixel yet', () {
    final layerId = session.activeLayer!.id;
    expect(session.canAddEffectToActiveLayer, isTrue);

    session.addEffectToActiveLayer(EffectKind.blur);
    final effect = session.activeLayer!.effects.single;
    expect(effect.kind, EffectKind.blur);
    expect(
      resolveLayerEffectsAt(effects: [effect], frameIndex: 0),
      isEmpty,
      reason: 'a fresh effect is all defaults — nothing to paint',
    );

    session.undo();
    expect(session.activeLayer!.effects, isEmpty);
    session.redo();
    expect(session.activeLayer!.effects.single.id, effect.id);
    expect(session.activeLayer!.id, layerId);
  });

  test('two effects added in a row get distinct ids (the lane address)', () {
    session.addEffectToActiveLayer(EffectKind.blur);
    session.addEffectToActiveLayer(EffectKind.blur);
    final effects = session.activeLayer!.effects;
    expect(effects, hasLength(2));
    expect(effects.first.id, isNot(effects.last.id));
    expect(
      effectLaneId(effects.first.id, 'blurX'),
      isNot(effectLaneId(effects.last.id, 'blurX')),
    );
  });

  test('a lane value edit reaches the composite and undoes in one step', () {
    session.addEffectToActiveLayer(EffectKind.blur);
    final layer = session.activeLayer!;
    final laneId = effectLaneId(layer.effects.single.id, 'blurX');

    final edited = effectsWithLaneValueEdited(
      layer.effects,
      laneId: laneId,
      frameIndex: 0,
      input: '9',
    )!;
    session.updateLayerEffects(layer.id, edited, description: 'Set Blur Width');

    expect(session.activeLayer!.effects.single.parameterOf('blurX').value, 9);
    expect(
      stackEffectsOf(
        session.editingCanvasStack.nodes,
      ).single.parameter('blurX'),
      9,
      reason: 'the editing canvas reads the same resolver the routes do',
    );

    session.undo();
    expect(session.activeLayer!.effects.single.parameterOf('blurX').value, 0);
    expect(stackEffectsOf(session.editingCanvasStack.nodes), isEmpty);
  });

  test('the fx switch bypasses the chain on the editing canvas too', () {
    session.addEffectToActiveLayer(EffectKind.blur);
    final layer = session.activeLayer!;
    session.updateLayerEffects(
      layer.id,
      effectsWithLaneValueEdited(
        layer.effects,
        laneId: effectLaneId(layer.effects.single.id, 'blurX'),
        frameIndex: 0,
        input: '9',
      )!,
    );
    expect(stackEffectsOf(session.editingCanvasStack.nodes), isNotEmpty);

    session.toggleLayerFx(layer.id);
    expect(
      stackEffectsOf(session.editingCanvasStack.nodes),
      isEmpty,
      reason: 'the fx switch is one switch for every kind of FX',
    );
  });

  test('removing an effect drops its keys, and undo brings both back', () {
    session.addEffectToActiveLayer(EffectKind.hueSaturation);
    final layer = session.activeLayer!;
    final effectId = layer.effects.single.id;
    session.updateLayerEffects(
      layer.id,
      effectsWithLaneKeyToggled(
        effectsWithLaneValueEdited(
          layer.effects,
          laneId: effectLaneId(effectId, 'hue'),
          frameIndex: 0,
          input: '40',
        )!,
        laneId: effectLaneId(effectId, 'hue'),
        frameIndex: 3,
      )!,
    );
    expect(
      session.activeLayer!.effects.single.parameterOf('hue').isAnimated,
      isTrue,
    );

    session.removeEffectFromActiveLayer(effectId);
    expect(session.activeLayer!.effects, isEmpty);
    session.undo();
    final restored = session.activeLayer!.effects.single;
    expect(restored.parameterOf('hue').track.keyAt(3), isNotNull);
    expect(restored.parameterOf('hue').value, 40);
  });

  test('the CAMERA row takes no effect chain', () {
    final camera = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    session.selectLayer(camera.id);
    expect(session.canAddEffectToActiveLayer, isFalse);
    session.addEffectToActiveLayer(EffectKind.blur);
    expect(
      session.requireActiveCut.layers
          .firstWhere((layer) => layer.id == camera.id)
          .effects,
      isEmpty,
    );
  });

  test('a lane RANGE move shifts effect keys as one rigid group', () {
    session.addEffectToActiveLayer(EffectKind.blur);
    final layer = session.activeLayer!;
    final effectId = layer.effects.single.id;
    final laneId = effectLaneId(effectId, 'blurX');
    var effects = layer.effects;
    for (final frame in [2, 3]) {
      effects = effectsWithLaneKeyToggled(
        effects,
        laneId: laneId,
        frameIndex: frame,
      )!;
    }
    session.updateLayerEffects(layer.id, effects);

    session.updateLaneRangeSelectionDrag(
      layerId: layer.id,
      laneId: laneId,
      anchorIndex: 2,
      headIndex: 3,
    );
    expect(session.beginLaneRangeMoveDrag(), isTrue);
    session.updateLaneRangeMoveDrag(frameDelta: 5);
    session.endLaneRangeMoveDrag();

    expect(
      session.activeLayer!.effects.single
          .parameterOf('blurX')
          .track
          .keys
          .keys
          .toList(),
      [7, 8],
    );
    session.undo();
    expect(
      session.activeLayer!.effects.single
          .parameterOf('blurX')
          .track
          .keys
          .keys
          .toList(),
      [2, 3],
    );
  });

  test('saving and reloading the project keeps the chain identical', () {
    session.addEffectToActiveLayer(EffectKind.brightnessContrast);
    final layer = session.activeLayer!;
    session.updateLayerEffects(
      layer.id,
      effectsWithLaneValueEdited(
        layer.effects,
        laneId: effectLaneId(layer.effects.single.id, 'brightness'),
        frameIndex: 0,
        input: '25',
      )!,
    );
    final before = session.activeLayer!.effects;

    final json = session.repository.requireProject().toJson();
    final reloaded = EditorSessionManager(
      initialProject: Project.fromJson(json),
    );
    addTearDown(reloaded.dispose);
    expect(
      reloaded.requireActiveCut.layers
          .firstWhere((candidate) => candidate.id == layer.id)
          .effects,
      before,
    );
  });
}
