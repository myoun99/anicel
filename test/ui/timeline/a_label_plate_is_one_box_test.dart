// Card frame-panels-build-in-one-frame (2026-10-25): the colour plate and
// the take are ONE box each — they fill, set, place and say their words
// themselves ([RenderLabelPlate], [RenderTakeText]). The plate used to be a
// `SizedBox.expand` › `ColoredBox` › `ClipRect` › `Flex` of `Expanded` ›
// `FittedBox(fill)` around each word's own box, the take a `ClipRect` ›
// `Center` around its word's; these hold the boxes to those compositions in
// both of the rail's axes, in the hosts the app puts them in.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/text/word_bake.dart'
    show BakedWords, WordBakeWaiter;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_plate_words.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineTextOnColor;

import '../../helpers/settle_async.dart';

const _boundary = ValueKey<String>('boundary');
const _host = ValueKey<String>('host');
const _old = ValueKey<String>('old');

/// [box] in [host] — and the host's own semantics node, which the box's
/// words are said on.
Widget _framed(Widget box, Widget Function(Widget) host, double scale) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _boundary,
              child: SizedBox(
                width: 60,
                height: 80,
                child: Semantics(
                  key: _host,
                  container: true,
                  label: 'host',
                  child: host(box),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// A word as the plates wrote it before they were boxes — stood up on the
/// rail, laid across and scaled down whole on the sheet.
Widget _wordAsItWas(String text, Axis axis, TextStyle style) =>
    axis == Axis.horizontal
    ? VerticalWritingText(
        text: text,
        latinForm: VerticalLatinForm.upright,
        lineHeight: SectionBandZone.lineHeight,
        overflow: VerticalTextOverflow.pack,
        minFontSize: 4,
        style: style,
      )
    : FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, style: style.copyWith(height: 1.0)),
      );

/// The plate as it was built.
Widget _plateAsItWas(LayerMark mark, {required bool shown, required Axis axis}) {
  final fill = shown
      ? layerMarkColor(mark)
      : layerMarkColor(mark).withValues(alpha: AppColors.offAlpha);
  final (:process, :revise) = layerMarkChipText(mark);
  final words = [process, revise].where((text) => text.isNotEmpty).toList();
  final style = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w400,
    height: SectionBandZone.lineHeight,
    color: timelineTextOnColor(fill),
  );
  return SizedBox.expand(
    key: _old,
    child: ColoredBox(
      color: fill,
      child: words.isEmpty
          ? null
          : ClipRect(
              child: Flex(
                direction: axis,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final text in words)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: _wordAsItWas(text, axis, style),
                      ),
                    ),
                ],
              ),
            ),
    ),
  );
}

/// The take as it was built.
Widget _takeAsItWas(LayerMark mark, Axis axis) => Builder(
  builder: (context) => ClipRect(
    key: _old,
    child: Center(
      child: _wordAsItWas(
        mark.takeText,
        axis,
        layerRowNameStyle(context).copyWith(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: SectionBandZone.lineHeight,
        ),
      ),
    ),
  ),
);

/// Until no word waits for its bake, and the frame that draws the landed
/// ones — so both sides are read drawing the same bakes.
Future<void> _settle(WidgetTester tester) async {
  await settleAsync(tester, () => BakedWords.instance.debugWaitingWords == 0);
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  return pixels;
}

typedef _Reading = ({
  Size size,
  Uint8List pixels,
  String label,
  TextDirection? direction,
  bool hitInTheMiddle,
  bool hitInTheCorner,
});

bool _hits(WidgetTester tester, Finder box, Offset at) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, at, tester.view.viewId);
  final target = tester.renderObject(box);
  return result.path.any((entry) => entry.target == target);
}

Future<_Reading> _read(WidgetTester tester, Finder box) async {
  final host = tester.getSemantics(find.byKey(_host)).getSemanticsData();
  return (
    size: tester.getSize(box),
    pixels: await _pixels(tester),
    label: host.label,
    direction: host.textDirection,
    hitInTheMiddle: _hits(tester, box, tester.getCenter(box)),
    hitInTheCorner: _hits(
      tester,
      box,
      tester.getTopLeft(box) + const Offset(0.5, 0.5),
    ),
  );
}

void _expectSame(_Reading now, _Reading old) {
  expect(now.size, old.size);
  expect(now.pixels, old.pixels);
  expect(now.label, old.label);
  expect(now.direction, old.direction);
  expect(now.hitInTheMiddle, old.hitInTheMiddle);
  expect(now.hitInTheCorner, old.hitInTheCorner);
}

