import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R8 — the fx switches are ONE persisted family.
///
/// Before this round the row's fx button was a session-only set of layer
/// ids while each effect's switch lived on the model, so the two disagreed
/// about what "bypassed" meant: the button was forgotten by any render
/// route that did not thread the set, and it vanished on reload. Now every
/// switch is model state ([Layer.transformEnabled] plus each
/// [LayerEffect.enabled]) and the label button is a MASTER over them.
void main() {
  EditorSessionManager makeSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// A row with a real transform AND two effects, so the master has more
  /// than one switch to be a master over.
  ({LayerId id, EffectId first, EffectId second}) armRow(
    EditorSessionManager session,
  ) {
    final layerId = session.activeLayer!.id;
    session.updateLayerTransformTrack(
      layerId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 40, y: 20),
        ),
      ),
    );
    session.addEffectToActiveLayer(EffectKind.brightnessContrast);
    session.addEffectToActiveLayer(EffectKind.blur);
    final effects = session.activeLayer!.effects;
    expect(effects, hasLength(2));
    return (id: layerId, first: effects.first.id, second: effects.last.id);
  }

  List<LayerEffect> effectsOf(EditorSessionManager session, LayerId id) =>
      session.requireActiveCut.layers.firstWhere((l) => l.id == id).effects;

  bool transformEnabledOf(EditorSessionManager session, LayerId id) => session
      .requireActiveCut
      .layers
      .firstWhere((l) => l.id == id)
      .transformEnabled;

  group('the master button reads and writes every switch on the row', () {
    test('all on / all off / mixed are the three states', () {
      final session = makeSession();
      final row = armRow(session);

      expect(session.layerFxState(row.id), LayerFxState.on);

      // One effect off is a MIX — the row still does some of its fx.
      session.updateLayerEffects(row.id, [
        for (final effect in effectsOf(session, row.id))
          effect.id == row.first ? effect.copyWith(enabled: false) : effect,
      ]);
      expect(session.layerFxState(row.id), LayerFxState.mixed);
      expect(
        session.isLayerFxEnabled(row.id),
        isTrue,
        reason: 'mixed still applies fx, so the boolean readers say yes',
      );

      // Tapping a MIXED row resolves it one way: everything off.
      session.toggleLayerFx(row.id);
      expect(session.layerFxState(row.id), LayerFxState.off);
      expect(session.isLayerFxEnabled(row.id), isFalse);
      expect(transformEnabledOf(session, row.id), isFalse);
      expect(
        effectsOf(session, row.id).every((effect) => !effect.enabled),
        isTrue,
      );

      // And only a fully-off row turns back ON.
      session.toggleLayerFx(row.id);
      expect(session.layerFxState(row.id), LayerFxState.on);
      expect(transformEnabledOf(session, row.id), isTrue);
      expect(
        effectsOf(session, row.id).every((effect) => effect.enabled),
        isTrue,
      );
    });

    test('the whole row is ONE undo step, and it survives a reload', () {
      final session = makeSession();
      final row = armRow(session);

      session.toggleLayerFx(row.id);
      expect(session.layerFxState(row.id), LayerFxState.off);

      // One command for the transform switch AND both effects.
      session.undo();
      expect(
        session.layerFxState(row.id),
        LayerFxState.on,
        reason: 'a master tap must not take three undos to walk back',
      );

      session.redo();
      expect(session.layerFxState(row.id), LayerFxState.off);

      // Persisted: the switches are in the layer's JSON, which is the
      // whole point of the round (the session set died on reload).
      final saved = session.requireActiveCut.layers.firstWhere(
        (l) => l.id == row.id,
      );
      final reloaded = Layer.fromJson(saved.toJson());
      expect(reloaded.transformEnabled, isFalse);
      expect(reloaded.effects.every((effect) => !effect.enabled), isTrue);
    });

    test('an OLD file with no switch keys reads as fully applied', () {
      final json = Layer(
        id: const LayerId('legacy'),
        name: 'LEGACY',
        frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
        timeline: const {},
      ).toJson();

      expect(
        json.containsKey('transformEnabled'),
        isFalse,
        reason: 'the default is omitted, so old and new files agree',
      );
      expect(Layer.fromJson(json).transformEnabled, isTrue);
    });
  });

  group('the group headers own their own switches', () {
    test('the TRANSFORM header switch moves only the transform', () {
      final session = makeSession();
      final row = armRow(session);

      session.toggleLayerTransformFx(row.id);
      expect(transformEnabledOf(session, row.id), isFalse);
      expect(
        effectsOf(session, row.id).every((effect) => effect.enabled),
        isTrue,
        reason: 'a per-group switch must not sweep the row',
      );
      expect(session.layerFxState(row.id), LayerFxState.mixed);

      // Bypassing the transform bypasses the POSE, like the master did.
      expect(session.layerCanvasPoseSample(row.id), isNull);

      session.toggleLayerTransformFx(row.id);
      expect(transformEnabledOf(session, row.id), isTrue);
      expect(session.layerCanvasPoseSample(row.id), isNotNull);
      expect(session.layerFxState(row.id), LayerFxState.on);
    });

    test('updateLayerTransformEnabled is idempotent (no empty undo steps)', () {
      final session = makeSession();
      final row = armRow(session);

      session.toggleLayerTransformFx(row.id);
      expect(transformEnabledOf(session, row.id), isFalse);

      // Writing the value it already has must record NOTHING, or the undo
      // stack grows a step that walks nowhere.
      session.updateLayerTransformEnabled(row.id, enabled: false);
      session.undo();
      expect(
        transformEnabledOf(session, row.id),
        isTrue,
        reason: 'one undo walks back the last REAL edit',
      );
    });
  });

  group('rows whose switch family is not the usual one', () {
    test('the CAMERA row has no effects, so the master is its transform', () {
      final session = makeSession();
      final cameraId = session.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;

      expect(layerKindHasLayerEffects(LayerKind.camera), isFalse);
      expect(layerKindHasTransformFxSwitch(LayerKind.camera), isTrue);

      expect(session.layerFxState(cameraId), LayerFxState.on);
      session.toggleLayerFx(cameraId);
      expect(
        session.layerFxState(cameraId),
        LayerFxState.off,
        reason:
            'the camera row is not skipped by the master (it carries '
            'the switch that bypasses the cut camera)',
      );
      expect(transformEnabledOf(session, cameraId), isFalse);
    });

    test('an ADJUSTMENT row reads its effects ALONE — never phantom-mixed', () {
      expect(layerKindHasTransformFxSwitch(LayerKind.adjustment), isFalse);
      expect(
        createAdjustmentLayer(
          id: const LayerId('adj'),
          name: 'ADJ',
        ).transformEnabled,
        isTrue,
        reason: 'the flag is still at its default; it just means nothing here',
      );

      final session = makeSession();
      session.createDrawingAtCurrentFrame();
      session.addLayerOfKind(LayerKind.adjustment);
      final adjId = session.activeLayer!.id;
      expect(session.activeLayer!.kind, LayerKind.adjustment);

      expect(
        session.layerFxState(adjId),
        LayerFxState.on,
        reason: 'no effects yet = nothing bypassed',
      );

      session.addEffectToActiveLayer(EffectKind.brightnessContrast);
      session.toggleLayerFx(adjId);
      expect(
        session.layerFxState(adjId),
        LayerFxState.off,
        reason:
            'its ONE effect is off, so the row is off — a meaningless '
            'transformEnabled: true must not read as mixed',
      );
    });

    test('the bulk sweep writes the model, not a view-state set', () {
      final session = makeSession();
      final row = armRow(session);

      session.setAllLayersFxBypassed(true);
      expect(transformEnabledOf(session, row.id), isFalse);
      expect(
        effectsOf(session, row.id).every((effect) => !effect.enabled),
        isTrue,
      );
      expect(
        session.layers.every(
          (layer) => session.layerFxState(layer.id) != LayerFxState.mixed,
        ),
        isTrue,
        reason: 'a sweep leaves no row half-resolved',
      );

      session.undo();
      expect(
        transformEnabledOf(session, row.id),
        isTrue,
        reason: 'the sweep is one undo step for the whole timeline',
      );
    });
  });
}
