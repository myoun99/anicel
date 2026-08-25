import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_hand_settings_store.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// H25 — **each brush wears its own size.**
///
/// 유저 2026-08-23: 「클튜보면 브러시크기가 브러시마다 다르게 설정가능하던데,
/// 그거 따라가도록. 브러시 고르고 브러시크기 설정하면 다음에 같은 브러시
/// 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」.
///
/// 🚨This REVERSES R26 #10 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지
/// 않음」 for size, and that is why the old rule stays quoted at
/// [BrushToolState.withPresetSettings]: it was a user decision, not an
/// oversight, and the next reader would otherwise find the new behaviour a bug.
/// Later ruling wins.
///
/// The answers this implements (both on the board before it started):
/// * **Q-brush-param**: a brush the hand has never set reads the size baked
///   into its own file; one it HAS set restores what it was set to.
/// * **Q-brush-store**: kept in app storage, not written into the preset file
///   by a slider drag.
void main() {
  BrushSettings settingsWithSize(double size) =>
      BrushSettings.fromShape(BrushToolState.defaults.shape.copyWith(size: size));

  group('picking a brush', () {
    test('an UNTOUCHED brush brings its own size, not the hand\'s', () {
      final hand = BrushToolState.defaults.copyWith(size: 42);

      final after = hand.withPresetSettings(
        settingsWithSize(7),
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

      final after = hand.withPresetSettings(
        settingsWithSize(7),
        tool: CanvasTool.brush,
        handSet: (size: 13, opacity: null),
      );

      expect(after.size, 13);
    });

    test('and opacity follows the same rule', () {
      final hand = BrushToolState.defaults.copyWith(opacity: 0.9);

      expect(
        hand
            .withPresetSettings(
              BrushSettings.fromShape(
                BrushToolState.defaults.shape.copyWith(opacity: 0.25),
              ),
              tool: CanvasTool.brush,
            )
            .opacity,
        0.25,
        reason: 'untouched: the brush\'s own',
      );
      expect(
        hand
            .withPresetSettings(
              BrushSettings.fromShape(
                BrushToolState.defaults.shape.copyWith(opacity: 0.25),
              ),
              tool: CanvasTool.brush,
              handSet: (size: null, opacity: 0.5),
            )
            .opacity,
        0.5,
        reason: 'hand-set: what the hand set',
      );
    });

    test('the COLOUR exception survives — it is the other decision', () {
      final hand = BrushToolState.defaults.copyWith(color: 0xFFFF0000);

      final after = hand.withPresetSettings(
        settingsWithSize(7),
        tool: CanvasTool.brush,
      );

      expect(
        after.color,
        0xFFFF0000,
        reason: 'R9 #2: most of the roster carries the default black, so a '
            'brush swap would silently repaint the palette',
      );
    });
  });

  group('the store', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('qa_hand_'));
    tearDown(() => folder.deleteSync(recursive: true));

    test('round-trips what the hand set', () async {
      final store = BrushHandSettingsStore(
        filePath: '${folder.path}/bank.json',
      );
      await store.save({
        'sketch': (size: 13, opacity: 0.5),
        'ink': (size: 2.5, opacity: null),
      });

      final read = await store.load();

      expect(read['sketch'], (size: 13.0, opacity: 0.5));
      expect(read['ink'], (size: 2.5, opacity: null));
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
