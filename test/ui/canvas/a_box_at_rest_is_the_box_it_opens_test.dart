import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/transform_tool_on_canvas.dart';

/// The Transform tool's box before anything has opened it is the box that
/// opens: the same pill under it, the same handles on it, in every mode.
///
/// 🗣️F-585 (유저 2026-11-12): 「변형도구 아래 알약, 변형의 값이
/// 바껴야(변형시작해야) 뜨는데, 그냥 변형도구상태면 뜨도록. 대신 값이
/// 안바뀐상태면 확정/취소버튼 존재는 하되 비활성화」.
///
/// 🗣️F-586 (유저 2026-11-12): 「매쉬변형, 변형시작해야 내부 사각형들 뜨는데,
/// 그냥 매쉬변형인 상태면 뜨도록. 변형안한상태로 그것들 잡아끌어서
/// 변형한다는게 안되는게 이유.」
void main() {
  const pill = ValueKey<String>('selection-confirm-pill');
  const confirm = 'selection-move-confirm';
  const cancel = 'selection-move-cancel';
  const pillButtons = [
    'selection-move-anti-alias',
    'selection-move-flip-horizontal',
    'selection-move-flip-vertical',
    confirm,
    cancel,
  ];
  VoidCallback? pressOf(WidgetTester tester, String key) =>
      tester.appIconButton(find.byKey(ValueKey<String>(key))).onPressed;

  for (final selected in [true, false]) {
    final over = selected ? 'a selection' : 'the whole picture';

    testWidgets('the Transform tool\'s box over $over wears its pill before '
        'any transform begins — 확정 and 취소 there, and grey', (tester) async {
      final (:commands, options: _, tool: _) = await pumpTransformTool(
        tester,
        selected: selected,
      );
      expect(commands.transformActive, isFalse, reason: 'nothing has opened');

      for (final key in pillButtons) {
        expect(
          find.descendant(
            of: find.byKey(pill),
            matching: find.byKey(ValueKey<String>(key)),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      expect(pressOf(tester, confirm), isNull, reason: 'nothing to land');
      expect(pressOf(tester, cancel), isNull, reason: 'nothing to take back');
      expect(
        pressOf(tester, 'selection-move-flip-horizontal'),
        isNotNull,
        reason: 'a flip is a transform beginning',
      );
    });

    for (final mode in TransformMode.values) {
      testWidgets('at rest over $over the box wears what it opens with in '
          '$mode — its outline, its handles, its cross, and the pill where '
          'it will stand', (tester) async {
        final (:commands, options: _, tool: _) = await pumpTransformTool(
          tester,
          options: TransformToolOptions(mode: mode),
          selected: selected,
        );
        final atRest = transformChromeOnScreen(tester)!;
        final pillAtRest = tester.getRect(find.byKey(pill));
        expect(commands.transformActive, isFalse, reason: 'the premise');

        commands.beginTransform();
        await tester.pump();
        expect(commands.transformActive, isTrue, reason: 'the premise');

        final open = transformChromeOnScreen(tester)!;
        expect(atRest.handles, open.handles);
        expect(atRest.box, open.box);
        expect(atRest.anchor, open.anchor);
        expect(tester.getRect(find.byKey(pill)), pillAtRest);
      });
    }
  }

  testWidgets('a 메쉬 box at rest shows its grid, the points inside it '
      'included', (tester) async {
    await pumpTransformTool(
      tester,
      options: const TransformToolOptions(mode: TransformMode.mesh),
    );
    final handles = transformChromeOnScreen(tester)!.handles;
    expect(handles, hasLength(16), reason: '3×3 cells: 4×4 points, no grips');
    expect(
      (handles[transformToolFirstInside] - const Offset(320, 220)).distance,
      lessThan(0.01),
    );
  });

  testWidgets('a point inside a 메쉬 grid is dragged from rest — the press '
      'opens the box and carries that point alone', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      options: const TransformToolOptions(mode: TransformMode.mesh),
    );
    final atRest = transformChromeOnScreen(tester)!.handles;

    await dragOnTransformLayer(
      tester,
      const Offset(320, 220),
      const Offset(326, 215),
    );

    expect(commands.transformActive, isTrue, reason: 'the press opened it');
    final dragged = transformChromeOnScreen(tester)!.handles;
    expect(
      (dragged[transformToolFirstInside] - const Offset(326, 215)).distance,
      lessThan(0.01),
      reason: 'the point went with the hand',
    );
    expect(
      [
        for (var index = 0; index < dragged.length; index += 1)
          if (index != transformToolFirstInside) dragged[index],
      ],
      [
        for (var index = 0; index < atRest.length; index += 1)
          if (index != transformToolFirstInside) atRest[index],
      ],
      reason: 'every other point where it stood',
    );
    expect(pressOf(tester, confirm), isNotNull, reason: 'a change to land');
    expect(pressOf(tester, cancel), isNotNull, reason: 'and to take back');
  });

  testWidgets('a box opened and left as it opened keeps 취소 grey, and 취소 '
      'after a change leaves the pill standing with both grey again', (
    tester,
  ) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(tester);
    commands.beginTransform();
    await tester.pump();
    expect(commands.transformActive, isTrue, reason: 'the premise');
    expect(pressOf(tester, cancel), isNull, reason: 'nothing changed');

    commands.editTransformValues((now) => now.copyWith(tx: 12));
    await tester.pump();
    expect(pressOf(tester, cancel), isNotNull, reason: 'a change');

    await tester.tap(find.byKey(const ValueKey<String>(cancel)));
    await tester.pump();
    expect(commands.transformActive, isFalse, reason: '취소 closed the box');
    expect(find.byKey(pill), findsOneWidget, reason: 'the pill does not go');
    expect(pressOf(tester, confirm), isNull);
    expect(pressOf(tester, cancel), isNull);
  });

  testWidgets('the box stands at rest under the Transform tool alone — the '
      'same selection under the selection tool wears no box, and none of '
      'its pill', (tester) async {
    final (commands: _, options: _, :tool) = await pumpTransformTool(tester);
    expect(transformChromeOnScreen(tester), isNotNull, reason: 'the premise');
    expect(find.byKey(pill), findsOneWidget, reason: 'the premise');

    tool.value = tool.value.copyWith(tool: CanvasTool.select);
    await tester.pump();
    await tester.pump();

    expect(transformChromeOnScreen(tester), isNull);
    expect(find.byKey(pill), findsNothing);
  });

  testWidgets('an outline still being drawn when the Transform tool is '
      'picked wears no box until it is let go', (tester) async {
    final (commands: _, options: _, :tool) = await pumpTransformTool(
      tester,
      selected: false,
    );
    tool.value = tool.value.copyWith(tool: CanvasTool.select);
    await tester.pump();
    await tester.pump();
    final gesture = await pressOnTransformLayer(
      tester,
      const Offset(300, 200),
    );
    final origin = tester.getTopLeft(find.byKey(transformToolLayerKey));
    await gesture.moveTo(origin + const Offset(360, 260));
    await tester.pump();

    tool.value = tool.value.copyWith(tool: CanvasTool.move);
    await tester.pump();
    await tester.pump();
    expect(
      transformChromeOnScreen(tester),
      isNull,
      reason: 'the outline is still in hand',
    );
    expect(find.byKey(pill), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(transformChromeOnScreen(tester), isNotNull);
    expect(find.byKey(pill), findsOneWidget);
  });

  testWidgets('over a cel with no picture the pill stands with every verb '
      'grey', (tester) async {
    final (:commands, options: _, tool: _) = await pumpTransformTool(
      tester,
      selected: false,
      inked: false,
    );
    expect(commands.transformActive, isFalse);
    expect(find.byKey(pill), findsOneWidget);
    for (final key in [
      'selection-move-flip-horizontal',
      'selection-move-flip-vertical',
      confirm,
      cancel,
    ]) {
      expect(pressOf(tester, key), isNull, reason: key);
    }
  });
}
