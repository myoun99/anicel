import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️I-19 (유저 2026-09-13): 「툴 내의 세부툴도 숏컷 지정 가능하게 하려고.
/// 툴 자체에 설정할수도있고 툴 내부의 세부툴도 설정가능하게」 — and the rule
/// that came with it for every button: 「버튼이면 왠만해선 숏컷 지정 가능하게
/// 리스트로 올리는걸 기본으로 두고싶어」.
///
/// ★Measured from the BUTTONS' side — the rail's groups and the tiles the
/// tool library actually lists ([subToolTilesOf]). A tile added there without
/// a row fails here, and so does a row whose button is gone.
void main() {
  final railGroups = {
    for (final tool in CanvasTool.values) canvasToolRailGroup(tool),
  };
  final buttonPresses = <ToolPress>[
    for (final group in railGroups) ...[
      RailToolPress(group),
      for (final tile in subToolTilesOf(group)) tile.press,
    ],
  ];

  test('⛔fixture premise: the rail has groups and the groups have tiles', () {
    expect(railGroups, hasLength(greaterThan(5)));
    expect(buttonPresses.whereType<SubToolPress>(), isNotEmpty);
  });

  test('every rail tool and every tile is exactly one action', () {
    for (final press in buttonPresses) {
      expect(
        editorActionDefinitions.where((d) => d.toolPress == press),
        hasLength(1),
        reason: '$press',
      );
    }
  });

  test('⛔and no tool action presses a button that is not there', () {
    expect([
      for (final definition in editorActionDefinitions)
        if (definition.toolPress case final press?)
          if (!buttonPresses.contains(press)) definition.id,
    ], isEmpty);
  });

  test('every verb of the colour edit list is an action', () {
    for (final verb in CelPixelVerb.values) {
      expect(
        editorActionDefinitions.where((d) => d.pixelVerb == verb),
        hasLength(1),
        reason: '$verb',
      );
    }
  });

  void expectDefault(ToolPress press, SingleActivator expected) {
    final id = toolActionIdFor(press);
    final defaults = editorActionDefinitions
        .firstWhere((d) => d.id == id)
        .defaultActivators;
    expect(defaults, hasLength(1), reason: id);
    expect(activatorsEqual(defaults.single, expected), isTrue, reason: id);
  }

  test('the keys the user named are the defaults', () {
    // 「선택도구의 올가미 선택에 w로 두고싶어」
    expectDefault(
      const ShapeTilePress(CanvasTool.select, CanvasShapeKind.lasso),
      const SingleActivator(LogicalKeyboardKey.keyW),
    );
    // 「잘라내기는 잘라내기 툴 자체에 c로 설정」
    expectDefault(
      const RailToolPress(CanvasTool.cut),
      const SingleActivator(LogicalKeyboardKey.keyC),
    );
    // 「채우기툴을 f로 변경하고, 가이드 툴을 g로 지정」
    expectDefault(
      const RailToolPress(CanvasTool.fill),
      const SingleActivator(LogicalKeyboardKey.keyF),
    );
    expectDefault(
      const RailToolPress(CanvasTool.guide),
      const SingleActivator(LogicalKeyboardKey.keyG),
    );
    // 「그냥 변형이 아니라 일반변형에 컨트롤+t로 연결하고 … 자유변형을
    // 컨트롤+y로」
    expectDefault(
      const TransformModePress(TransformMode.normal),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true),
    );
    expectDefault(
      const TransformModePress(TransformMode.perspective),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true),
    );
  });

  test('🪦the retired keys are nobody\'s: V, M and L alone, and Ctrl+Y as '
      'a second redo', () {
    for (final retired in const [
      SingleActivator(LogicalKeyboardKey.keyV),
      SingleActivator(LogicalKeyboardKey.keyM),
      SingleActivator(LogicalKeyboardKey.keyL),
    ]) {
      expect(
        [
          for (final definition in editorActionDefinitions)
            if (definition.defaultActivators.any(
              (activator) => activatorsEqual(activator, retired),
            ))
              definition.id,
        ],
        isEmpty,
        reason: retired.trigger.keyLabel,
      );
    }
    // 「다시실행 중복할당된거 제거하고 잔재도 제거해」
    final redo = editorActionDefinitions.firstWhere(
      (definition) => definition.id == EditorActionIds.redo,
    );
    expect(redo.defaultActivators, hasLength(1));
    expect(
      activatorsEqual(
        redo.defaultActivators.single,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ),
      ),
      isTrue,
    );
    for (final gone in const [
      'tool-lasso',
      'tool-move',
      'selection-free-transform',
    ]) {
      expect(
        editorActionDefinitions.where((definition) => definition.id == gone),
        isEmpty,
        reason: gone,
      );
    }
  });

  test('a shape tile is named in the reading language, composed from its '
      'verb and its shape — not a tabled copy', () {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    String nameOf(ToolPress press) => editorActionLabel(toolActionIdFor(press));

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    expect(
      nameOf(const ShapeTilePress(CanvasTool.select, CanvasShapeKind.lasso)),
      '올가미 선택',
    );
    expect(
      nameOf(const ShapeTilePress(CanvasTool.cut, CanvasShapeKind.rect)),
      '사각형 잘라내기',
    );
    // 「퍼스변형 이름을 자유변형으로 바꾸고」.
    expect(
      nameOf(const TransformModePress(TransformMode.perspective)),
      '자유 변형',
    );

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.fr,
    );
    expect(
      nameOf(const ShapeTilePress(CanvasTool.select, CanvasShapeKind.lasso)),
      'Sélection Lasso',
      reason: 'the order is the template\'s — French puts the verb first',
    );
  });

  test('no two actions ship the same key', () {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    expect(bindings.conflictedActionIds, isEmpty);
  });
}
