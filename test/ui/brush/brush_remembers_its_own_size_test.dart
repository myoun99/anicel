import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_hand_settings.dart'
    show brushHandSettingsRecalled;
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/services/brush_hand_overlay.dart';
import 'package:anicel/src/ui/brush/brush_hand_settings_store.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import '../../helpers/temp_dir.dart';

/// H25 — **each brush wears its own size.**
///
/// 유저 2026-08-23: 「클튜보면 브러시크기가 브러시마다 다르게 설정가능하던데,
/// 그거 따라가도록. 브러시 고르고 브러시크기 설정하면 다음에 같은 브러시
/// 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」.
///
/// 🚨This REVERSES R26 #10 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지
/// 않음」 for size, and that is why the old rule stays quoted at
/// [BrushToolState.withPreset]: it was a user decision, not an
/// oversight, and the next reader would otherwise find the new behaviour a bug.
/// Later ruling wins.
///
/// 🚨H25-again (유저 2026-09-11) widened it to every setting: 「사이즈말고도
/// 불투명도나 필압이나 이런거 … 싹 다 확인하고 법 하나로 통일」. What a pick
/// hands the state is now the whole brush as the hand left it, read back
/// through the same overlay the workspace keeps (`brush_hand_overlay.dart`).
///
/// The answers this implements (both on the board before it started):
/// * **Q-brush-param**: a brush the hand has never set reads what is baked
///   into its own file; one it HAS set restores what it was set to.
/// * **Q-brush-store**: kept in app storage, not written into the preset file
///   by a slider drag.
void main() {
  BrushSettings settingsWithSize(double size) =>
      BrushSettings.fromShape(BrushToolState.defaults.shape.copyWith(size: size));

  /// A preset carrying [settings] — what the library hands the state.
  BrushPreset presetOf(BrushSettings settings) => BrushPreset(
    id: const BrushPresetId('under-test'),
    name: 'under test',
    settings: settings,
  );

  group('picking a brush', () {
    test('an UNTOUCHED brush brings its own size, not the hand\'s', () {
      final hand = BrushToolState.defaults.copyWith(size: 42);

      final after = hand.withPreset(
        presetOf(settingsWithSize(7)),
        tool: CanvasTool.brush,
      );

      expect(
        after.size,
        7,
        reason: 'the size baked into the brush file wins when nobody has set '
            'one — R26 #10 kept the hand\'s 42 here',
      );
    });

    test('a brush the hand HAS set comes back at that size', () {
      final hand = BrushToolState.defaults.copyWith(size: 42);
      final file = settingsWithSize(7);

      final after = hand.withPreset(
        presetOf(file),
        tool: CanvasTool.brush,
        held: brushSettingsUnderHand(file, {'size': 13.0}),
      );

      expect(after.size, 13);
    });

    test('and opacity follows the same rule', () {
      final hand = BrushToolState.defaults.copyWith(opacity: 0.9);
      final file = BrushSettings.fromShape(
        BrushToolState.defaults.shape.copyWith(opacity: 0.25),
      );

      expect(
        hand.withPreset(presetOf(file), tool: CanvasTool.brush).opacity,
        0.25,
        reason: 'untouched: the brush\'s own',
      );
      expect(
        hand
            .withPreset(
              presetOf(file),
              tool: CanvasTool.brush,
              held: brushSettingsUnderHand(file, {'opacity': 0.5}),
            )
            .opacity,
        0.5,
        reason: 'hand-set: what the hand set',
      );
    });

    test('and so does the BLEND (유저 2026-09-08)', () {
      // 「블렌드모드도 어차피 브러시/툴마다 다르게 저장되도록. 사이즈나
      // 불투명도처럼 그렇게 되도록」 — the same two-part rule, third field.
      final multiply = BrushSettings.fromShape(
        BrushToolState.defaults.shape.copyWith(
          blendMode: BrushBlendMode.multiply,
        ),
      );
      final hand = BrushToolState.defaults.copyWith(
        blendMode: BrushBlendMode.screen,
      );

      expect(
        hand.withPreset(presetOf(multiply), tool: CanvasTool.brush).blendMode,
        BrushBlendMode.multiply,
        reason: 'untouched: the brush\'s own',
      );
      expect(
        hand
            .withPreset(
              presetOf(multiply),
              tool: CanvasTool.brush,
              held: brushSettingsUnderHand(multiply, {
                'blendMode': BrushBlendMode.add.name,
              }),
            )
            .blendMode,
        BrushBlendMode.add,
        reason: 'hand-set: what the hand set on THIS brush',
      );
    });

    test('🚨H25-again: and so does everything else — 「필압이나 이런거」', () {
      final file = settingsWithSize(7);
      final curve = BrushPressureCurve.linearFrom(0.6);

      final after = BrushToolState.defaults.withPreset(
        presetOf(file),
        tool: CanvasTool.brush,
        held: brushSettingsUnderHand(file, {
          'sizePressureCurve': curve.toJson(),
          'flow': 0.3,
        }),
      );

      expect(
        jsonEncode(after.shape.sizePressureCurve?.toJson()),
        jsonEncode(curve.toJson()),
      );
      expect(after.flow, 0.3);
      expect(
        after.size,
        7,
        reason: 'what the hand did not touch still follows the file',
      );
    });

    test('the COLOUR exception survives — it is the other decision', () {
      final hand = BrushToolState.defaults.copyWith(color: 0xFFFF0000);
      final file = settingsWithSize(7);

      for (final held in [
        null,
        BrushSettings.fromShape(file.shape.copyWith(color: 0xFF00FF00)),
      ]) {
        expect(
          hand
              .withPreset(presetOf(file), tool: CanvasTool.brush, held: held)
              .color,
          0xFFFF0000,
          reason: 'R9 #2: most of the roster carries the default black, so a '
              'brush swap would silently repaint the palette — held or not',
        );
      }
    });
  });

  group('the store', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('qa_hand_'));
    tearDown(() => deleteTempQuietly(folder));

    test('round-trips what the hand set — every kind of setting', () async {
      final store = BrushHandSettingsStore(
        filePath: '${folder.path}/bank.json',
      );
      final bank = <String, BrushHandSettings>{
        'sketch': {'size': 13.0, 'opacity': 0.5, 'blendMode': 'multiply'},
        'ink': {
          'sizePressureCurve': BrushPressureCurve.linearFrom(0.6).toJson(),
          'flow': 0.3,
          'tipMaskId': 'tip-7',
          'dualMask': null,
        },
      };
      await store.save(bank);

      expect(await store.load(), bank);
    });

    test('⚠️a bank that lands late gives way to what the hand set since the '
        'app opened', () {
      final recalled = brushHandSettingsRecalled(
        live: {
          'sketch': {'size': 5.0},
        },
        saved: {
          'sketch': {'size': 13.0},
          'ink': {'flow': 0.3},
        },
      );

      expect(recalled, {
        'sketch': {'size': 5.0},
        'ink': {'flow': 0.3},
      }, reason: 'the newer fact wins; the older one fills only what is new');
    });

    test('🚨a bank written before H25-again reads as an overlay — its three '
        'values are spelled the way the brush spells them', () async {
      final path = '${folder.path}/old.json';
      File(path).writeAsStringSync(
        jsonEncode({
          'version': BrushHandSettingsStore.version,
          'brushes': {
            'sketch': {'size': 13, 'opacity': 0.5, 'blendMode': 'multiply'},
          },
        }),
      );

      final read = await BrushHandSettingsStore(filePath: path).load();
      final settings = brushSettingsUnderHand(
        settingsWithSize(7),
        read['sketch']!,
      );

      expect(settings.size, 13);
      expect(settings.opacity, 0.5);
      expect(settings.blendMode, BrushBlendMode.multiply);
    });

    test('a missing file is simply an empty bank — every brush then reads '
        'its own baked size', () async {
      final store = BrushHandSettingsStore(
        filePath: '${folder.path}/nothing-here.json',
      );
      expect(await store.load(), isEmpty);
    });

    test('and so is a corrupt one', () async {
      final path = '${folder.path}/broken.json';
      File(path).writeAsStringSync('{not json');
      expect(await BrushHandSettingsStore(filePath: path).load(), isEmpty);
    });
  });
}
