import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
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
    expect(session.effectsAndFx.canAddEffectToActiveLayer, isTrue);

    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);

    expect([for (final e in seRow().effects) e.kind], [EffectKind.blur]);
  });

  test('keying its parameter from cut 2 keys the row at the GLOBAL frame, '
      'one undo', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final effect = seRow().effects.single;

    session.laneVerbs.toggleLaneKeyAt(
      se,
      effectLaneId(effect.id, 'blurX'),
      3,
      frameIsGlobal: false,
      description: 'Blur keyframe',
    );

    expect(
      seRow().effects.single.parameters['blurX']!.track.keys.keys.toList(),
      [cut2Start + 3],
    );
    session.undo();
    expect(
      seRow().effects.single.parameters['blurX']!.track.keys,
      isEmpty,
      reason: 'one undo takes the key back',
    );
  });

  test('an effect added from cut 2 keeps the keys the row already holds on '
      'their GLOBAL frames — it is built from the row, not its projection', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final blur = seRow().effects.single;
    session.laneVerbs.toggleLaneKeyAt(
      se,
      effectLaneId(blur.id, 'blurX'),
      2,
      frameIsGlobal: false,
      description: 'Blur keyframe',
    );

    session.effectsAndFx.addEffectToActiveLayer(EffectKind.hueSaturation);

    final effects = seRow().effects;
    expect([for (final e in effects) e.kind], [
      EffectKind.blur,
      EffectKind.hueSaturation,
    ]);
    expect(
      effects.first.parameters['blurX']!.track.keys.keys.toList(),
      [cut2Start + 2],
    );
  });

  test('the row\'s master FX switch bypasses its chain too', () {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);

    session.effectsAndFx.toggleLayerFx(se);

    expect(seRow().effects.single.enabled, isFalse);
    expect(seRow().transformEnabled, isFalse);
  });
}
