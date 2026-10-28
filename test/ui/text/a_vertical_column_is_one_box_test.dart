// Card frame-panels-build-in-one-frame (2026-10-25): a column of vertical
// writing is ONE box — it paints, sizes and says itself
// ([RenderVerticalWriting]). It used to be a `Semantics` over an
// `ExcludeSemantics` over a `CustomPaint`; these hold the box to that
// composition, given the same painter, in every host the app puts it in.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/text/word_bake.dart'
    show BakedWords, WordBakeWaiter;

import '../../helpers/settle_async.dart';

const _boundary = ValueKey<String>('boundary');
const _host = ValueKey<String>('host');

/// [column] in [host] — and the host's own semantics node, which the
/// column's words are said on.
Widget _framed(Widget column, Widget Function(Widget) host, double scale) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _boundary,
              child: SizedBox(
                width: 60,
                height: 160,
                child: Semantics(
                  key: _host,
                  container: true,
                  label: 'host',
                  child: host(column),
                ),
              ),
            ),
          ),
        ),
      ),
    );

const _old = ValueKey<String>('old');

/// The composition the box replaced, painting with [painter].
Widget _asItWas(String text, CustomPainter painter, Size size) => Semantics(
  label: text,
  child: ExcludeSemantics(
    child: CustomPaint(key: _old, size: size, painter: painter),
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
  bool hit,
});

Future<_Reading> _read(WidgetTester tester, Finder box) async {
  final host = tester.getSemantics(find.byKey(_host)).getSemanticsData();
  final centre = tester.getCenter(box);
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, centre, tester.view.viewId);
  final target = tester.renderObject(box);
  return (
    size: tester.getSize(box),
    pixels: await _pixels(tester),
    label: host.label,
    direction: host.textDirection,
    hit: result.path.any((entry) => entry.target == target),
  );
}

void main() {
  final hosts = <String, Widget Function(Widget)>{
    'a loose host': (column) => Center(child: column),
    'a tight host': (column) => column,
    'an unbounded host': (column) =>
        SingleChildScrollView(child: Center(child: column)),
    'a cramped host': (column) => Center(
      child: SizedBox(width: 30, height: 20, child: ClipRect(child: column)),
    ),
  };
  final columns = <String, VerticalWritingText>{
    'kana': const VerticalWritingText(
      text: 'カット',
      style: TextStyle(fontSize: 9),
    ),
    'latin standing, packed': const VerticalWritingText(
      text: 'LO',
      latinForm: VerticalLatinForm.upright,
      overflow: VerticalTextOverflow.pack,
      minFontSize: 4,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
    ),
    'from the top, inset, two inks': const VerticalWritingText(
      text: '100',
      mainAlignment: 0,
      endInset: 3,
      inks: [
        (end: 0.5, ink: Color(0xFF000000)),
        (end: 1, ink: Color(0xFFFFFFFF)),
      ],
      style: TextStyle(fontSize: 10),
    ),
    'nothing': const VerticalWritingText(text: ''),
  };

  for (final MapEntry(key: hostName, value: host) in hosts.entries) {
    for (final MapEntry(key: columnName, value: column) in columns.entries) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('$columnName in $hostName at ${scale}x paints, measures, '
            'says and hits as the composition it replaced', (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(_framed(column, host, scale));
          await _settle(tester);
          final box = find.byType(VerticalWritingText);
          final now = await _read(tester, box);
          final render = tester.renderObject<RenderVerticalWriting>(box);
          final painter = render.painter!;
          final natural = column.naturalSizeIn(tester.element(box));

          await tester.pumpWidget(
            _framed(_asItWas(column.text, painter, natural), host, scale),
          );
          await _settle(tester);
          final old = await _read(tester, find.byKey(_old));

          expect(now.size, old.size);
          expect(now.pixels, old.pixels);
          expect(now.label, old.label);
          expect(now.direction, old.direction);
          expect(now.hit, old.hit);
          handle.dispose();
        });
      }
    }
  }

  testWidgets('a column is one element — nothing stands under it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _framed(columns['kana']!, (column) => Center(child: column), 1),
    );
    final element = tester.element(find.byType(VerticalWritingText));
    var under = 0;
    element.visitChildren((_) => under += 1);
    expect(under, 0);
  });

  testWidgets('a word that lands paints the column again', (tester) async {
    await tester.pumpWidget(
      _framed(columns['kana']!, (column) => Center(child: column), 1),
    );
    final render = tester.renderObject<RenderVerticalWriting>(
      find.byType(VerticalWritingText),
    );
    expect(render.debugNeedsPaint, isFalse);
    (render.painter! as WordBakeWaiter).wordBakeLanded();
    expect(render.debugNeedsPaint, isTrue);
  });

  testWidgets('a column its host hands a new text paints and measures it as '
      'one built for it does', (tester) async {
    Widget writing(String text) => _framed(
      VerticalWritingText(text: text, style: const TextStyle(fontSize: 9)),
      (column) => Center(child: column),
      1,
    );
    final box = find.byType(VerticalWritingText);
    await tester.pumpWidget(writing('カ'));
    await _settle(tester);
    await tester.pumpWidget(writing('カットシーン'));
    await _settle(tester);
    final handedSize = tester.getSize(box);
    final handedPixels = await _pixels(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(writing('カットシーン'));
    await _settle(tester);
    expect(handedSize, tester.getSize(box));
    expect(handedPixels, await _pixels(tester));
  });

  testWidgets('a column told a new text says it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _framed(columns['kana']!, (column) => Center(child: column), 1),
    );
    final render = tester.renderObject<RenderVerticalWriting>(
      find.byType(VerticalWritingText),
    );
    render.text = 'シーン';
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(_host)).getSemanticsData().label,
      'host\nシーン',
    );
    handle.dispose();
  });

  testWidgets('a new text is said', (tester) async {
    final handle = tester.ensureSemantics();
    Widget saying(String text) => _framed(
      VerticalWritingText(text: text, style: const TextStyle(fontSize: 9)),
      (column) => Center(child: column),
      1,
    );
    await tester.pumpWidget(saying('カット'));
    await tester.pumpWidget(saying('シーン'));
    expect(
      tester.getSemantics(find.byKey(_host)).getSemanticsData().label,
      'host\nシーン',
    );
    handle.dispose();
  });
}
