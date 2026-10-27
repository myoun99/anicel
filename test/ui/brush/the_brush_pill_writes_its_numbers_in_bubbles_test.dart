// 🗣️I-135 (유저 2026-10-27): 「브러시 사이즈 위젯 알약모드일때, 역시 사이즈
// 글자가 세로면 알기힘듬. 그러니 그냥 텍스트 독립시키자. 슬라이더 막대엔
// 텍스트 없애고, 연필버튼도 여기선 대체되니 없애고. 그러고 막대 옆에 <20.0
// 이런식으로 약간 말풍선컨셉? 으로 슬라이더 값이 위치한곳에 텍스트 위젯
// 넣도록. 이 위젯은 슬라이더 값 위치한곳 따라다님. … 이 위젯은 버튼이라
// 클릭가능. 클릭하면 연필버튼이랑 똑같은 동작으로 텍스트 직접 편집 … 그냥
// 고정크기로하자(…2000.0 의 길이…텍스트 중앙정렬). 그러고 불투명도도 그
// 고정크기로 통일」.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxParentData;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/brush_value_group.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/text/text_measure.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/disabled_ink.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/canvas/canvas_capsule.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/number_pad_keyboard.dart';

const sides = ['size', 'opacity'];

Finder bar(String side) =>
    find.byKey(ValueKey<String>('brush-pill-$side-bar'));

Finder bubble(String side) =>
    find.byKey(ValueKey<String>('brush-pill-$side-bubble'));

Finder trackOf(String side) =>
    find.descendant(of: bar(side), matching: find.byType(FieldSliderTrack));

Finder wordsOf(String side) =>
    find.descendant(of: bubble(side), matching: find.byType(Text));

final typing = find.byKey(const ValueKey<String>('field-slider-type-input'));

