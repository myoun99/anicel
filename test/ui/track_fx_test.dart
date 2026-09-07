import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/services/composite_effect_paint.dart'    show        CompositeEffectPaint,        blurSigmaPerRadius,        resolveCompositeEffectPaint,        resolveCompositeEffectPlan;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart' show effectGroupLaneId;
import 'package:anicel/src/ui/track_effect_paint_policy.dart';

/// The V row's EFFECT CHAIN: a layer's fx one level up, filtering the whole
/// composited cut (user 2026-08-08). Track data on the GLOBAL axis, like the
/// pose and the fade beside it.

const _track = TrackId('track-1');
const _cut = CutId('cut-1');

LayerEffect _brightness({double value = 0.5, Map<int, double>? keys}) {
  return LayerEffect(
    id: const EffectId('fx-1'),
    kind: EffectKind.brightnessContrast,
    parameters: {
      'brightness': EffectParameter(
        value: value,
        track: keys == null
            ? null
            : PropertyTrack<double>(
                keys: {
                  for (final entry in keys.entries)
                    entry.key: PropertyKey<double>(entry.value),
                },
              ),
      ),
    },
  );
}

LayerEffect _blur({double radius = 9}) => LayerEffect(
  id: const EffectId('fx-blur'),
  kind: EffectKind.blur,
  parameters: {
    'blurX': EffectParameter(value: radius),
    'blurY': EffectParameter(value: radius),
  },
);

/// A colour key on the V row — the shape that used to make the policy throw.
LayerEffect _deleteWhite() => LayerEffect(
  id: const EffectId('fx-key'),
  kind: EffectKind.deleteColor,
  parameters: {
    'keyRed': EffectParameter(value: 255),
    'keyGreen': EffectParameter(value: 255),
    'keyBlue': EffectParameter(value: 255),
    'tolerance': EffectParameter(value: 0),
    'amount': EffectParameter(value: 100),
  },
);

Project _project({List<LayerEffect> effects = const []}) => Project(
  id: const ProjectId('project-1'),
  name: 'Project',
  createdAt: DateTime.utc(2024),
  tracks: [
    Track(
      id: _track,
      name: 'Video',
      effects: effects,
      cuts: [
        Cut(
          id: _cut,
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          layers: [Layer(id: const LayerId('layer-1'), name: 'A', frames: const [])],
        ),
      ],
    ),
  ],
);

