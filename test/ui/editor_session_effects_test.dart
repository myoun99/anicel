import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/transform_track.dart';
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
        case CanvasLayerAdjustmentNode(:final children):
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

  test('an ATTACH row with no cel yet still previews the BASE\'s effects', () {
    // The fallback node (active row, nothing exposed) has to resolve its
    // chain the way the composite entry does — from the FX CARRIER. Reading
    // the row's own would leave the live surface unfiltered until the first
    // cel exists, then snap to filtered.
    session.addEffectToActiveLayer(EffectKind.blur);
    final base = session.activeLayer!;
    session.updateLayerEffects(
      base.id,
      effectsWithLaneValueEdited(
        base.effects,
        laneId: effectLaneId(base.effects.single.id, 'blurX'),
        frameIndex: 0,
        input: '9',
      )!,
    );
    session.addAttachedLayer(AttachedPlacement.above);
    final attached = session.activeLayer!;
    expect(attached.attachedToLayerId, base.id);
    expect(attached.effects, isEmpty, reason: 'the chain lives on the base');

    // Specifically the ACTIVE node — the live surface the next stroke
    // lands in — not just "some node in the stack carries effects".
    List<ResolvedLayerEffect> activeNodeEffects() {
      for (final node in session.editingCanvasStack.nodes) {
        if (node is CanvasActiveLayerNode) {
          return node.effects;
        }
      }
      fail('the attach row with no cel must still get an active node');
    }

    expect(activeNodeEffects().single.parameter('blurX'), 9);
    // …and the BASE's fx switch is what bypasses it.
    session.toggleLayerFx(base.id);
    expect(activeNodeEffects(), isEmpty);
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

  group('the adjustment layer (R6b)', () {
    /// The adjustment scope node in the editing stack, or null.
    CanvasLayerAdjustmentNode? scopeIn(List<CanvasLayerStackNode> nodes) {
      for (final node in nodes) {
        if (node is CanvasLayerAdjustmentNode) {
          return node;
        }
        if (node is CanvasLayerGroupNode) {
          final inner = scopeIn(node.children);
          if (inner != null) {
            return inner;
          }
        }
      }
      return null;
    }

    test('Add Layer creates one, named FX1, above the active row', () {
      final base = session.activeLayer!;
      session.addLayerOfKind(LayerKind.adjustment);
      final created = session.activeLayer!;
      expect(created.kind, LayerKind.adjustment);
      expect(created.name, 'FX1');
      expect(created.effects, isEmpty);
      expect(created.frames, isEmpty);
      final layers = session.requireActiveCut.layers;
      expect(
        layers.indexWhere((layer) => layer.id == created.id),
        greaterThan(layers.indexWhere((layer) => layer.id == base.id)),
        reason: 'above the active row — which is what puts it in front',
      );
      session.undo();
      expect(
        session.requireActiveCut.layers.any(
          (layer) => layer.kind == LayerKind.adjustment,
        ),
        isFalse,
      );
    });

    test('an EMPTY adjustment filters nothing; adding an effect does', () {
      // A default cut's rows start on a BLANK exposure, so give the row
      // below the adjustment an actual cel — a scope with nothing in it is
      // correctly no scope at all.
      session.createDrawingAtCurrentFrame();
      session.addLayerOfKind(LayerKind.adjustment);
      expect(scopeIn(session.editingCanvasStack.nodes), isNull);

      session.addEffectToActiveLayer(EffectKind.brightnessContrast);
      final row = session.activeLayer!;
      session.updateLayerEffects(
        row.id,
        effectsWithLaneValueEdited(
          row.effects,
          laneId: effectLaneId(row.effects.single.id, 'brightness'),
          frameIndex: 0,
          input: '30',
        )!,
      );

      final scope = scopeIn(session.editingCanvasStack.nodes);
      expect(scope, isNotNull);
      expect(scope!.effects.single.parameter('brightness'), 30);
      expect(scope.mix, 1);
      expect(
        scope.children,
        isNotEmpty,
        reason: 'the rows below it are what it filters',
      );
    });

    test('it takes effects but no transform lanes', () {
      session.addLayerOfKind(LayerKind.adjustment);
      final row = session.activeLayer!;
      expect(session.canAddEffectToActiveLayer, isTrue);
      expect(layerKindHasLayerTransform(row.kind), isFalse);
      // …and the coordinator refuses a transform outright — writing one is
      // a programming error, not a silently ignored edit.
      expect(
        () => session.updateLayerTransformTrack(row.id, TransformTrack.empty()),
        throwsStateError,
      );
    });

    test('the row survives a save/load round trip as an adjustment', () {
      session.addLayerOfKind(LayerKind.adjustment);
      session.addEffectToActiveLayer(EffectKind.blur);
      final row = session.activeLayer!;

      final reloaded = EditorSessionManager(
        initialProject: Project.fromJson(
          session.repository.requireProject().toJson(),
        ),
      );
      addTearDown(reloaded.dispose);
      final restored = reloaded.requireActiveCut.layers.firstWhere(
        (layer) => layer.id == row.id,
      );
      expect(restored.kind, LayerKind.adjustment);
      expect(restored.effects.single.kind, EffectKind.blur);
    });
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
