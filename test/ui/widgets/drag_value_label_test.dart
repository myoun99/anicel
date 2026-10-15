// A NUMBER YOU OPERATE, BY HANDS THAT EACH DO ONE THING: its face drags from
// the first pixel, its pencil opens the field, its ± step it, and the wheel
// over it turns it a step a notch.
//
// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「지금의 박스는 그냥 드래그만
// 하고, 편집창 여는건 그 옆에 편집아이콘 둬서 그거누르면 열리도록. 열리면
// 텍스트 전체선택된상태?」 · 「상자에 한걸음 올리기 내리기버튼들도 동일하게」 ·
// 휠 「좋아」. These pins drive it as a user does.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/theme/app_theme.dart'
    show AppColors, buildAppTheme;
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/inline_numeric_field.dart';

/// What a readout told its owner.
class _Seen {
  final deltas = <double>[];
  final edits = <String>[];
  int starts = 0;
  int ends = 0;
}

void main() {
  const face = ValueKey<String>('zoom');
  const pencil = ValueKey<String>('zoom-edit');

  Future<_Seen> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool box = false,
    PressFire? fireOn,
  }) async {
    final seen = _Seen();
    final readout = box
        ? SizedBox(
            width: 200,
            child: DragValueLabel.box(
              keyValue: 'zoom',
              name: 'X',
              text: '100%',
              onDragDelta: seen.deltas.add,
              onEditSubmit: seen.edits.add,
              onOperationStart: () => seen.starts += 1,
              onOperationEnd: () => seen.ends += 1,
              enabled: enabled,
            ),
          )
        : DragValueLabel(
            keyValue: 'zoom',
            text: '100%',
            onDragDelta: seen.deltas.add,
            onEditSubmit: seen.edits.add,
            onOperationStart: () => seen.starts += 1,
            onOperationEnd: () => seen.ends += 1,
            unitsPerPixel: 1,
            width: 64,
            enabled: enabled,
          );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: fireOn == null
                ? readout
                : PressFireScope(fireOn: fireOn, child: readout),
          ),
        ),
      ),
    );
    return seen;
  }

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    testWidgets('a ${kind.name} drag on the face scrubs from its FIRST pixel, '
        'in whole units, and opens nothing', (tester) async {
      final seen = await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(face)),
        kind: kind,
      );
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(seen.deltas, [1], reason: 'one pixel is one unit, at once');
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(seen.deltas.fold(0.0, (a, b) => a + b), 4);
      for (final delta in seen.deltas) {
        expect(delta, delta.roundToDouble(), reason: 'whole units only');
      }
      expect(find.byType(InlineNumericField), findsNothing);
      expect(seen.edits, isEmpty);
    });
  }

  testWidgets('a press on the face that does not move does NOTHING — no '
      'field, no step, no operation', (tester) async {
    final seen = await pump(tester);
    await tester.tap(find.byKey(face));
    await tester.pump();
    expect(find.byType(InlineNumericField), findsNothing);
    expect(seen.deltas, isEmpty);
    expect(seen.starts, 0);
    expect(seen.ends, 0);
  });

  testWidgets('its PENCIL opens the field: the number alone, all of it '
      'selected, nothing beside it — and a submit reaches the owner', (
    tester,
  ) async {
    final seen = await pump(tester);
    await tester.tap(find.byKey(pencil));
    await tester.pump();
    expect(find.byType(InlineNumericField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '100');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
      reason: 'the first keystroke replaces the number',
    );
    expect(find.text('%'), findsNothing, reason: 'its unit is gone with it');

    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.edits, ['250']);
    expect(seen.starts, 1, reason: 'a typed commit is an operation');
    expect(find.byType(InlineNumericField), findsNothing);
    expect(seen.deltas, isEmpty);
  });

  testWidgets('a box\'s ± step it a unit, each step one whole operation', (
    tester,
  ) async {
    final seen = await pump(tester, box: true);
    await tester.tap(find.byKey(const ValueKey<String>('zoom-step-up')));
    await tester.pump();
    expect(seen.deltas, [1]);
    expect((seen.starts, seen.ends), (1, 1));
    await tester.tap(find.byKey(const ValueKey<String>('zoom-step-down')));
    await tester.pump();
    expect(seen.deltas, [1, -1]);
    expect((seen.starts, seen.ends), (2, 2));
  });

  testWidgets('a bare readout carries no ± unless its host asks — the canvas '
      'bar turns the view with its own ⟲ ⟳', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey<String>('zoom-step-up')), findsNothing);
    expect(find.byKey(pencil), findsOneWidget);
  });

  testWidgets('a notch of the wheel over the face is a step: up is +1', (
    tester,
  ) async {
    final seen = await pump(tester);
    final over = tester.getCenter(find.byKey(face));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: over, scrollDelta: const Offset(0, -20)),
    );
    await tester.pump();
    expect(seen.deltas, [1]);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: over, scrollDelta: const Offset(0, 20)),
    );
    await tester.pump();
    expect(seen.deltas, [1, -1]);
    expect((seen.starts, seen.ends), (2, 2));
  });

  testWidgets('🚨on a row whose buttons act on the PRESS, the face still '
      'scrubs and the pencil opens on the press', (tester) async {
    final seen = await pump(tester, fireOn: PressFire.down);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(face)),
    );
    await tester.pump();
    expect(find.byType(InlineNumericField), findsNothing);
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(seen.deltas.fold(0.0, (a, b) => a + b), 20);

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(pencil)),
    );
    await tester.pump();
    expect(
      find.byType(InlineNumericField),
      findsOneWidget,
      reason: 'a rail row\'s button fires on the press',
    );
    await press.up();
  });

  testWidgets('a scrub says ONCE that it is over, at the release — and a '
      'press that moved nothing says nothing', (tester) async {
    final seen = await pump(tester, fireOn: PressFire.down);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(face)),
    );
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    expect(seen.starts, 1, reason: 'one operation, from its first unit');
    expect(seen.ends, 0, reason: 'not while it runs');
    await gesture.up();
    await tester.pump();
    expect(seen.ends, 1);

    await tester.tap(find.byKey(face));
    await tester.pump();
    expect((seen.starts, seen.ends), (1, 1), reason: 'it scrubbed nothing');
  });

  testWidgets('a TURNED box is the same box on its side: a drag DOWN its '
      'column scrubs it up, and its cursor runs the way its drag does', (
    tester,
  ) async {
    // 🗣️유저 2026-10-11: 「일본어 세로쓰기에서 영어 세로쓰기인데 진짜로
    // 90도눕혀서 쓰는것처럼」 — the x-sheet's lane values.
    final deltas = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 24,
              height: 160,
              child: RotatedBox(
                quarterTurns: 1,
                child: DragValueLabel.box(
                  keyValue: 'line',
                  name: 'X',
                  text: '-1218.00',
                  turned: true,
                  onDragDelta: deltas.add,
                  onEditSubmit: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byKey(const ValueKey<String>('line')));
    expect(box.width, 24, reason: 'a box\'s height, across the column');
    expect(box.height, greaterThan(box.width));
    expect(find.text('X'), findsOneWidget, reason: 'its name, as the rail\'s');
    expect(
      tester.getRect(find.byKey(const ValueKey<String>('line-edit'))).top,
      greaterThanOrEqualTo(box.bottom - 0.01),
      reason: 'its hands after it, down the column',
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: box.center);
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(
      // A test mouse is device 1, whatever its pointer.
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeUpDown,
    );
    await mouse.down(box.center);
    await mouse.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(deltas, isEmpty, reason: 'across the column turns nothing');
    await mouse.moveBy(const Offset(0, 6));
    await tester.pump();
    await mouse.up();
    expect(deltas.fold<double>(0, (sum, units) => sum + units), 6);
  });

  testWidgets('🚨typed in, under the app\'s own theme, a box is ALL field: '
      'no name, no unit, no frame or padding of the field\'s own — its '
      'frame takes the accent and its number stays where it stood', (
    tester,
  ) async {
    // 🗣️유저 2026-10-11: 「직접입력눌렀을때 텍스트편집박스가 너무 작아.
    // 오른쪽에도 이상한 패딩있고 왼쪽에도 X 글자 없애고 최대치로 잡아도
    // 될거같은데. 다른박스 마찬가지 통일」 · 「뒤에 붙은 %나 도같은 단위도
    // 텍스트편집창에서 없도록. 진짜 박스 전면 텍스트로 하고싶은거야」.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: DragValueLabel.box(
                keyValue: 'box',
                name: 'X',
                text: '100.00%',
                onDragDelta: (_) {},
                onEditSubmit: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    // The frame does not move when it is typed in, so it is measured at
    // rest — typed, the box's key goes with the drag it answers.
    final frame = tester.getRect(find.byKey(const ValueKey<String>('box')));
    final restingRight = tester.getRect(find.text('100.00%')).right;
    await tester.tap(find.byKey(const ValueKey<String>('box-edit')));
    await tester.pump();

    expect(find.text('X'), findsNothing, reason: 'its name steps aside');
    expect(find.text('%'), findsNothing, reason: 'its unit too');
    final typed = tester.getRect(find.byType(EditableText));
    expect(typed.left, closeTo(frame.left + FieldSlider.inset, 0.01));
    expect(typed.right, closeTo(frame.right - FieldSlider.inset, 0.01));
    expect(
      typed.right,
      closeTo(restingRight, 0.01),
      reason: 'the number does not move when it is typed in',
    );
    final decoration = tester
        .widget<InputDecorator>(find.byType(InputDecorator))
        .decoration;
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.contentPadding, EdgeInsets.zero);
    final frames = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.byType(EditableText),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((decorated) => decorated.decoration);
    expect(
      frames,
      contains(
        FieldSlider.frameOf(
          FieldSlider.defaultHeight,
          enabled: true,
          typed: true,
        ),
      ),
    );
    expect(
      frames
          .whereType<ShapeDecoration>()
          .map((frame) => frame.shape)
          .whereType<OutlinedBorder>()
          .map((shape) => shape.side.color),
      contains(AppColors.accent),
      reason: 'the frame is the field\'s now, in the accent',
    );
  });

  testWidgets('disabled, it keeps its place: a drag reports nothing, its '
      'pencil opens no field, and the text wears the disabled foreground', (
    tester,
  ) async {
    final seen = await pump(tester, enabled: false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(face)),
    );
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(seen.deltas, isEmpty);

    await tester.tap(find.byKey(pencil), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(InlineNumericField), findsNothing);
    expect(seen.edits, isEmpty);

    final scheme = Theme.of(tester.element(find.text('100%'))).colorScheme;
    expect(
      tester.widget<Text>(find.text('100%')).style?.color,
      scheme.onSurface.withValues(alpha: 0.38),
      reason: 'the disabled foreground every icon button wears',
    );
  });

  testWidgets('a NARROW readout typed in is all field: the number across '
      'its whole width, nothing beside it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DragValueLabel(
              keyValue: 'page',
              text: '3 / 1200',
              width: 30,
              textStyle: const TextStyle(fontSize: 9),
              onDragDelta: (_) {},
              onEditSubmit: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('page-edit')));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'nothing ran past it');
    expect(tester.getSize(find.byType(InlineNumericField)).width, 30);
    expect(find.text(' / 1200'), findsNothing);
  });

  /// 🚨H24 (유저 2026-09-15: 「뷰어쪽 줌 레일스크롤바랑 겹치는거」) — the
  /// label where the dock puts it when a panel is squeezed: at the top of a
  /// list that scrolls. The canvas zoom and angle readouts are this widget.
  Future<({_Seen seen, ScrollController scroll})> pumpInList(
    WidgetTester tester,
  ) async {
    final seen = _Seen();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        // A Scaffold: the inline field is a TextField and needs a Material
        // above it, or a press that DID open the field fails the test.
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    DragValueLabel(
                      keyValue: 'zoom',
                      text: '100%',
                      onDragDelta: seen.deltas.add,
                      onEditSubmit: seen.edits.add,
                      unitsPerPixel: 1,
                      width: 64,
                    ),
                    const SizedBox(
                      key: ValueKey<String>('below-the-label'),
                      width: 300,
                      height: 600,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (seen: seen, scroll: scroll);
  }

  Future<void> dragUp(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind,
  ) async {
    final gesture = await tester.startGesture(from, kind: kind);
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('inside a list that scrolls', () {
    testWidgets('⛔fixture premise: a drag off the label scrolls the list', (
      tester,
    ) async {
      final (:seen, :scroll) = await pumpInList(tester);
      await dragUp(
        tester,
        tester.getTopLeft(
              find.byKey(const ValueKey<String>('below-the-label')),
            ) +
            const Offset(150, 60),
        PointerDeviceKind.touch,
      );
      expect(scroll.offset, greaterThan(0));
      expect(seen.deltas, isEmpty);
    });

    for (final kind in const [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.mouse,
    ]) {
      testWidgets('a ${kind.name} drag that starts on the face and runs '
          'straight up is the face\'s — the list never moves', (tester) async {
        final (:seen, :scroll) = await pumpInList(tester);
        await dragUp(tester, tester.getCenter(find.byKey(face)), kind);
        expect(scroll.offset, 0);
        expect(seen.deltas, isEmpty, reason: 'up is not along the number');
        expect(find.byType(InlineNumericField), findsNothing);
      });
    }

    testWidgets('a pen press that wobbles on the PENCIL still opens the '
        'field — a button fires on the release inside it', (tester) async {
      final (:seen, scroll: _) = await pumpInList(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(pencil)),
        kind: PointerDeviceKind.stylus,
      );
      for (final step in const [Offset(2, 1), Offset(3, 0), Offset(-2, 1)]) {
        await gesture.moveBy(step);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(find.byType(InlineNumericField), findsOneWidget);
      expect(seen.deltas, isEmpty);
    });
  });
}
