// 🗣️I-135 (유저 2026-10-27): 「브러시 사이즈 위젯 알약모드일때, 역시 사이즈
// 글자가 세로면 알기힘듬. 그러니 그냥 텍스트 독립시키자. 슬라이더 막대엔
// 텍스트 없애고, 연필버튼도 여기선 대체되니 없애고. … 이 위젯은 버튼이라
// 클릭가능. 클릭하면 연필버튼이랑 똑같은 동작으로 텍스트 직접 편집 … 그냥
// 고정크기로하자(…2000.0 의 길이…텍스트 중앙정렬). 그러고 불투명도도 그
// 고정크기로 통일」 — then, the bubbles beside the bars taking 「생각보다 너무
// 캔버스 좌우공간을」: 「이 시스템 없애고 그냥 해당하는 막대 슬라이더 위에 이
// 텍스트 두자. 물론 다 안들어가니 최대한 텍스트쪽 위젯 컴팩트하게 하고」, and
// of the sheet's three sizes (I-135-Q1): 「a로가자」 — 8, the pill 37 across.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/brush_value_group.dart';
import 'package:anicel/src/ui/canvas/canvas_capsule.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/text/text_measure.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/disabled_ink.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/number_pad_keyboard.dart';

const sides = ['size', 'opacity'];

Finder bar(String side) =>
    find.byKey(ValueKey<String>('brush-pill-$side-bar'));

Finder readout(String side) =>
    find.byKey(ValueKey<String>('brush-pill-$side-readout'));

Finder trackOf(String side) =>
    find.descendant(of: bar(side), matching: find.byType(FieldSliderTrack));

Finder wordsOf(String side) =>
    find.descendant(of: readout(side), matching: find.byType(Text));

final typing = find.byKey(const ValueKey<String>('field-slider-type-input'));

/// The number a readout writes, as the number pad its press opens shows it
/// (I-134): the number alone ([readoutParts]).
String numberOf(WidgetTester tester, String side) =>
    readoutParts(tester.widget<Text>(wordsOf(side)).data!).single.number;

/// What the open number pad shows at its top.
String? padShows(WidgetTester tester) =>
    tester.widget<Text>(theNumberPadsNumber).data;

final capsule = find.byKey(const ValueKey<String>('canvas-brush-pill'));

/// The pill alone, over a floor that hears what the pill passes on.
Future<ValueNotifier<BrushToolState>> pumpPill(
  WidgetTester tester, {
  List<Offset>? floor,
}) async {
  final brushTool = ValueNotifier(BrushToolState.defaults);
  addTearDown(brushTool.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => floor?.add(event.position),
              ),
            ),
            Center(child: BrushValuesPill(brushTool: brushTool)),
          ],
        ),
      ),
    ),
  );
  return brushTool;
}

