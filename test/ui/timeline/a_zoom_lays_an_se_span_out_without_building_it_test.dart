import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/ui/text/dialogue_fit_paint.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/an_se_row.dart';

/// 🚨A ZOOM LAYS AN SE SPAN OUT AGAIN; IT DOES NOT BUILD IT AGAIN
/// (zoom-step-lays-out-five-times-the-07-25-count, 10-12): the chip's length
/// is the box's question, asked by the layout and the paint that know the
/// box. A `LayoutBuilder` asked it, so every SE span built its chip, its
/// dialogue and the flex between them again on every zoom step — 100 of
/// each in the 07-25 harness, the most of a step's 498 rebuilds.
void main() {
  const dialogue = 'せりふのテキスト';
  const row = 28.0;

  /// The dark ground the spans lie on, as the rows' does, and the boundary
  /// a test reads its pixels through.
  const rowGround = Color(0xFF202124);
  final shot = GlobalKey();

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
    String? name = 'ドア',
    SeLineType? delivery,
    int shownFrom = 0,
  }) async {
    var shown = width;
    late StateSetter setState;
    final span = SeSpanVisual(
      layer: anSeRow(),
      axis: Axis.horizontal,
      frames: frames,
      dialogue: words,
      seName: name,
      delivery: delivery,
      shownFrom: shownFrom,
      framesFreeBefore: framesFreeBefore,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: rowGround,
          body: RepaintBoundary(
            key: shot,
            child: Align(
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
      ),
    );
    return (next) => setState(() => shown = next);
  }

  /// The pixels painted over [rect], at one pixel a logical pixel.
  Future<List<Color>> pixelsOver(WidgetTester tester, Rect rect) async {
    final colors = <Color>[];
    await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData())!;
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
        for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
          final at = (y * image.width + x) * 4;
          colors.add(
            Color.fromARGB(
              255,
              bytes.getUint8(at),
              bytes.getUint8(at + 1),
              bytes.getUint8(at + 2),
            ),
          );
        }
      }
      image.dispose();
    });
    return colors;
  }

  bool white(Color color) =>
      [color.r, color.g, color.b].every((channel) => channel > 0.94);

  /// A pixel with a hue of its own — the accent's tint, not the grey of the
  /// ground, the ink or what lies between them.
  bool tinted(Color color) {
    final channels = [color.r, color.g, color.b];
    return channels.reduce(math.max) - channels.reduce(math.min) > 0.06;
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
      rebuilt.where((type) => '$type' == '_SeHeadWord'),
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
    expect(rebuilt.where((type) => '$type' == '_SeHeadWord'), isEmpty);
  });

  // 🗣️F-444 (유저 2026-10-23): 「배경 바탕색 삭제하고, 심플하게 하얀색 텍스트
  // 고정으로 텍스트만 두도록 … 만약 공간 부족해서 이름이 블록안으로 들어가는
  // 상황에선 지금이랑 변함없이」.
  testWidgets('🚨just before its block the name is white on the row, with no '
      'ground; a zoom that lays it in writes it on the tint again — and out '
      'again — building nothing', (tester) async {
    final resize = await mount(
      tester,
      width: 100,
      frames: 10,
      words: 'あい',
      framesFreeBefore: 2,
      left: 40,
    );
    final chip = find.bySemanticsLabel('SE name ドア');
    final rebuilt = <Type>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) =>
        rebuilt.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    Future<void> expectOut() async {
      final out = tester.getRect(chip);
      expect(out.right, closeTo(40, 1e-6), reason: '⛔전제');
      final pixels = await pixelsOver(tester, out);
      expect(pixels.where(white), isNotEmpty, reason: 'its name, in white');
      expect(pixels.where(tinted), isEmpty, reason: 'on no ground');
      final head = await pixelsOver(tester, out.shift(Offset(out.width, 0)));
      expect(head.where(tinted), isEmpty, reason: 'nor a tint left behind');
    }

    await expectOut();

    resize(70);
    await tester.pump();
    expect(tester.getRect(chip).left, closeTo(40, 1e-6), reason: '⛔전제: in');
    final on = await pixelsOver(tester, tester.getRect(chip));
    expect(on.where(tinted), isNotEmpty, reason: 'the tint, as it was');
    expect(on.where(white), isEmpty, reason: 'and the block\'s ink on it');

    resize(100);
    await tester.pump();
    await expectOut();
    expect(rebuilt.where((type) => '$type' == '_SeHeadWord'), isEmpty);
  });

  // 🗣️F-496 (유저 2026-10-28): 「ON은 표시안하고 OFF랑 MONO도 se블록에 표시.
  // 타임시트 용지패널처럼 이름 앞이니까 이름 왼쪽에. 이름이랑 같은텍스트/규칙.
  // 공간없으면 이름이 블록안에 첫부분에 들어가니까, 그 경우 이름 오른쪽에
  // 검정색으로. 대사랑 겹쳐도 문제없음」.
  group('F-496: the delivery beside the name', () {
    Finder said(SeLineType type) =>
        find.bySemanticsLabel('SE delivery ${type.label}');
    Finder name() => find.bySemanticsLabel('SE name ドア');

    /// How [rect] is written: white, on a tint, or in ink of another
    /// colour than either over the row's ground.
    Future<({bool white, bool tinted, bool inked})> look(
      WidgetTester tester,
      Rect rect,
    ) async {
      final pixels = await pixelsOver(tester, rect);
      return (
        white: pixels.any(white),
        tinted: pixels.any(tinted),
        inked: pixels.any(
          (pixel) => pixel != rowGround && !white(pixel) && !tinted(pixel),
        ),
      );
    }

    testWidgets('ON writes nothing beside the name; OFF and MONO do', (
      tester,
    ) async {
      for (final type in SeLineType.values) {
        await mount(tester, width: 100, frames: 10, delivery: type);
        expect(
          find.bySemanticsLabel(RegExp('SE delivery')),
          type.writtenOut ? findsOneWidget : findsNothing,
          reason: type.name,
        );
        expect(name(), findsOneWidget, reason: 'the name, either way');
      }
    });

    testWidgets('🚨with room before its block for both, it stands LEFT of '
        'the name, white on the row; a zoom that takes that room lays it '
        'right of the name, in the block\'s ink — building nothing', (
      tester,
    ) async {
      // Ten frames of 10, four of them free before: room for two chips.
      final resize = await mount(
        tester,
        width: 100,
        frames: 10,
        words: 'あい',
        framesFreeBefore: 4,
        left: 60,
        delivery: SeLineType.off,
      );
      final rebuilt = <Type>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) =>
          rebuilt.add(element.widget.runtimeType);
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final off = said(SeLineType.off);
      expect(tester.getRect(name()).right, closeTo(60, 1e-6), reason: '⛔전제');
      expect(tester.getRect(off).width, seNameBoxExtent);
      expect(
        tester.getRect(off).right,
        closeTo(tester.getRect(name()).left, 1e-6),
        reason: 'just before the name',
      );
      final out = await look(tester, tester.getRect(off));
      expect([out.white, out.tinted], [true, false], reason: 'the name\'s');

      // Frames of 6: four of them hold 24 — the name, not both.
      resize(60);
      await tester.pump();
      expect(tester.getRect(name()).right, closeTo(60, 1e-6), reason: '⛔전제');
      expect(tester.getRect(off).left, closeTo(60, 1e-6), reason: 'after it');
      final on = await look(tester, tester.getRect(off));
      expect(
        [on.white, on.tinted, on.inked],
        [false, false, true],
        reason: 'the block\'s ink, on no ground of its own',
      );
      expect(rebuilt.where((type) => '$type' == '_SeHeadWord'), isEmpty);
    });

    testWidgets('with no room before its block, the name takes its head and '
        'the delivery stands right after it, over the words', (tester) async {
      await mount(
        tester,
        width: 100,
        frames: 10,
        words: 'あい',
        delivery: SeLineType.mono,
      );
      final mono = tester.getRect(said(SeLineType.mono));
      expect(tester.getRect(name()).left, closeTo(0, 1e-6), reason: '⛔전제');
      expect(mono.left, closeTo(seNameBoxExtent, 1e-6));
      expect(
        mono.overlaps(tester.getRect(find.byType(DialogueFitText))),
        isTrue,
        reason: '「대사랑 겹쳐도 문제없음」',
      );
      final written = await look(tester, mono);
      expect([written.white, written.tinted, written.inked], [
        false,
        false,
        true,
      ]);
    });

    testWidgets('a nameless block writes it where the name would stand — '
        'before the block white, on its head on no tint', (tester) async {
      await mount(
        tester,
        width: 100,
        frames: 10,
        words: 'あい',
        framesFreeBefore: 2,
        left: 40,
        name: null,
        delivery: SeLineType.off,
      );
      final off = said(SeLineType.off);
      expect(tester.getRect(off).right, closeTo(40, 1e-6));
      final out = await look(tester, tester.getRect(off));
      expect([out.white, out.tinted], [true, false]);

      await mount(
        tester,
        width: 100,
        frames: 10,
        words: 'あい',
        name: null,
        delivery: SeLineType.off,
      );
      expect(tester.getRect(off).left, closeTo(0, 1e-6));
      final on = await look(tester, tester.getRect(off));
      expect([on.white, on.tinted, on.inked], [false, false, true]);
    });

    testWidgets('a line seen from past its head writes both at the head it '
        'is seen from, the tint the name\'s alone', (tester) async {
      await mount(
        tester,
        width: 100,
        frames: 10,
        words: 'あい',
        shownFrom: 4,
        delivery: SeLineType.off,
      );
      final chip = tester.getRect(name());
      final off = tester.getRect(said(SeLineType.off));
      expect(chip.left, closeTo(40, 1e-6));
      expect(off.left, closeTo(40 + seNameBoxExtent, 1e-6));
      expect((await look(tester, chip)).tinted, isTrue);
      expect((await look(tester, off)).tinted, isFalse);
      expect(
        (await look(tester, Rect.fromLTRB(0, 0, chip.left, row))).tinted,
        isFalse,
        reason: 'nor over the frames an earlier cut holds',
      );
    });

    testWidgets('a nameless span built again with what it had, and not laid '
        'again, still writes its delivery white before its block', (
      tester,
    ) async {
      Widget at(String dialogue) => MaterialApp(
        home: Scaffold(
          backgroundColor: rowGround,
          body: RepaintBoundary(
            key: shot,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 40),
                child: SizedBox(
                  width: 100,
                  height: row,
                  child: SeSpanVisual(
                    layer: anSeRow(),
                    axis: Axis.horizontal,
                    frames: 10,
                    dialogue: dialogue,
                    delivery: SeLineType.off,
                    framesFreeBefore: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(at('あい'));
      // An equal dialogue, another instance of the span: built, not laid.
      await tester.pumpWidget(at('あい'));
      final off = tester.getRect(said(SeLineType.off));
      expect(off.right, closeTo(40, 1e-6), reason: '⛔전제: out');
      final out = await look(tester, off);
      expect([out.white, out.tinted], [true, false]);
    });

    testWidgets('the same span seen from another head, or named no more, '
        'lays its words and tint again', (tester) async {
      Widget at({required int shownFrom, String? name = 'ドア'}) =>
          MaterialApp(
            home: Scaffold(
              backgroundColor: rowGround,
              body: RepaintBoundary(
                key: shot,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 100,
                    height: row,
                    child: SeSpanVisual(
                      layer: anSeRow(),
                      axis: Axis.horizontal,
                      frames: 10,
                      dialogue: 'あい',
                      seName: name,
                      delivery: SeLineType.off,
                      shownFrom: shownFrom,
                    ),
                  ),
                ),
              ),
            ),
          );
      final off = said(SeLineType.off);
      await tester.pumpWidget(at(shownFrom: 0));
      expect(tester.getRect(name()).left, closeTo(0, 1e-6), reason: '⛔전제');

      await tester.pumpWidget(at(shownFrom: 4));
      expect(tester.getRect(name()).left, closeTo(40, 1e-6));
      expect(tester.getRect(off).left, closeTo(40 + seNameBoxExtent, 1e-6));
      const head = Rect.fromLTWH(0, 0, seNameBoxExtent, row);
      expect((await look(tester, head)).tinted, isFalse, reason: 'moved');

      await tester.pumpWidget(at(shownFrom: 4, name: null));
      expect(tester.getRect(off).left, closeTo(40, 1e-6));
      final there = await look(tester, tester.getRect(off));
      expect(there.tinted, isFalse, reason: 'no name, no tint');
    });
  });

  testWidgets('a span built again with what it had, and not laid again, '
      'still writes its name white before its block', (tester) async {
    Widget at(String dialogue) => MaterialApp(
      home: Scaffold(
        backgroundColor: rowGround,
        body: RepaintBoundary(
          key: shot,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 40),
              child: SizedBox(
                width: 100,
                height: row,
                child: SeSpanVisual(
                  layer: anSeRow(),
                  axis: Axis.horizontal,
                  frames: 10,
                  dialogue: dialogue,
                  seName: 'ドア',
                  framesFreeBefore: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(at('あい'));
    // An equal dialogue, another instance of the span: built, not laid.
    await tester.pumpWidget(at('あい'));
    final chip = tester.getRect(find.bySemanticsLabel('SE name ドア'));
    expect(chip.right, closeTo(40, 1e-6), reason: '⛔전제: out');
    final pixels = await pixelsOver(tester, chip);
    expect(pixels.where(white), isNotEmpty);
    expect(pixels.where(tinted), isEmpty);
  });

  testWidgets('on the X-sheet\'s column too: white just above its block, on '
      'no ground', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: rowGround,
          body: RepaintBoundary(
            key: shot,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: SizedBox(
                  width: row,
                  height: 100,
                  child: SeSpanVisual(
                    layer: anSeRow(),
                    axis: Axis.vertical,
                    frames: 10,
                    dialogue: 'あい',
                    seName: 'ドア',
                    framesFreeBefore: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final chip = tester.getRect(find.bySemanticsLabel('SE name ドア'));
    expect(chip.bottom, closeTo(40, 1e-6), reason: '⛔전제: out');
    final pixels = await pixelsOver(tester, chip);
    expect(pixels.where(white), isNotEmpty, reason: 'its name, in white');
    expect(pixels.where(tinted), isEmpty, reason: 'on no ground');
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
                layer: anSeRow(),
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
                  child: SeSpanVisual(
                    layer: anSeRow(),
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
              layer: anSeRow(),
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
