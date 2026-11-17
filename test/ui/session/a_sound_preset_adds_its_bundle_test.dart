import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/sound_preset.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/effects_and_fx.dart'
    show ActiveRowChain;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show soundPresetActionLabel;
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:anicel/src/ui/timeline/timeline_bar_menus.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// A sound preset's row adds its bundle to the S row as a paste of effects
/// does — an equalizer then a compressor at the preset's values, one undo —
/// and is dimmed on a row that takes none of a sound's (board
/// audio-fx-second-effect-and-presets ②).
///
/// 🗣️Q2 (유저 2026-11-17): 「시안 3 · 시안 1 + 성격 프리셋」 — its bundle
/// comes in as design 1's fx groups, and then is design 1's.
void main() {
  late EditorSessionManager session;
  late LayerId se;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    se = session.activeTrack.seLayers.first.id;
  });
  tearDown(() => session.dispose());

  Layer seRow() =>
      session.activeTrack.seLayers.firstWhere((layer) => layer.id == se);

  PanelFlyoutItem rowOf(SoundPreset preset) =>
      TimelineBarMenus(
        session: session,
        panel: TimelineToolbarPanelContext(session),
      ).effects().whereType<PanelFlyoutItem>().singleWhere(
        (item) => item.keyValue == 'add-sound-preset-${preset.jsonValue}',
      );

  test('🎯on an S row, its row adds an equalizer then a compressor at its '
      'values — one undo takes both away', () {
    session.selectLayer(se);
    final row = rowOf(SoundPreset.dialogue);
    expect(row.enabled, isTrue);

    row.onSelected!();

    final added = seRow().effects;
    expect([for (final effect in added) effect.kind], [
      EffectKind.equalizer,
      EffectKind.compressor,
    ]);
    final (equalizer, compressor) = (added.first, added.last);
    expect(equalizer.parameterOf('lowCut').value, 80);
    expect(equalizer.parameterOf('highGain').value, 2);
    expect(
      {
        for (final id in ['threshold', 'ratio', 'attack', 'release', 'makeup'])
          id: compressor.parameterOf(id).value,
      },
      {'threshold': -20, 'ratio': 3, 'attack': 5, 'release': 80, 'makeup': 3},
    );
    expect(
      equalizer.id,
      isNot(compressor.id),
      reason: 'each under an id of its own, minted for the row',
    );

    session.undo();

    expect(seRow().effects, isEmpty);
  });

  test('picked twice, it adds its bundle twice — as a paste does', () {
    session.selectLayer(se);
    rowOf(SoundPreset.music).onSelected!();
    rowOf(SoundPreset.music).onSelected!();

    expect([for (final effect in seRow().effects) effect.kind], [
      EffectKind.equalizer,
      EffectKind.compressor,
      EffectKind.equalizer,
      EffectKind.compressor,
    ]);
    expect(seRow().effects.map((effect) => effect.id).toSet(), hasLength(4));
  });

  test('a picture row takes none of a sound\'s: every preset\'s row is '
      'dimmed', () {
    expect(session.activeLayer?.kind.playsSound, isFalse);
    for (final preset in SoundPreset.values) {
      expect(rowOf(preset).enabled, isFalse, reason: '$preset');
      expect(
        session.effectsAndFx.canAddEffectCopies(
          const ActiveRowChain(),
          preset.effects,
        ),
        isFalse,
      );
    }
  });

  test('every preset is a sound\'s bundle at values its knobs can hold', () {
    for (final preset in SoundPreset.values) {
      final effects = preset.effects;
      expect(
        [for (final effect in effects) effect.kind],
        [EffectKind.equalizer, EffectKind.compressor],
        reason: '$preset',
      );
      for (final effect in effects) {
        expect(
          effect.parameters.keys,
          everyElement(
            isIn([for (final spec in effect.kind.parameters) spec.id]),
          ),
          reason: '$preset sets only knobs its ${effect.kind} has',
        );
        for (final spec in effect.kind.parameters) {
          final value = effect.parameterOf(spec.id).value;
          expect(
            value,
            inInclusiveRange(spec.minimum, spec.maximum),
            reason: '$preset ${spec.id}',
          );
        }
      }
    }
  });

  test('its row is named as the column names it, its action with the '
      'column first', () {
    session.selectLayer(se);
    expect(
      rowOf(SoundPreset.dialogue).label,
      SoundPreset.dialogue.labelFor(AppText.language),
    );
    expect(SoundPreset.dialogue.labelFor(AppLanguage.ja), 'セリフ');
    expect(
      soundPresetActionLabel(SoundPreset.ambience, AppLanguage.ja),
      'プリセット: 環境音',
    );
  });
}