void main() {
  // In the face the app wears: the pill is as wide as its numbers, and the
  // test font's squares run wider than any number in it.
  setUpAll(loadTheAppFaces);

  testWidgets('in the app\'s face the pill stands 37 across where it stood '
      '28 — 「2000.0」 at 8 whole in readouts 35 across — as I-135-Q1 took '
      'it (「a로가자」)', (tester) async {
    await pumpPill(tester);
    expect(tester.getSize(capsule).width, 37);
    for (final side in sides) {
      expect(tester.getSize(readout(side)).width, 35, reason: side);
    }
  });

  testWidgets('the pill\'s bars write nothing and wear no pencil — their ± '
      'stay — and their numbers stand in readouts, the size without its px '
      'and the opacity without its %; the strip\'s bars still write their '
      'own, units and pencils and all', (tester) async {
    final brushTool = await pumpPill(tester);

    for (final side in sides) {
      for (final writing in [
        find.byType(Text),
        find.byType(VerticalWritingText),
      ]) {
        expect(
          find.descendant(of: bar(side), matching: writing),
          findsNothing,
          reason: '$side: nothing written in the bar',
        );
      }
      expect(
        find.descendant(
          of: bar(side),
          matching: find.byKey(const ValueKey<String>('field-slider-type')),
        ),
        findsNothing,
        reason: '$side: 「연필버튼도 여기선 대체되니 없애고」',
      );
      expect(
        find.descendant(
          of: bar(side),
          matching: find.byKey(const ValueKey<String>('field-slider-step-up')),
        ),
        findsOneWidget,
        reason: '$side: its ± stay',
      );
    }
    String said(String side) => tester.widget<Text>(wordsOf(side)).data!;
    expect(said('size'), matches(RegExp(r'^\d+\.\d$')), reason: 'no px');
    expect(said('opacity'), matches(RegExp(r'^\d+$')), reason: 'no %');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: BrushValueBars(
              brushTool: brushTool,
              widths: BrushValueBars.full,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining(' px'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('field-slider-type')),
      findsNWidgets(2),
    );
    for (final side in sides) {
      expect(readout(side), findsNothing, reason: '$side: the strip\'s own');
    }
  });

  testWidgets('each number stands right above its bar — two pixels over it, '
      'across the pill a pixel in from its ring either side — and stays '
      'there whatever the bar says', (tester) async {
    final brushTool = await pumpPill(tester);
    final pill = tester.getRect(capsule);
    final laid = {
      for (final side in sides) side: tester.getRect(readout(side)),
    };
    for (final side in sides) {
      final number = laid[side]!;
      expect(
        tester.getRect(bar(side)).top - number.bottom,
        closeTo(2, 0.01),
        reason: '$side: right above its bar',
      );
      expect(number.left, closeTo(pill.left + 1, 0.01), reason: side);
      expect(number.right, closeTo(pill.right - 1, 0.01), reason: side);
    }
    expect(
      laid['opacity']!.top,
      greaterThan(
        tester
            .getRect(
              find.byKey(const ValueKey<String>('brush-tool-pressure-size')),
            )
            .bottom,
      ),
      reason: 'the opacity\'s number under the size\'s curve',
    );

    for (final (size, opacity) in [
      (BrushToolState.minSize, 0.0),
      (BrushToolState.maxSize, 1.0),
    ]) {
      brushTool.value = brushTool.value
          .withActiveSize(size)
          .withActiveOpacity(opacity);
      await tester.pump();
      for (final side in sides) {
        expect(
          tester.getRect(readout(side)),
          laid[side],
          reason: '$side at $size, $opacity',
        );
      }
    }
  });

  testWidgets('the two readouts are one fixed size — 「2000.0」 whole at 8 and '
      'a pixel either side, as I-135-Q1 took it — and write their number at '
      '8, on a line 8 tall, in their middle, whatever the number', (
    tester,
  ) async {
    final brushTool = await pumpPill(tester);
    final context = tester.element(readout('size'));
    final atEight = FieldSlider.valueStyleIn(
      context,
    )!.copyWith(fontSize: 8, height: 1);
    final fixed = Size(
      TextMeasure(context, atEight).size('2000.0').width.ceilToDouble() + 2,
      12,
    );

    for (final (size, opacity) in [
      (BrushToolState.minSize, 0.0),
      (12.3, 0.5),
      (BrushToolState.maxSize, 1.0),
    ]) {
      brushTool.value = brushTool.value
          .withActiveSize(size)
          .withActiveOpacity(opacity);
      await tester.pump();
      for (final side in sides) {
        expect(tester.getSize(readout(side)), fixed, reason: '$side, $size');
        expect(tester.widget<Text>(wordsOf(side)).style?.fontSize, 8);
        // The line as tall as its letters — not the theme's 1.45, which
        // sinks the digits a pixel and more under the box's middle.
        expect(tester.getSize(wordsOf(side)).height, 8, reason: side);
        final words = tester.getCenter(wordsOf(side));
        final box = tester.getCenter(readout(side));
        expect(words.dx, closeTo(box.dx, 0.5), reason: '$side: centred');
        expect(words.dy, closeTo(box.dy, 0.5), reason: '$side: centred');
      }
    }
    expect(tester.widget<Text>(wordsOf('size')).data, '2000.0');
  });

  testWidgets('a press on a readout opens its bar\'s number pad, as its '
      'pencil did, with the readout standing where it stood; the typed '
      'number lands, and the readout says it', (tester) async {
    final brushTool = await pumpPill(tester);
    final before = tester.getRect(readout('size'));
    for (final side in sides) {
      expect(
        find.descendant(
          of: readout(side),
          matching: find.tooltipSaying(AppText.strings.valueTypeIn),
        ),
        findsOneWidget,
        reason: '$side: it says what its pencil said',
      );
    }

    await tester.tap(readout('size'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'size'));
    expect(tester.getRect(readout('size')), before, reason: 'it stays');
    await openThePadsKeyboard(tester);
    await tester.enterText(typing, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(brushTool.value.activeSize, closeTo(25, 1e-9));
    expect(tester.widget<Text>(wordsOf('size')).data, '25.0');

    await tester.tap(readout('opacity'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'opacity'));
  });

  testWidgets('a tool that reads no size dims the size\'s readout, and a '
      'press there types nothing — the keyboard passes it over — the '
      'opacity\'s still answers', (tester) async {
    final brushTool = await pumpPill(tester);
    brushTool.value = brushTool.value.copyWith(tool: CanvasTool.fill);
    await tester.pump();
    expect(brushTool.value.supports(ToolParameter.size), isFalse);

    // The pill's own ground, which the numbers stand on.
    final ground = Theme.of(tester.element(capsule)).colorScheme.surface;
    Color? inkOf(String side) =>
        tester.widget<Text>(wordsOf(side)).style?.color;
    expect(
      inkOf('size'),
      dimmedIfDisabled(textOnColor(ground), enabled: false),
    );
    expect(inkOf('opacity'), textOnColor(ground));

    await tester.tap(readout('size'));
    await tester.pumpAndSettle();
    expect(theNumberPadsNumber, findsNothing);
    final plate = find.descendant(
      of: readout('size'),
      matching: find.byType(RailPlateButton),
    );
    Focus.of(tester.element(plate)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(theNumberPadsNumber, findsNothing, reason: 'nor the keyboard\'s');
    await tester.tap(readout('opacity'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'opacity'));
  });

  testWidgets('the pill is its capsule and nothing beside it — as wide as '
      'the band it asks of the canvas — and a press just past its edge '
      'reaches the drawing', (tester) async {
    final floor = <Offset>[];
    await pumpPill(tester, floor: floor);
    final pill = tester.getRect(capsule);
    expect(tester.getRect(find.byType(BrushValuesPill)), pill);
    expect(BrushValuesPill.widthIn(tester.element(capsule)), pill.width);

    final past = Offset(pill.right + 2, tester.getCenter(readout('size')).dy);
    await tester.tapAt(past);
    expect(floor, [past]);
  });

  testWidgets('the pill keeps the view pill\'s room inside both its ends', (
    tester,
  ) async {
    await pumpPill(tester);
    final pill = tester.getRect(capsule);
    expect(
      tester.getRect(find.byType(BrushBlendModeControl)).top - pill.top,
      CanvasCapsule.barPillEnd,
    );
    expect(
      pill.bottom - tester.getRect(find.byType(BrushValueBars)).bottom,
      CanvasCapsule.barPillEnd,
    );
  });

  testWidgets('the pill\'s tracks keep the length the numbers gave them '
      'while they stood in them, a glyph to a cell — the ± alone under '
      'them, and the blend as long as they are', (tester) async {
    await pumpPill(tester);
    final context = tester.element(capsule);
    final thickness = BrushValueBars.stoodThicknessIn(context);
    // The bars as they stood their numbers until I-135 (F-460).
    final stood = [
      FieldSlider(
        label: AppText.strings.brSize,
        nameInside: false,
        value: 1,
        min: BrushToolState.minSize,
        max: BrushToolState.maxSize,
        scale: FieldSliderScale.exponential,
        height: thickness,
        axis: Axis.vertical,
        upright: true,
        onChanged: null,
      ),
      FieldSlider.opacity(
        label: AppText.strings.brOpacity,
        nameInside: false,
        value: 1,
        height: thickness,
        axis: Axis.vertical,
        upright: true,
        onChanged: null,
      ),
    ];
    final track = stood
        .map((bar) => bar.narrowestIn(context) - FieldSlider.handsReach)
        .reduce(math.max)
        .ceilToDouble();

    for (final side in sides) {
      expect(tester.getSize(trackOf(side)).height, track, reason: side);
      expect(
        tester.getSize(bar(side)).height,
        track + FieldSlider.readoutHandsReach,
        reason: side,
      );
    }
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('brush-tool-blend-menu-button')),
          )
          .height,
      track,
    );
  });
}