/// A slot of the rail ([Axis.horizontal], tall) or the sheet's header
/// ([Axis.vertical], wide), and a loose host around it.
Map<String, Widget Function(Widget)> _hostsOf(Axis axis) {
  final slot = axis == Axis.horizontal
      ? const Size(14, 26)
      : const Size(28, 14);
  return {
    'its slot': (box) => Center(child: SizedBox.fromSize(size: slot, child: box)),
    'a loose host': (box) => Center(child: box),
    'a cramped slot': (box) => Center(
      child: SizedBox(width: 6, height: 7, child: box),
    ),
  };
}

const _marks = <String, LayerMark>{
  'no label': LayerMark.none,
  'one word': LayerMark(process: LayerProcess.finish),
  'two words': LayerMark(
    process: LayerProcess.inbetween,
    revise: LayerRevise.inbetweenCheck,
  ),
  'a short and a long word': LayerMark(
    process: LayerProcess.layout,
    revise: LayerRevise.chiefAnimationDirector,
  ),
};

/// A label with two words and a take.
const _labelled = LayerMark(
  process: LayerProcess.inbetween,
  revise: LayerRevise.inbetweenCheck,
  take: 3,
);

void main() {
  for (final axis in Axis.values) {
    for (final MapEntry(key: hostName, value: host) in _hostsOf(axis).entries) {
      for (final scale in [1.0, 2.0]) {
        for (final MapEntry(key: markName, value: mark) in _marks.entries) {
          for (final shown in [true, if (markName == 'two words') false]) {
            testWidgets('the plate of $markName${shown ? '' : ', hidden'} in '
                '$hostName, ${axis.name}, at ${scale}x paints, measures, says '
                'and hits as the composition it replaced', (tester) async {
              final handle = tester.ensureSemantics();
              await tester.pumpWidget(
                _framed(
                  LayerMarkPlate(mark: mark, isVisible: shown, axis: axis),
                  host,
                  scale,
                ),
              );
              await _settle(tester);
              final now = await _read(tester, find.byType(LayerMarkPlate));

              await tester.pumpWidget(
                _framed(
                  _plateAsItWas(mark, shown: shown, axis: axis),
                  host,
                  scale,
                ),
              );
              await _settle(tester);
              _expectSame(now, await _read(tester, find.byKey(_old)));
              handle.dispose();
            });
          }
        }
        for (final take in [1, 9]) {
          testWidgets('take $take in $hostName, ${axis.name}, at ${scale}x '
              'paints, measures, says and hits as the composition it '
              'replaced', (tester) async {
            final handle = tester.ensureSemantics();
            final mark = LayerMark.none.withTake(take);
            await tester.pumpWidget(
              _framed(LayerTakeText(mark: mark, axis: axis), host, scale),
            );
            await _settle(tester);
            final now = await _read(tester, find.byType(LayerTakeText));

            await tester.pumpWidget(
              _framed(_takeAsItWas(mark, axis), host, scale),
            );
            await _settle(tester);
            _expectSame(now, await _read(tester, find.byKey(_old)));
            handle.dispose();
          });
        }
      }
    }
  }

  Widget slotted(Widget box) => _framed(
    box,
    (box) => Center(
      child: SizedBox(width: 14, height: 26, child: box),
    ),
    1,
  );

  /// A plate and a take in their slots, side by side.
  Widget pair() => _framed(
    const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 14, height: 26, child: LayerMarkPlate(mark: _labelled)),
        SizedBox(
          width: 14,
          height: 26,
          child: LayerTakeText(mark: _labelled, axis: Axis.horizontal),
        ),
      ],
    ),
    (box) => Center(child: box),
    1,
  );

  testWidgets('a plate and a take are one element each — nothing stands '
      'under them', (tester) async {
    await tester.pumpWidget(pair());
    for (final box in [find.byType(LayerMarkPlate), find.byType(LayerTakeText)]) {
      var under = 0;
      tester.element(box).visitChildren((_) => under += 1);
      expect(under, 0);
    }
  });

  testWidgets('a word that lands paints the plate and the take again', (
    tester,
  ) async {
    await tester.pumpWidget(pair());
    final plate = tester.renderObject<RenderLabelPlate>(
      find.byType(LayerMarkPlate),
    );
    final take = tester.renderObject<RenderTakeText>(
      find.byType(LayerTakeText),
    );
    for (final (index, word) in plate.words.indexed) {
      expect(plate.debugNeedsPaint, isFalse);
      (word.repaint! as WordBakeWaiter).wordBakeLanded();
      expect(plate.debugNeedsPaint, isTrue, reason: 'word $index');
      await tester.pump();
    }
    expect(take.debugNeedsPaint, isFalse);
    (take.word.repaint! as WordBakeWaiter).wordBakeLanded();
    expect(take.debugNeedsPaint, isTrue);
  });

  testWidgets('a plate and a take their host hands a new label paint, '
      'measure and say it as ones built for it do', (tester) async {
    final handle = tester.ensureSemantics();
    Widget labelled(LayerMark mark, {required bool shown, required Axis axis}) =>
        _framed(
          Row(
            key: _old,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 26,
                child: LayerMarkPlate(mark: mark, isVisible: shown, axis: axis),
              ),
              SizedBox(
                width: 28,
                height: 26,
                child: LayerTakeText(mark: mark, axis: axis),
              ),
            ],
          ),
          (box) => Center(child: box),
          1,
        );
    const before = LayerMark(process: LayerProcess.layout, take: 2);
    const after = LayerMark(
      process: LayerProcess.inbetween,
      revise: LayerRevise.inbetweenCheck,
      take: 7,
    );
    for (final axis in Axis.values) {
      await tester.pumpWidget(labelled(before, shown: true, axis: axis));
      await _settle(tester);
      await tester.pumpWidget(labelled(after, shown: false, axis: axis));
      await _settle(tester);
      final handed = await _read(tester, find.byKey(_old));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(labelled(after, shown: false, axis: axis));
      await _settle(tester);
      _expectSame(handed, await _read(tester, find.byKey(_old)));
    }
    handle.dispose();
  });

  testWidgets('the plate turned to the other axis lays its words the other '
      'way, as one built there does', (tester) async {
    Widget turned(Axis axis) => slotted(
      LayerMarkPlate(mark: _marks['two words']!, axis: axis),
    );
    await tester.pumpWidget(turned(Axis.horizontal));
    await _settle(tester);
    await tester.pumpWidget(turned(Axis.vertical));
    await _settle(tester);
    final handed = await _pixels(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(turned(Axis.vertical));
    await _settle(tester);
    expect(handed, await _pixels(tester));
  });

  testWidgets('a plate rebuilt with the same words keeps the ones it set — '
      'and lets go of the ones it no longer writes', (tester) async {
    Widget sheet(LayerMark mark) => slotted(
      LayerMarkPlate(mark: mark, axis: Axis.vertical),
    );
    RenderLabelPlate plate() =>
        tester.renderObject<RenderLabelPlate>(find.byType(LayerMarkPlate));

    await tester.pumpWidget(sheet(_labelled));
    final first = plate().words;
    expect(first, everyElement(isA<LyingPlateWords>()));
    await tester.pumpWidget(sheet(_labelled.withTake(5)));
    expect(
      plate().words.indexed.every(
        (entry) => identical(entry.$2, first[entry.$1]),
      ),
      isTrue,
      reason: 'the same words, set once',
    );
    expect(
      first.cast<LyingPlateWords>().map((word) => word.debugLetGo),
      everyElement(isFalse),
    );

    await tester.pumpWidget(
      sheet(const LayerMark(process: LayerProcess.inbetween)),
    );
    final second = plate().words.cast<LyingPlateWords>();
    expect(identical(second.single, first.first), isTrue, reason: 'IB stays');
    expect((first.last as LyingPlateWords).debugLetGo, isTrue, reason: 'IBC');

    await tester.pumpWidget(sheet(const LayerMark(process: LayerProcess.key)));
    expect(second.single.debugLetGo, isTrue, reason: 'IB, replaced');
    final third = plate().words.cast<LyingPlateWords>().single;

    await tester.pumpWidget(const SizedBox());
    expect(third.debugLetGo, isTrue, reason: 'the plate is gone');
  });

  testWidgets('a rail plate rebuilt with the same words keeps the columns it '
      'set, and sets a new one for a new word', (tester) async {
    Widget rail(LayerMark mark) => slotted(LayerMarkPlate(mark: mark));
    List<PlateWords> words() => tester
        .renderObject<RenderLabelPlate>(find.byType(LayerMarkPlate))
        .words;

    await tester.pumpWidget(rail(_labelled));
    final first = words();
    expect(first, everyElement(isA<StoodPlateWords>()));
    await tester.pumpWidget(rail(_labelled.withTake(5)));
    expect(identical(words().first, first.first), isTrue);
    expect(identical(words().last, first.last), isTrue);

    await tester.pumpWidget(
      rail(
        const LayerMark(
          process: LayerProcess.inbetween,
          revise: LayerRevise.cellCheck,
        ),
      ),
    );
    expect(identical(words().first, first.first), isTrue, reason: 'IB stays');
    expect(identical(words().last, first.last), isFalse, reason: 'CC is new');
  });
}
