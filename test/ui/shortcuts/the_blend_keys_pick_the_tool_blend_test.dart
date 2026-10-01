import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';

/// 🗣️I-31 (유저 2026-09-14): 「도구의 블렌드모드(브러시나 채우기나)내용
/// 숏컷으로서 등록. 컬러,비하인드 등 리스트 전부. 그리고 위에서부터 순서대로
/// F1부터 F12까지 등록할수있는만큼 초기값으로서 숏컷 등록」.
void main() {
  final blendActions = [
    for (final definition in editorActionDefinitions)
      if (definition.blendMode != null) definition,
  ];

  test('every mode of the list is an action, in the list\'s order', () {
    expect(
      [for (final definition in blendActions) definition.blendMode],
      BrushBlendMode.values,
    );
  });

  test('the first twelve are F1–F12 from the top; the rest have no key', () {
    const functionKeys = [
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f2,
      LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4,
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7,
      LogicalKeyboardKey.f8,
      LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f10,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.f12,
    ];
    for (final (index, definition) in blendActions.indexed) {
      if (index < functionKeys.length) {
        expect(definition.defaultActivators, hasLength(1));
        expect(
          activatorsEqual(
            definition.defaultActivators.single,
            SingleActivator(functionKeys[index]),
          ),
          isTrue,
          reason: '${definition.blendMode}',
        );
      } else {
        expect(
          definition.defaultActivators,
          isEmpty,
          reason: '${definition.blendMode} — 「등록할수있는만큼」',
        );
      }
    }
  });

  testWidgets('a blend key picks the blend of the tool in hand, and only '
      'where the strip\'s chooser could', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    BrushToolState tool() => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!
        .value;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(tool().tool, CanvasTool.brush);
    await press(LogicalKeyboardKey.f5);
    expect(tool().activeBlendMode, BrushBlendMode.multiply);

    // The fill keeps a blend of its own.
    await press(LogicalKeyboardKey.keyF);
    expect(tool().tool, CanvasTool.fill);
    await press(LogicalKeyboardKey.f2);
    expect(tool().activeBlendMode, BrushBlendMode.behind);

    // ⚠️The RAW field, not `activeBlendMode`: the eraser's always answers
    // erase, and a switch back to the brush restores the brush's own bank —
    // either would hide a write that landed where no chooser is.
    //
    // The eraser IS the erase blend — nothing to pick.
    await press(LogicalKeyboardKey.keyE);
    expect(tool().tool, CanvasTool.eraser);
    final eraserBlend = tool().blendMode;
    await press(LogicalKeyboardKey.f4);
    expect(tool().blendMode, eraserBlend);

    // A tool that composites nothing picks nothing.
    await press(LogicalKeyboardKey.keyW);
    expect(tool().tool, CanvasTool.select);
    final carried = tool().blendMode;
    await press(LogicalKeyboardKey.f4);
    expect(tool().blendMode, carried);

    await press(LogicalKeyboardKey.keyB);
    expect(tool().activeBlendMode, BrushBlendMode.multiply);
    await press(LogicalKeyboardKey.keyF);
    expect(tool().activeBlendMode, BrushBlendMode.behind);
  });
}
