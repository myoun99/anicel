import 'package:anicel/src/services/shortcuts/program_keymap.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_shortcuts.dart';

/// 🗣️I-149 (유저 2026-11-02): 「브러시 사이즈 변경(한걸음올리기 내리기)
/// 단축키 없지않나? 등록하고 클튜나 tvp도 아마 키 있을텐데 등록. anicel은
/// [랑 ]. ]가 한걸음 올리기」.
///
/// ★A KEY IS THE BAR'S ±: where it lands is asked of the bar, so the rack
/// stands in one place (F-325).
void main() {
  const rack = ToolSizePresetPanel.presets;

  group('in the app', () {
    late BrushToolState Function() hand;

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      final notifier = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .brushTool!;
      hand = () => notifier.value;
    }

    void put(WidgetTester tester, BrushToolState state) => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!
        .value = state;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> pressShifted(
      WidgetTester tester,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('🚨] takes the next stop of the rack up and [ the next down, '
        'and the bar\'s ± lands the same', (tester) async {
      await pumpApp(tester);
      await useAnicelKeys(tester);
      put(tester, hand().withActiveSize(rack[3]));

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack[4]);
      await press(tester, LogicalKeyboardKey.bracketLeft);
      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(hand().activeSize, rack[2]);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('brush-pill-size-bar')),
          matching: find.byKey(const ValueKey('field-slider-step-up')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        hand().activeSize,
        rack[3],
        reason: 'the bar\'s + from where the keys left it',
      );
    });

    testWidgets('🚨a size between two stops goes to the next one each way', (
      tester,
    ) async {
      await pumpApp(tester);
      await useAnicelKeys(tester);
      final between = (rack[3] + rack[4]) / 2;
      put(tester, hand().withActiveSize(between));
      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack[4]);

      put(tester, hand().withActiveSize(between));
      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(hand().activeSize, rack[3]);
    });

    testWidgets('⛔past the rack\'s ends a key leaves the size where it is', (
      tester,
    ) async {
      await pumpApp(tester);
      await useAnicelKeys(tester);
      put(tester, hand().withActiveSize(rack.first));
      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(hand().activeSize, rack.first);

      put(tester, hand().withActiveSize(rack.last));
      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack.last);
    });

    testWidgets('🚨the tool in hand\'s own size moves — the eraser\'s, and the '
        'brush keeps its', (tester) async {
      await pumpApp(tester);
      await useAnicelKeys(tester);
      put(tester, hand().withActiveSize(rack[3]));
      final brushSize = hand().activeSize;
      await press(tester, LogicalKeyboardKey.keyE);
      expect(hand().tool, CanvasTool.eraser, reason: '⛔전제: 지우개로 바꿨다');
      put(tester, hand().withActiveSize(rack[6]));

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack[7]);

      await press(tester, LogicalKeyboardKey.keyB);
      expect(hand().activeSize, brushSize);
    });

    testWidgets('⛔a tool with no size takes no step', (tester) async {
      await pumpApp(tester);
      await useAnicelKeys(tester);
      put(tester, hand().copyWith(tool: CanvasTool.move));
      expect(
        hand().supports(ToolParameter.size),
        isFalse,
        reason: '⛔전제: 크기가 없는 도구다',
      );
      final before = hand();

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(identical(hand(), before), isTrue);
    });

    testWidgets('🚨Clip Studio\'s [ and ] press it', (tester) async {
      await pumpApp(tester);
      expect(appShortcuts(tester).preset, ShortcutPreset.clipStudio);
      put(tester, hand().withActiveSize(rack[3]));

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack[4]);
      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(hand().activeSize, rack[3]);
    });

    testWidgets('🚨TVPaint\'s + and - press it however a keyboard types them, '
        'and its [ and ] stay the view\'s flips', (tester) async {
      await pumpApp(tester);
      appShortcuts(tester).setPreset(ShortcutPreset.tvpaint);
      await tester.pump();
      put(tester, hand().withActiveSize(rack[3]));

      await press(tester, LogicalKeyboardKey.numpadAdd);
      expect(hand().activeSize, rack[4], reason: 'the pad\'s +');
      await pressShifted(tester, LogicalKeyboardKey.semicolon);
      expect(hand().activeSize, rack[5], reason: '+ on a JIS keyboard');
      await pressShifted(tester, LogicalKeyboardKey.equal);
      expect(hand().activeSize, rack[6], reason: '+ on a US keyboard');

      await press(tester, LogicalKeyboardKey.numpadSubtract);
      expect(hand().activeSize, rack[5], reason: 'the pad\'s -');
      await press(tester, LogicalKeyboardKey.minus);
      expect(hand().activeSize, rack[4], reason: 'the keyboard\'s -');

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(hand().activeSize, rack[4], reason: 'there, ] flips the view');
    });
  });

  group('what ships', () {
    List<String> keysOf(ShortcutPreset preset, String actionId) => [
      for (final key in presetActivators(
        preset,
        editorActionDefinitions.singleWhere((row) => row.id == actionId),
      ))
        activatorKey(key),
    ];
    String spelled(LogicalKeyboardKey key, {bool shift = false}) =>
        activatorKey(SingleActivator(key, shift: shift));

    test('anicel\'s keys are the ones asked for: ] is up', () {
      expect(keysOf(ShortcutPreset.anicel, EditorActionIds.brushSizeUp), [
        spelled(LogicalKeyboardKey.bracketRight),
      ]);
      expect(keysOf(ShortcutPreset.anicel, EditorActionIds.brushSizeDown), [
        spelled(LogicalKeyboardKey.bracketLeft),
      ]);
    });
  });

  group('a program\'s file', () {
    test('🚨TVPaint\'s keymap gives the two steps the keys it names, and its '
        '+ is one a keyboard can press', () {
      final keys = fileKeysOf([
        readTvpaintKeymap(
          '[keyboard]\n-=DecreaseToolsSize\n+=IncreaseToolsSize\n',
        )!,
      ]);
      expect(keys[EditorActionIds.brushSizeDown]!.map(activatorKey), [
        activatorKey(const SingleActivator(LogicalKeyboardKey.minus)),
      ]);
      expect(keys[EditorActionIds.brushSizeUp]!.map(activatorKey), [
        activatorKey(const SingleActivator(LogicalKeyboardKey.numpadAdd)),
      ]);
    });

    test('🚨TVPaint\'s shortcut window\'s text says them by name', () {
      final keys = fileKeysOf([
        readTvpaintKeymap(
          'Shortcuts\n'
          '"-" = none${tvpaintShownNames['DecreaseToolsSize']}\n'
          '"+" = none${tvpaintShownNames['IncreaseToolsSize']}\n',
        )!,
      ]);
      expect(
        keys.keys,
        containsAll([
          EditorActionIds.brushSizeUp,
          EditorActionIds.brushSizeDown,
        ]),
      );
    });

    test('🚨each of Clip Studio\'s size commands gives the step its key', () {
      List<String> keysOfFile(String command, String actionId) {
        final keys = fileKeysOf([
          ProgramKeymap(
            program: KeymapProgram.clipStudio,
            keys: {
              command: const [ProgramChord(LogicalKeyboardKey.keyH)],
            },
            unread: 0,
          ),
        ]);
        return [...keys[actionId]!.map(activatorKey)];
      }

      final h = [activatorKey(const SingleActivator(LogicalKeyboardKey.keyH))];
      for (final (command, actionId) in const [
        ('toolsizenext', EditorActionIds.brushSizeUp),
        ('toolsizeplus', EditorActionIds.brushSizeUp),
        ('toolsizeprevious', EditorActionIds.brushSizeDown),
        ('toolsizeminus', EditorActionIds.brushSizeDown),
      ]) {
        expect(keysOfFile(command, actionId), h, reason: command);
      }
    });
  });
}
