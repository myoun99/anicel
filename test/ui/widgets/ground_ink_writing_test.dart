import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/ground_ink_writing.dart';

/// H38 again (유저 2026-09-11): 「뒤 색에 따라 하양/검정 바꾸는거 … 그거대로
/// 하자 … 슬라이더 공용 텍스트ui 그대로 재사용」 — the one writing whose ink
/// follows the ground under it.
void main() {
  const white = Color(0xFFFFFFFF);
  const black = Color(0xFF000000);

  group('runs', () {
    test('a bar with a fill: track, fill, track', () {
      expect(
        groundInkRunsForFill(
          near: 0.25,
          far: 0.5,
          onFill: black,
          onTrack: white,
        ),
        [(end: 0.25, ink: white), (end: 0.5, ink: black), (end: 1.0, ink: white)],
      );
    });

    test('a fill from the start has no track before it, and a full one none '
        'after it', () {
      expect(
        groundInkRunsForFill(near: 0, far: 1, onFill: black, onTrack: white),
        [(end: 1.0, ink: black)],
      );
    });

    test('🚨an EMPTY bar is all track — 「뒤가 비어있으면」', () {
      expect(
        groundInkRunsForFill(near: 0, far: 0, onFill: black, onTrack: white),
        [(end: 1.0, ink: white)],
      );
    });
  });

  testWidgets('one ink over the whole width is a plain colour — no shader', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GroundInkWriting(
          runs: const [(end: 1.0, ink: white)],
          builder: (context, ink) => Text('solid', style: ink),
        ),
      ),
    );

    final style = tester.widget<Text>(find.text('solid')).style!;
    expect(style.color, white);
    expect(style.foreground, isNull);
  });

  testWidgets('🚨the ink changes PART WAY THROUGH the writing, where the '
      'ground changes — measured in pixels, off the layer\'s origin', (
    tester,
  ) async {
    // The writing sits 50 px into its layer on purpose: a shader read in
    // the LAYER's coordinates would split the ink at 100 of the layer —
    // 50 into the writing — instead of halfway through it.
    final boundary = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFF808080),
              child: Padding(
                padding: const EdgeInsets.only(left: 50),
                child: SizedBox(
                  width: 200,
                  height: 20,
                  child: GroundInkWriting(
                    runs: const [(end: 0.5, ink: white), (end: 1.0, ink: black)],
                    builder: (context, ink) => Text(
                      'XXXXXXXXXX',
                      style: const TextStyle(fontSize: 20, height: 1).merge(ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = (await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      image.dispose();
      return (data!, width);
    }))!;
    int redAt(int x, int y) => bytes.$1.getUint8((y * bytes.$2 + x) * 4);

    expect(redAt(50 + 75, 10), greaterThan(200), reason: 'the left half: white');
    expect(redAt(50 + 125, 10), lessThan(50), reason: 'the right half: black');
    expect(
      tester.widgetList<Text>(find.text('XXXXXXXXXX')),
      hasLength(1),
      reason: 'one Text for one string — never the writing laid twice',
    );
  });

  group('one shape, whatever the ground (2026-09-26)', () {
    // A bar whose fill crossed into or out of its words used to throw its
    // writing away and build the other shape — a replaced child, laid out
    // again all the way up to the row's first relayout boundary (on a brush
    // pick: the whole tool settings column, and its semantics).
    Widget writing(List<GroundInkRun> runs, {ValueChanged<Offset>? painted}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 50),
              child: SizedBox(
                width: 200,
                height: 20,
                child: GroundInkWriting(
                  runs: runs,
                  builder: (context, ink) => _OffsetProbe(
                    painted: painted ?? (_) {},
                    child: Text('word', style: ink),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('the writing keeps its render objects when the ground under '
        'it starts or stops changing', (tester) async {
      await tester.pumpWidget(writing(const [(end: 1.0, ink: white)]));
      final paragraph = tester.renderObject(find.text('word'));

      await tester.pumpWidget(
        writing(const [(end: 0.5, ink: white), (end: 1.0, ink: black)]),
      );
      expect(
        tester.widget<Text>(find.text('word')).style?.foreground?.shader,
        isNotNull,
        reason: 'fixture: the ground now changes under the writing',
      );
      expect(tester.renderObject(find.text('word')), same(paragraph));

      await tester.pumpWidget(writing(const [(end: 1.0, ink: black)]));
      expect(tester.widget<Text>(find.text('word')).style?.color, black);
      expect(tester.renderObject(find.text('word')), same(paragraph));
    });

    testWidgets('one ink paints the ordinary way — the canvas is moved only '
        'for a shader', (tester) async {
      final offsets = <Offset>[];
      await tester.pumpWidget(
        writing(const [(end: 1.0, ink: white)], painted: offsets.add),
      );
      expect(
        offsets.last.dx,
        50,
        reason: 'one ink: painted at its offset, as it always was',
      );

      await tester.pumpWidget(
        writing(
          const [(end: 0.5, ink: white), (end: 1.0, ink: black)],
          painted: offsets.add,
        ),
      );
      expect(
        offsets.last,
        Offset.zero,
        reason: 'a shader: the canvas moved to the writing\'s own origin',
      );
    });
  });
}

/// Records the offset its paint is handed, then paints its child there.
class _OffsetProbe extends SingleChildRenderObjectWidget {
  const _OffsetProbe({required this.painted, required super.child});

  final ValueChanged<Offset> painted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOffsetProbe(painted);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOffsetProbe renderObject,
  ) {
    renderObject.painted = painted;
  }
}

class _RenderOffsetProbe extends RenderProxyBox {
  _RenderOffsetProbe(this.painted);

  ValueChanged<Offset> painted;

  @override
  void paint(PaintingContext context, Offset offset) {
    painted(offset);
    super.paint(context, offset);
  }
}