void main() {
  group('the model', () {
    test('carries the chain through JSON, and writes nothing when empty', () {
      final bare = Track(id: _track, name: 'V', cuts: const []);
      expect(bare.effects, isEmpty);
      expect(bare.toJson().containsKey('effects'), isFalse);

      final withFx = bare.copyWith(effects: [_brightness()]);
      final json = withFx.toJson();
      expect(json['effects'], hasLength(1));
      expect(Track.fromJson(json).effects, withFx.effects);
      // A value, so an unchanged write is a no-op for dirty tracking. (The
      // parse also ENSURES the S1/S2 fixtures, so the comparison drops them.)
      expect(Track.fromJson(json).copyWith(seLayers: const []), withFx);
      expect(withFx == bare, isFalse);
    });
  });

  group('the chain as paint', () {
    // ⛔THE POLICY HANDS BACK A CHAIN NOW, not a paint — a colour key has no
    // paint form, and resolving one here is what used to throw. These tests
    // still ask about the PAINT, so they resolve it themselves, one step
    // further down than they used to.
    CompositeEffectPaint paintOf(
      List<LayerEffect> effects,
      int frame, {
      bool enabled = true,
    }) => resolveCompositeEffectPaint(
      trackEffectsAt(effects, frame, enabled: enabled),
    );

    test('empty is the zero-cost path, and so is a bypassed row', () {
      expect(paintOf(const [], 0).isEmpty, isTrue);
      expect(
        paintOf([_brightness()], 0, enabled: false).isEmpty,
        isTrue,
        reason: 'the V row fx master bypasses the chain like the pose',
      );
      expect(paintOf([_brightness()], 0).isNotEmpty, isTrue);
    });

    test('a colour effect resolves INLINE, a blur takes the offscreen', () {
      final colour = paintOf([_brightness()], 0);
      expect(colour.colorFilter, isNotNull);
      expect(colour.imageFilter, isNull);
      expect(colour.outsetPixels, 0);

      final blurred = paintOf([_blur(radius: 9)], 0);
      expect(blurred.colorFilter, isNull);
      expect(blurred.imageFilter, isNotNull);
      expect(blurred.outsetPixels, 9);
    });

    test('it samples at the GLOBAL frame — the axis the keys live on', () {
      final animated = [
        _brightness(keys: {0: 0.0, 10: 0.9}),
      ];
      // Frame 0 resolves to the no-op value, so there is nothing to paint;
      // frame 10 does.
      expect(paintOf(animated, 0).isEmpty, isTrue);
      expect(paintOf(animated, 10).isNotEmpty, isTrue);
      // And the two ends differ, which is what makes it animated at all.
      expect(paintOf(animated, 10) == paintOf(animated, 5), isFalse);
    });

    test('an effect switched OFF drops out while its keys stay', () {
      final off = [_brightness().copyWith(enabled: false)];
      expect(paintOf(off, 0).isEmpty, isTrue);
      expect(off.single.parameterOf('brightness').value, 0.5);
    });

    test('the CHAIN is a value, so a static grade is not a repaint', () {
      // ⛔ASKED OF THE CHAIN, because the chain is what the painter now
      // diffs (`listEquals`). Asking the paint would leave the field the
      // painter actually compares untested.
      final effects = [_brightness()];
      expect(
        listEquals(trackEffectsAt(effects, 3), trackEffectsAt(effects, 4)),
        isTrue,
      );
      expect(paintOf(effects, 3), paintOf(effects, 4));
    });

    test('a COLOUR KEY resolves to a plan instead of throwing', () {
      // 🚨★★★THE BUG THIS SHAPE EXISTS FOR. The policy used to return a
      // resolved paint, and `resolveCompositeEffectPaint` REFUSES a
      // source-pixel effect — by assert. So a track chain with a colour key
      // in it threw, exactly as the live layer's did until #1314. It was
      // unreachable only because nothing calls `addEffectToTrack`; "no
      // caller" is not a design, and the next round to add that menu would
      // have shipped an assert.
      final chain = trackEffectsAt([_deleteWhite()], 0);
      expect(chain, hasLength(1), reason: 'fixture: the key survived');

      final plan = resolveCompositeEffectPlan(chain);
      expect(
        plan.preSteps, hasLength(1),
        reason: 'the key rides its own raster, like a group or a layer image',
      );
      expect(plan.preSteps.single.key, isNotNull);
      expect(
        plan.finalPaint.isEmpty,
        isTrue,
        reason: 'nothing follows the key, so the final draw carries nothing',
      );
    });

    test('a key UNDER a painted effect keeps both, in that order', () {
      final plan = resolveCompositeEffectPlan(
        trackEffectsAt([_brightness(), _deleteWhite()], 0),
      );
      expect(plan.preSteps, hasLength(2));
      expect(
        plan.preSteps.first.key,
        isNull,
        reason: 'the darken runs first, with no key of its own',
      );
      expect(plan.preSteps.first.then, hasLength(1));
      expect(
        plan.preSteps.last.key,
        isNotNull,
        reason: 'and the key sees what the darken made — order is free here '
            'too, the same law the layer rows got in #1312',
      );
    });
  });

  group('the command', () {
    ({ProjectRepository repository, HistoryManager history, CutCommandCoordinator coordinator})
    fixture(Project project) {
      final repository = ProjectRepository(initialProject: project);
      final history = HistoryManager();
      return (
        repository: repository,
        history: history,
        coordinator: CutCommandCoordinator(
          repository: repository,
          editingSession: EditingSessionState(activeCutId: _cut),
          historyManager: history,
        ),
      );
    }

    List<LayerEffect> effectsOf(ProjectRepository repository) =>
        repository.requireProject().tracks.single.effects;

    test('writes the chain and undoes it', () {
      final f = fixture(_project());
      f.coordinator.updateTrackEffects(
        trackId: _track,
        effects: [_brightness()],
      );
      expect(effectsOf(f.repository), hasLength(1));
      expect(f.history.undoCount, 1);

      f.history.undo();
      expect(effectsOf(f.repository), isEmpty);
    });

    test('an unchanged chain is not an undo entry', () {
      final effects = [_brightness()];
      final f = fixture(_project(effects: effects));
      f.coordinator.updateTrackEffects(trackId: _track, effects: effects);
      expect(f.history.undoCount, 0);
    });
  });

  group('the session verbs', () {
    EditorSessionManager session({List<LayerEffect> effects = const []}) =>
        EditorSessionManager(initialProject: _project(effects: effects));

    List<LayerEffect> chain(EditorSessionManager s) =>
        s.repository.requireProject().tracks.single.effects;

    test('add lands an effect on the V row, and the render routes see it '
        'through the cut', () {
      final s = session();
      expect(s.effectsAndFx.trackEffectsForCut(_cut), isEmpty);

      s.effectsAndFx.addEffectToTrack(_track, EffectKind.blur);

      expect(chain(s), hasLength(1));
      expect(chain(s).single.kind, EffectKind.blur);
      expect(s.effectsAndFx.trackEffectsForCut(_cut), chain(s));
      // The chain's id hangs off the TRACK, since that is what carries it.
      expect(chain(s).single.id.value, startsWith('fx-${_track.value}-'));

      s.undo();
      expect(chain(s), isEmpty);
    });

    test('remove and the per-effect bypass', () {
      final s = session(effects: [_brightness()]);
      const id = EffectId('fx-1');

      s.effectsAndFx.toggleTrackEffectEnabled(_track, id);
      expect(chain(s).single.enabled, isFalse);
      // Bypassed, so the cut's picture is unfiltered — the keys stay.
      expect(
        resolveCompositeEffectPaint(trackEffectsAt(chain(s), 0)).isEmpty,
        isTrue,
      );

      s.effectsAndFx.toggleTrackEffectEnabled(_track, id);
      expect(chain(s).single.enabled, isTrue);

      s.effectsAndFx.removeEffectFromTrack(_track, id);
      expect(chain(s), isEmpty);
      s.undo();
      expect(chain(s), hasLength(1));
    });

    test('the group RESET puts the chain back to its defaults, once', () {
      final s = session(effects: [_brightness(value: 0.5)]);
      final laneId = effectGroupLaneId(const EffectId('fx-1'));

      expect(s.effectsAndFx.resetTrackEffectGroup(_track, laneId), isTrue);
      expect(chain(s).single.parameterOf('brightness').value, 0);
      expect(
        s.effectsAndFx.resetTrackEffectGroup(_track, laneId),
        isFalse,
        reason: 'a chain already at its defaults changes nothing, so there '
            'is nothing to bank',
      );

      s.undo();
      expect(chain(s).single.parameterOf('brightness').value, 0.5);
    });

    test('an unknown track is a no-op, not a crash', () {
      final s = session();
      const missing = TrackId('nope');
      s.effectsAndFx.addEffectToTrack(missing, EffectKind.blur);
      s.effectsAndFx.removeEffectFromTrack(missing, const EffectId('fx-1'));
      s.effectsAndFx.toggleTrackEffectEnabled(missing, const EffectId('fx-1'));
      expect(
        s.effectsAndFx.resetTrackEffectGroup(
          missing,
          effectGroupLaneId(const EffectId('fx-1')),
        ),
        isFalse,
      );
      expect(chain(s), isEmpty);
    });
  });

  test('the blur sigma follows the radius convention the layers use', () {
    // Same translation as a layer's blur (one resolver, one painter): the
    // V row must not invent a second meaning for a radius.
    final paint = ui.Paint();
    resolveCompositeEffectPaint(
      trackEffectsAt([_blur(radius: 6)], 0),
    ).applyTo(paint);
    expect(paint.imageFilter, isNotNull);
    expect(
      paint.imageFilter.toString(),
      contains((6 * blurSigmaPerRadius).toString()),
    );
  });
}