/// The number a bubble writes, as the number pad its press opens shows it
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
  testWidgets('the pill\'s bars write nothing and wear no pencil — their ± '
      'stay — and their numbers stand in bubbles beside them, the size '
      'without its px and the opacity without its %; the strip\'s bars '
      'still write their own, units and pencils and all', (tester) async {
    final brushTool = await pumpPill(tester);

    for (final side in sides) {
      for (final writing in [find.byType(Text), find.byType(VerticalWritingText)]) {
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
  });

  testWidgets('a bubble\'s point stands at its value\'s place on the bar, '
      'just clear of the pill, and follows it there — moved by its layer, '
      'its box left where the lane laid it', (tester) async {
    final brushTool = await pumpPill(tester);
    final pill = tester.getRect(capsule);
    Offset laidAt(String side) =>
        (tester
                    .renderObject<RenderBox>(
                      find.ancestor(
                        of: bubble(side),
                        matching: find.byType(CompositedTransformFollower),
                      ),
                    )
                    .parentData!
                as BoxParentData)
            .offset;
    final laid = {for (final side in sides) side: laidAt(side)};
    double sizeAlong(double size) =>
        math.log(size / BrushToolState.minSize) /
        math.log(BrushToolState.maxSize / BrushToolState.minSize);

    for (final (size, opacity) in [
      (BrushToolState.minSize, 0.0),
      (10.0, 0.37),
      (BrushToolState.maxSize, 1.0),
    ]) {
      brushTool.value = brushTool.value
          .withActiveSize(size)
          .withActiveOpacity(opacity);
      await tester.pump();
      for (final (side, t) in [('size', sizeAlong(size)), ('opacity', opacity)]) {
        final track = tester.getRect(trackOf(side));
        final body = tester.getRect(bubble(side));
        expect(
          body.center.dy,
          closeTo(track.bottom - t * track.height, 0.01),
          reason: '$side at $t of its track',
        );
        expect(
          body.left - FieldSliderValueBubble.point,
          closeTo(pill.right + 2, 0.01),
          reason: '$side: its point a breath past the pill',
        );
        expect(laidAt(side), laid[side], reason: side);
      }
    }
  });

  testWidgets('the two bubbles are one fixed size — 「2000.0」 whole and the '
      'ring\'s room either side — and say their number in its middle, '
      'whatever the number', (tester) async {
    final brushTool = await pumpPill(tester);
    final context = tester.element(bubble('size'));
    final fixed = Size(
      TextMeasure(
            context,
            FieldSlider.valueStyleIn(context),
          ).size('2000.0').width.ceilToDouble() +
          CanvasCapsule.barPillEnd * 2,
      BrushValueBars.stoodThicknessIn(context),
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
        expect(tester.getSize(bubble(side)), fixed, reason: '$side, $size');
        expect(
          tester.getCenter(wordsOf(side)).dx,
          closeTo(tester.getCenter(bubble(side)).dx, 0.5),
          reason: '$side: centred',
        );
      }
    }
    expect(tester.widget<Text>(wordsOf('size')).data, '2000.0');
  });

  testWidgets('a bubble\'s point is its body\'s ground, ringed as the body '
      'is, its tip at the middle of the bubble\'s left edge', (tester) async {
    await pumpPill(tester);
    final ground = CanvasCapsule.groundIn(tester.element(bubble('size')));
    for (final side in sides) {
      final face = find
          .ancestor(
            of: bubble(side),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint && widget.foregroundPainter != null,
            ),
          )
          .first;
      final point = tester.widget<CustomPaint>(face).foregroundPainter!;
      final size = tester.getSize(face);
      final middle = size.height / 2;
      expect(
        (Canvas canvas) => point.paint(canvas, size),
        paints
          ..path(
            color: ground,
            includes: [Offset(1, middle)],
            excludes: [Offset(1, middle - 3), Offset(1, middle + 3)],
          )
          ..path(color: CanvasCapsule.ring, style: PaintingStyle.stroke),
        reason: side,
      );
    }
  });

  testWidgets('a press on a bubble opens its bar\'s number pad, as its '
      'pencil did, with the bubble standing where it stood; the typed '
      'number lands, and the bubble says it', (tester) async {
    final brushTool = await pumpPill(tester);
    final before = tester.getRect(bubble('size'));
    for (final side in sides) {
      expect(
        find.descendant(
          of: bubble(side),
          matching: find.tooltipSaying(AppText.strings.valueTypeIn),
        ),
        findsOneWidget,
        reason: '$side: it says what its pencil said',
      );
    }

    await tester.tap(bubble('size'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'size'));
    expect(tester.getRect(bubble('size')), before, reason: 'it stays');
    await openThePadsKeyboard(tester);
    await tester.enterText(typing, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(brushTool.value.activeSize, closeTo(25, 1e-9));
    expect(tester.widget<Text>(wordsOf('size')).data, '25.0');

    await tester.tap(bubble('opacity'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'opacity'));
  });

  testWidgets('a tool that reads no size dims the size\'s bubble, and a '
      'press there types nothing — the opacity\'s still answers', (
    tester,
  ) async {
    final brushTool = await pumpPill(tester);
    brushTool.value = brushTool.value.copyWith(tool: CanvasTool.fill);
    await tester.pump();
    expect(brushTool.value.supports(ToolParameter.size), isFalse);

    final ground = CanvasCapsule.groundIn(tester.element(bubble('size')));
    Color? inkOf(String side) =>
        tester.widget<Text>(wordsOf(side)).style?.color;
    expect(
      inkOf('size'),
      dimmedIfDisabled(textOnColor(ground), enabled: false),
    );
    expect(inkOf('opacity'), textOnColor(ground));

    await tester.tap(bubble('size'));
    await tester.pumpAndSettle();
    expect(theNumberPadsNumber, findsNothing);
    await tester.tap(bubble('opacity'));
    await tester.pumpAndSettle();
    expect(padShows(tester), numberOf(tester, 'opacity'));
  });

  testWidgets('the lane beside the pill keeps no press but its bubbles\' — '
      'the drawing under the rest of it still takes the pen', (tester) async {
    final floor = <Offset>[];
    await pumpPill(tester, floor: floor);
    final pill = tester.getRect(capsule);
    final sizeBubble = tester.getRect(bubble('size'));
    // Beside the pill's head, where no bubble stands.
    final empty = Offset(sizeBubble.center.dx, pill.top + 6);
    expect(
      sizeBubble.top,
      greaterThan(empty.dy + 10),
      reason: '⛔premise: no bubble there',
    );

    await tester.tapAt(empty);
    expect(floor, [empty]);
    floor.clear();
    await tester.tap(bubble('size'));
    expect(floor, isEmpty, reason: 'a bubble keeps its press');
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
    final track =
        stood
            .map((bar) => bar.narrowestIn(context) - FieldSlider.handsReach)
            .reduce(math.max)
            .ceilToDouble();

    for (final side in sides) {
      expect(tester.getSize(trackOf(side)).height, track, reason: side);
      expect(
        tester.getSize(bar(side)).height,
        track + FieldSlider.bubbleHandsReach,
        reason: side,
      );
    }
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('brush-tool-blend-menu-button')))
          .height,
      track,
    );
  });
}
