import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/effects_and_fx.dart'
    show ActiveRowChain;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;

/// An S row wears its FX where it lives — on the TRACK — and every cut can
/// work them (se-row-fx-write-path).
///
/// 🗣️F-102 (유저 2026-09-15): 「글로벌트랙은 fx든뭐던 로컬에선 글로벌을
/// 투영해서 보여주도록? 물론 로컬에서도 조작은 가능하지만」.
///
/// ↩️An S row could not take an effect at all, and a file that already gave
/// it one crashed the first lane edit: the FX command looked the row up in
/// the CUT, where a track-owned row does not live. The reason the row was
/// fenced off (R6a, 2026-07-30: 「its display clone strips FX」) stopped
/// being true when the clone learned to project the track's chain.
void main() {
  late EditorSessionManager session;
  late LayerId se;
  late int cut2Start;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    se = session.activeTrack.seLayers.first.id;
    session.cutVerbs.createCut();
    cut2Start = session.activeCutGlobalStartFrame;
    expect(cut2Start, greaterThan(0), reason: 'fixture: cut 2 starts later');
    session.selectLayer(se);
    expect(session.activeLayer?.id, se, reason: 'fixture: standing on S1');
  });
  tearDown(() => session.dispose());

  Layer seRow() =>
      session.activeTrack.seLayers.firstWhere((layer) => layer.id == se);

  test('an S row takes an effect, and the TRACK\'s row holds it', () {
    expect(
      session.effectsAndFx.canAddEffectToActiveLayer(EffectKind.equalizer),
      isTrue,
    );

    session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);

    expect([for (final e in seRow().effects) e.kind], [EffectKind.equalizer]);
  });

  test('keying its parameter from cut 2 keys the row at the GLOBAL frame, '
      'one undo', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);
    final effect = seRow().effects.single;

    session.laneVerbs.toggleLaneKeyAt(
      se,
      effectLaneId(effect.id, 'lowGain'),
      3,
      frameIsGlobal: false,
      description: 'Equalizer keyframe',
    );

    expect(
      seRow().effects.single.parameters['lowGain']!.track.keys.keys.toList(),
      [cut2Start + 3],
    );
    session.undo();
    expect(
      seRow().effects.single.parameters['lowGain']!.track.keys,
      isEmpty,
      reason: 'one undo takes the key back',
    );
  });

  test('an effect added from cut 2 keeps the keys the row already holds on '
      'their GLOBAL frames — it is built from the row, not its projection', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);
    final first = seRow().effects.single;
    session.laneVerbs.toggleLaneKeyAt(
      se,
      effectLaneId(first.id, 'lowGain'),
      2,
      frameIsGlobal: false,
      description: 'Equalizer keyframe',
    );

    session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);

    final effects = seRow().effects;
    expect([for (final e in effects) e.kind], [
      EffectKind.equalizer,
      EffectKind.equalizer,
    ]);
    expect(
      effects.first.parameters['lowGain']!.track.keys.keys.toList(),
      [cut2Start + 2],
    );
  });

  test('the row\'s master FX switch bypasses its chain too', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);

    session.effectsAndFx.toggleLayerFx(se);

    expect(seRow().effects.single.enabled, isFalse);
    expect(seRow().transformEnabled, isFalse);
  });

  // 🗣️audio-fx-grows-like-the-pros Q3 (유저 2026-11-17): 「s행은 그냥
  // 영상fx안붙게? 오디오fx만 기본으로」 — a sound's filter on a row that plays
  // sound, a picture's on any other, by every road an effect is added.
  // ↩️The S row took every kind from F-102 on, its picture fx filtering
  // the name tag alone (F-387).
  group('🎯a row takes the effects of what it plays', () {
    final pictureKinds = [
      for (final kind in effectKindsAddedAlone)
        if (!kind.filtersSound) kind,
    ];

    test('an S row refuses every picture kind and the plugins', () {
      for (final kind in [...pictureKinds, EffectKind.plugin]) {
        expect(
          session.effectsAndFx.canAddEffectToActiveLayer(kind),
          isFalse,
          reason: '$kind on an S row',
        );
      }
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      expect(seRow().effects, isEmpty);
    });

    test('a picture row and the V row refuse the sound kind', () {
      final drawing = session.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      session.selectLayer(drawing.id);
      expect(
        session.effectsAndFx.canAddEffectToActiveLayer(EffectKind.equalizer),
        isFalse,
      );
      expect(
        session.effectsAndFx.canAddEffectToActiveLayer(EffectKind.blur),
        isTrue,
        reason: 'fixture: the row takes a picture kind',
      );
      expect(
        session.effectsAndFx.canAddEffectToTrack(
          session.activeTrack.id,
          EffectKind.equalizer,
        ),
        isFalse,
      );
    });

    test('a paste onto an S row takes its sound kinds alone', () {
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.equalizer);
      final equalizer = seRow().effects.single;
      final blur = LayerEffect.defaults(
        id: const EffectId('pasted-blur'),
        kind: EffectKind.blur,
      );

      session.effectsAndFx.addEffectCopies(const ActiveRowChain(), [
        blur,
        equalizer,
      ]);

      expect([for (final e in seRow().effects) e.kind], [
        EffectKind.equalizer,
        EffectKind.equalizer,
      ]);
    });
  });
}
