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

  /// An SE span in a box [width] long, [left] in from the screen's edge
  /// with [framesFreeBefore] free before it, the width moved by [resize] —
  /// the span itself the same instance throughout, as a zoom leaves it.
  Future<void Function(double)> mount(
    WidgetTester tester, {
    required double width,
    int frames = 4,
    String words = dialogue,
    int framesFreeBefore = 0,
    double left = 0,
  }) async {
    var shown = width;
    late StateSetter setState;
    final span = SeSpanVisual(
      axis: Axis.horizontal,
      frames: frames,
      dialogue: words,
      seName: 'ドア',
      framesFreeBefore: framesFreeBefore,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: left),
              child: StatefulBuilder(
                builder: (context, set) {
                  setState = set;
                  return SizedBox(width: shown, height: row, child: span);
                },
              ),
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

  testWidgets('🚨and the chip still narrows with the words — laid out at the '
      'length it is given', (tester) async {
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
      final place = seNameChipPlace(
        width,
        dialogueExtent: natural,
        roomBefore: 0,
      );
      expect(place.outside, isFalse, reason: '⛔premise: no room before it');
      expect(tester.getSize(chip).width, closeTo(place.chip, 1e-6));
      expect(
        tester.getTopLeft(find.byType(DialogueFitText)).dx,
        closeTo(0, 1e-6),
        reason: 'the words begin on the block\'s first frame, at $width',
      );
      expect(
        tester.getSize(find.byType(DialogueFitText)).width,
        closeTo(width, 1e-6),
        reason: 'and run to its end, at $width',
      );
      expect(
        tester.getCenter(chip).dy,
        closeTo(tester.getCenter(find.byType(SeSpanVisual)).dy, 1e-6),
        reason: 'the chip stands in the middle across, as the flex had it',
      );
    }
  });

  // 🗣️F-358 (유저 2026-10-19): 「대사영역 바로앞. 즉 블록 앞부분 왼쪽에
  // 이름두자. 블록 밖으로 나가게되는거지. … 공간없으면 지금처럼 블록안에
  // 넣는데 대사랑 완전겹치는거 감수」 — and 「이름칸이 통째로 들어가면 밖,
  // 아니면 안(화면 픽셀로)」 (F-358-Q2).
  testWidgets('🚨with room before its block, the chip stands just before it '
      'and the words keep the whole block — a zoom that takes the room away '
      'lays it in, building nothing', (tester) async {
    // Ten frames of 10, two of them free before: room for the chip's 16.
    final resize = await mount(
      tester,
      width: 100,
      frames: 10,
      words: 'あい',
      framesFreeBefore: 2,
      left: 40,
    );
    final chip = find.bySemanticsLabel('SE name ドア');
    final words = find.byType(DialogueFitText);
    expect(tester.getRect(chip).width, seNameBoxExtent);
    expect(tester.getRect(chip).right, closeTo(40, 1e-6));
    expect(tester.getRect(words).left, closeTo(40, 1e-6));
    expect(tester.getRect(words).width, closeTo(100, 1e-6));

    final rebuilt = <Type>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) =>
        rebuilt.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    // Frames of 7: two of them hold 14, short of the chip.
    resize(70);
    await tester.pump();
    expect(tester.getRect(chip).left, closeTo(40, 1e-6), reason: 'in');
    expect(tester.getRect(words).left, closeTo(40, 1e-6));
    expect(rebuilt.where((type) => '$type' == '_SeNameBox'), isEmpty);
  });

  testWidgets('the block before it moved away: the room is asked again, and '
      'the chip goes out', (tester) async {
    Widget at(int framesFreeBefore) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 40),
            child: SizedBox(
              width: 100,
              height: row,
              child: SeSpanVisual(
                axis: Axis.horizontal,
                frames: 10,
                dialogue: 'あい',
                seName: 'ドア',
                framesFreeBefore: framesFreeBefore,
              ),
            ),
          ),
        ),
      ),
    );
    final chip = find.bySemanticsLabel('SE name ドア');
    await tester.pumpWidget(at(0));
    expect(tester.getRect(chip).left, closeTo(40, 1e-6), reason: '⛔premise');

    await tester.pumpWidget(at(2));
    expect(tester.getRect(chip).right, closeTo(40, 1e-6));
  });

  testWidgets('a block shorter than the chip, with no room before it, gives '
      'the chip all of itself and no more', (tester) async {
    // No words to narrow it: the chip would be its whole 16.
    await mount(tester, width: 10, frames: 1, words: '');
    final chip = tester.getRect(find.bySemanticsLabel('SE name ドア'));
    expect(chip.left, closeTo(0, 1e-6));
    expect(chip.width, closeTo(10, 1e-6), reason: 'the block\'s end');
  });

  testWidgets('with no room before its block, the chip lies over the words\' '
      'head and paints over them', (tester) async {
    await mount(tester, width: 100, frames: 10, words: 'あい');
    final chip = tester.getRect(find.bySemanticsLabel('SE name ドア'));
    final words = tester.getRect(find.byType(DialogueFitText));
    expect(chip.width, seNameBoxExtent);
    expect([chip.left, words.left], [0, 0], reason: 'both at the head');
    expect(chip.overlaps(words), isTrue, reason: '⛔premise: they meet');
    expect(
      [
        for (final slot in tester.widgetList<LayoutId>(
          find.descendant(
            of: find.byType(SeSpanVisual),
            matching: find.byType(LayoutId),
          ),
        ))
          if (slot.child is DialogueFitText) 'words' else 'chip',
      ],
      ['words', 'chip'],
      reason: 'a layout paints its children in order: the name is what '
          'stays legible (F-358-Q1 「이름은 최대한 지금처럼 잘 보이고」)',
    );
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
    double chipIn(double width) => seNameChipPlace(
      60,
      dialogueExtent: naturalIn(width),
      roomBefore: 0,
    ).chip;
    expect(
      chipIn(10),
      isNot(closeTo(chipIn(40), 1e-6)),
      reason: '⛔premise: the width across moves the dialogue\'s length, '
          'and with it the chip',
    );

    for (final width in [10.0, 40.0]) {
      setState(() => across = width);
      await tester.pump();
      expect(
        tester.getSize(chip).height,
        closeTo(chipIn(width), 1e-6),
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
      reason: 'a longer dialogue narrows the chip with it',
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
