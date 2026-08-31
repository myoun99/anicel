import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';

/// 🚨★★★A BRUSH IN HAND THAT THE LIBRARY CANNOT NAME.
///
/// 유저 (F-63): 「브러시/지우개에서, 브러시 라이브러리에서 **초기값이 아무것도
/// 선택안된 UI**인데, 브러시는 그려지는거 보니 **초기 브러시자체는
/// 정해져있는거같음.** 그게 ui에도 연동되있도록」.
///
/// ⛔The app opened with TWO facts: the paint tool carried baked-in settings
/// while the active-preset map was EMPTY. Nothing was persisted either way,
/// so no remembered choice is being overwritten by fixing it — the map simply
/// started blank and never caught up.
void main() {
  BrushPreset preset(String id) =>
      BrushPreset(id: BrushPresetId(id), name: id, settings: BrushSettings(size: 12));

  final library = [preset('a'), preset('b')];

  test('🚨★★★a painting tool with nothing chosen opens on the first preset', () {
    expect(
      openingPresetFor(
        presets: library,
        toolPaints: true,
        alreadyChosen: false,
      )?.id.value,
      'a',
    );
  });

  test('⛔never overrules a choice already made', () {
    // A load that lands after the user has picked must leave their brush
    // alone — the library loads asynchronously, so this really can race.
    expect(
      openingPresetFor(presets: library, toolPaints: true, alreadyChosen: true),
      isNull,
    );
  });

  test('⛔★★★never moves the hand — a non-painting tool is left alone', () {
    // 🚨`_applyPreset` ARMS THE BRUSH when the current tool does not paint.
    // Seeding through it from, say, the selection tool would change the tool
    // the app opens with, which nobody asked for.
    expect(
      openingPresetFor(
        presets: library,
        toolPaints: false,
        alreadyChosen: false,
      ),
      isNull,
    );
  });

  test('⛔an empty library selects nothing', () {
    expect(
      openingPresetFor(
        presets: const [],
        toolPaints: true,
        alreadyChosen: false,
      ),
      isNull,
    );
  });
}
