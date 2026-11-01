// 🗣️F-530 (유저 2026-11-01): 「텍스트가 잘려서 ...으로 표시되는 위젯,
// 기본적으로 표시될땐 툴팁으로 전 문장 표시하도록. 특히 fx의 카메라렌즈흐림의
// 키에서 발견」.
//
// Every cut word in the app says the whole of itself in the one tooltip
// window, by the one rule of nesting: a line across ([EllipsisText]), a
// column down ([VerticalWritingText]), and both forks of [readableText]. What
// keeps a new one from going round this is
// `test/architecture/every_cut_word_says_itself_test.dart`.
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/ellipsis_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

const long = 'A sentence far too long for the room it is given';

void main() {
  tearDown(SummonedTooltip.dismiss);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(finder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return mouse;
  }

  group('a line across', () {
    testWidgets('that is cut says itself whole on a hover', (tester) async {
      await pump(
        tester,
        const SizedBox(width: 60, child: EllipsisText(long, maxLines: 1)),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, long);
    });

    testWidgets('that fits says nothing', (tester) async {
      await pump(
        tester,
        const SizedBox(width: 600, child: EllipsisText('Short', maxLines: 1)),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    for (final (name, line) in const [
      ('no line limit', EllipsisText(long)),
      ('no wrapping', EllipsisText(long, maxLines: 1, softWrap: false)),
      ('two lines', EllipsisText('$long $long $long', maxLines: 2)),
    ]) {
      testWidgets('is cut however it is written: $name', (tester) async {
        await pump(tester, SizedBox(width: 60, child: line));
        await hover(tester, find.byType(EllipsisText));
        expect(SummonedTooltip.debugShownMessage, line.data);
      });
    }

    testWidgets('that its room grew around says nothing any more', (
      tester,
    ) async {
      final width = ValueNotifier<double>(60);
      addTearDown(width.dispose);
      await pump(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (context, value, _) => SizedBox(
            width: value,
            child: const EllipsisText(long, maxLines: 1),
          ),
        ),
      );
      width.value = 780;
      await tester.pump();
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('cut by its caller says what it was cut from, however wide '
        'its room', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 600,
          child: EllipsisText('First…', whole: 'First\nSecond', maxLines: 1),
        ),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, 'First\nSecond');
    });

    testWidgets('given what it shows as what it was cut from is not cut', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          width: 600,
          child: EllipsisText('Short', whole: 'Short', maxLines: 1),
        ),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('says what it says now, not what it was built with', (
      tester,
    ) async {
      Widget line(String words, {String? whole}) => SizedBox(
        width: 60,
        child: EllipsisText(words, whole: whole, maxLines: 1),
      );
      await pump(tester, line(long));
      await pump(tester, line('$long, and more'));
      final mouse = await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, '$long, and more');
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      SummonedTooltip.dismiss();
      await tester.pump(const Duration(seconds: 1));

      await pump(tester, line('Hi', whole: 'Hi'));
      await pump(tester, line('Hi', whole: 'Hi there'));
      await mouse.moveTo(tester.getCenter(find.byType(EllipsisText)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(SummonedTooltip.debugShownMessage, 'Hi there');
    });

    testWidgets('opens on a long press for a hand that cannot hover', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(width: 60, child: EllipsisText(long, maxLines: 1)),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.byType(EllipsisText)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(SummonedTooltip.debugShownMessage, long);
      await press.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('that fits takes no long press from what it stands in', (
      tester,
    ) async {
      var held = 0;
      await pump(
        tester,
        GestureDetector(
          onLongPress: () => held++,
          child: const SizedBox(
            width: 600,
            child: EllipsisText('Short', maxLines: 1),
          ),
        ),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.byType(EllipsisText)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await press.up();
      await tester.pump();
      expect(held, 1);
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('is one box: the paragraph, with nothing around it', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(width: 60, child: EllipsisText(long, maxLines: 1)),
      );
      expect(
        tester.renderObject(find.byType(EllipsisText)),
        isA<RenderParagraph>(),
      );
      expect(find.text(long), findsOneWidget);
      expect(tester.widget<Text>(find.text(long)).maxLines, 1);
    });
  });

  group('inside a tooltip of its own', () {
    Widget around(String words, double width) => AppTooltip(
      message: 'What the button does',
      child: SizedBox(
        width: width,
        height: 40,
        child: EllipsisText(words, maxLines: 1),
      ),
    );

    testWidgets('a word that fits leaves the tooltip around it to answer', (
      tester,
    ) async {
      await pump(tester, around('Short', 600));
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, 'What the button does');
    });

    testWidgets('a cut word answers: the innermost tooltip does', (
      tester,
    ) async {
      await pump(tester, around(long, 60));
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, long);
    });
  });

  group('a column down', () {
    Widget column(
      String text, {
      required double height,
      VerticalTextOverflow overflow = VerticalTextOverflow.ellipsis,
    }) => SizedBox(
      width: 20,
      height: height,
      child: VerticalWritingText(
        text: text,
        style: const TextStyle(fontSize: 12),
        overflow: overflow,
      ),
    );

    testWidgets('that is cut says itself whole', (tester) async {
      await pump(tester, column('가나다라마바사아자차', height: 40));
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugShownMessage, '가나다라마바사아자차');
    });

    testWidgets('that fits says nothing, to its last slot', (tester) async {
      await pump(tester, column('가나다', height: 3 * 12 * 1.15));
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('that packs shows it all, and says nothing', (tester) async {
      await pump(
        tester,
        column(
          '가나다라마바사아자차',
          height: 40,
          overflow: VerticalTextOverflow.pack,
        ),
      );
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('its bar\'s insets are off its run', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 20,
          height: 3 * 12 * 1.15,
          child: VerticalWritingText(
            text: '가나다',
            style: TextStyle(fontSize: 12),
            endInset: 4,
          ),
        ),
      );
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugShownMessage, '가나다');
    });

    testWidgets('reads its slots at the size the text scale set', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Center(child: column('가나다', height: 3 * 12 * 1.15)),
            ),
          ),
        ),
      );
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugShownMessage, '가나다');
    });

    testWidgets('opens on a long press too', (tester) async {
      await pump(tester, column('가나다라마바사아자차', height: 40));
      final press = await tester.startGesture(
        tester.getCenter(find.byType(VerticalWritingText)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(SummonedTooltip.debugShownMessage, '가나다라마바사아자차');
      await press.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('that fits leaves the tooltip around it to answer', (
      tester,
    ) async {
      await pump(
        tester,
        AppTooltip(
          message: 'Around it',
          child: column('가나다', height: 80),
        ),
      );
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugShownMessage, 'Around it');
    });
  });

  group('the words a person reads, by the axis', () {
    testWidgets('across the strip', (tester) async {
      await pump(
        tester,
        SizedBox(width: 60, child: readableText(Axis.horizontal, long)),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, long);
    });

    testWidgets('down the column', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 28,
          height: 40,
          child: readableText(Axis.vertical, '가나다라마바사아자차'),
        ),
      );
      await hover(tester, find.byType(VerticalWritingText));
      expect(SummonedTooltip.debugShownMessage, '가나다라마바사아자차');
    });
  });

  group('a notice\'s one-line list', () {
    Future<void> notice(WidgetTester tester) => pump(
      tester,
      const SizedBox(
        width: 400,
        child: DetailsDisclosure(
          heading: 'Heading',
          lines: ['first line\nsecond line', 'one line'],
          startsOpen: true,
          oneLineEach: true,
        ),
      ),
    );

    testWidgets('a text cut at its first line says all its lines', (
      tester,
    ) async {
      await notice(tester);
      await hover(tester, find.text('first line…'));
      expect(SummonedTooltip.debugShownMessage, 'first line\nsecond line');
    });

    testWidgets('a text of one line says nothing', (tester) async {
      await notice(tester);
      await hover(tester, find.text('one line'));
      expect(SummonedTooltip.debugTarget, isNull);
    });
  });

  group('the fx lane the user found it on', () {
    final layer = Layer(id: const LayerId('fx'), name: 'S', frames: const []);
    PropertyLaneRow lane(String label) =>
        PropertyLaneRow(laneId: 'lane', label: label, keyMarks: const {});

    Future<void> row(
      WidgetTester tester,
      Axis axis,
      String label, {
      required double along,
    }) => pump(
      tester,
      sizedAlong(
        axis,
        along: along,
        across: 40,
        child: TimelineLaneControlsRow(
          layer: layer,
          lane: lane(label),
          metrics: TimelineGridMetrics.defaults,
          axis: axis,
        ),
      ),
    );

    testWidgets('its name, cut on the rail, says itself whole', (
      tester,
    ) async {
      await row(tester, Axis.horizontal, long, along: 400);
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, long);
    });

    testWidgets('its name, cut down the sheet, says itself whole', (
      tester,
    ) async {
      await row(tester, Axis.vertical, '가나다라마바사아자차', along: 40);
      await hover(tester, find.byType(VerticalWritingText).first);
      expect(SummonedTooltip.debugShownMessage, '가나다라마바사아자차');
    });

    testWidgets('its name, whole on the rail, says nothing', (tester) async {
      await row(tester, Axis.horizontal, 'Roundness', along: 600);
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('a graph\'s guest, cut on its tag that presses go through, '
        'says layer and lane whole', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 120,
          child: LaneGraphGuestTags(
            guests: [(layer: layer, lane: lane(long), reach: null)],
          ),
        ),
      );
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, 'S · $long');
    });
  });

  group('a plate presses go through', () {
    Widget plate({
      required VoidCallback onBeneath,
      required double width,
    }) => SizedBox(
      width: 300,
      height: 100,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBeneath,
            ),
          ),
          Align(
            child: PressesGoThrough(
              child: ColoredBox(
                color: const Color(0xFF000000),
                child: SizedBox(
                  width: width,
                  child: const EllipsisText(long, maxLines: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    testWidgets('a cut word on it says itself on a hover', (tester) async {
      await pump(tester, plate(onBeneath: () {}, width: 60));
      await hover(tester, find.byType(EllipsisText));
      expect(SummonedTooltip.debugShownMessage, long);
    });

    testWidgets('a press on it is what lies beneath\'s', (tester) async {
      var pressed = 0;
      await pump(tester, plate(onBeneath: () => pressed++, width: 60));
      await tester.tap(find.byType(EllipsisText), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 1);
    });
  });
}
