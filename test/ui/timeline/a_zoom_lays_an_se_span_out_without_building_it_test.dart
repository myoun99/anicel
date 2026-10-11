import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/dialogue_fit_paint.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

/// 🚨A ZOOM LAYS AN SE SPAN OUT AGAIN; IT DOES NOT BUILD IT AGAIN
/// (zoom-step-lays-out-five-times-the-07-25-count, 10-12): the chip's length
/// is the box's question, asked by the layout and the paint that know the
/// box. A `LayoutBuilder` asked it, so every SE span built its chip, its
/// dialogue and the flex between them again on every zoom step — 100 of
/// each in the 07-25 harness, the most of a step's 498 rebuilds.
void main() {
  const dialogue = 'せりふのテキスト';
  const row = 28.0;

  /// An SE span in a box [width] long, the width moved by [resize] — the
  /// span itself the same instance throughout, as a zoom leaves it.
  Future<void Function(double)> mount(
    WidgetTester tester, {
    required double width,
  }) async {
    var shown = width;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, set) {
                setState = set;
                return SizedBox(
                  width: shown,
                  height: row,
                  child: const SeSpanVisual(
                    axis: Axis.horizontal,
                    frames: 4,
                    dialogue: dialogue,
                    seName: 'ドア',
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return (next) => setState(() => shown = next);
  }

  testWidgets('🚨a new length builds nothing of the span again', (
    tester,
  ) async {
    final resize = await mount(tester, width: 240);
    final rebuilt = <Type>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) =>
        rebuilt.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (final width in [200.0, 120.0, 40.0, 12.0, 240.0]) {
      resize(width);
      await tester.pump();
    }

    expect(rebuilt, isNot(contains(DialogueFitText)));
    expect(
      rebuilt.where((type) => '$type' == '_SeNameBox'),
      isEmpty,
      reason: 'the chip is laid out again, not built again',
    );
    expect(rebuilt, isNot(contains(LayoutBuilder)));
  });

  testWidgets('🚨and the chip still narrows with the box beside the '
      'dialogue — laid out at the length it is given', (tester) async {
    final resize = await mount(tester, width: 400);
    final natural = dialogueNaturalExtent(
      dialogue,
      axis: Axis.horizontal,
      style: dialogueFitStyle(
        tester.element(find.byType(SeSpanVisual)),
        color: Colors.black,
      ),
      maxCrossExtent: row,
    );
    final chip = find.bySemanticsLabel('SE name ドア');

    for (final width in [400.0, 60.0, 20.0, 6.0]) {
      resize(width);
      await tester.pump();
      expect(
        tester.getSize(chip).width,
        closeTo(seNameBoxExtentIn(width, dialogueExtent: natural), 1e-6),
        reason: 'at $width',
      );
      expect(
        tester.getSize(chip).width +
            tester.getSize(find.byType(DialogueFitText)).width,
        closeTo(width, 1e-6),
        reason: 'the dialogue takes the rest, at $width',
      );
    }
  });

  testWidgets('a column grown wider measures its dialogue again — a glyph '
      'standing in it is fitted to the width first', (tester) async {
    var across = 10.0;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, set) {
                setState = set;
                return SizedBox(
                  width: across,
                  height: 60,
                  child: const SeSpanVisual(
                    axis: Axis.vertical,
                    frames: 4,
                    dialogue: dialogue,
                    seName: 'ドア',
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final style = dialogueFitStyle(
      tester.element(find.byType(SeSpanVisual)),
      color: Colors.black,
    );
    final chip = find.bySemanticsLabel('SE name ドア');
    double naturalIn(double width) => dialogueNaturalExtent(
      dialogue,
      axis: Axis.vertical,
      style: style,
      maxCrossExtent: width,
    );
    expect(
      naturalIn(10),
      isNot(naturalIn(40)),
      reason: '⛔premise: the width across moves the dialogue\'s length',
    );

    for (final width in [10.0, 40.0]) {
      setState(() => across = width);
      await tester.pump();
      final natural = naturalIn(width);
      expect(
        tester.getSize(chip).height,
        closeTo(seNameBoxExtentIn(60, dialogueExtent: natural), 1e-6),
        reason: 'a column $width wide',
      );
    }
  });

  testWidgets('a new dialogue at the same length lays the chip out again', (
    tester,
  ) async {
    Widget span(String text) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 60,
            height: row,
            child: SeSpanVisual(
              axis: Axis.horizontal,
              frames: 4,
              dialogue: text,
              seName: 'ドア',
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(span('あ'));
    final chip = find.bySemanticsLabel('SE name ドア');
    final short = tester.getSize(chip).width;

    await tester.pumpWidget(span(dialogue));

    expect(
      tester.getSize(chip).width,
      lessThan(short),
      reason: 'a longer dialogue narrows the chip beside it',
    );
  });

  testWidgets('the chip\'s ground is tinted over the length the box gives '
      'it, painted at that size', (tester) async {
    final resize = await mount(tester, width: 400);
    resize(20);
    await tester.pump();
    final ground = find
        .descendant(
          of: find.byType(SeSpanVisual),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        )
        .first;
    final box = tester.renderObject<RenderCustomPaint>(ground);
    final chip = tester.getSize(find.bySemanticsLabel('SE name ドア'));

    final spy = _RectSpy();
    box.painter!.paint(spy, box.size);

    expect(spy.rects.single.width, closeTo(chip.width, 1e-6));
  });
}

/// The rectangles a painter lays.
class _RectSpy implements Canvas {
  final rects = <Rect>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void noSuchMethod(Invocation invocation) {}
}
