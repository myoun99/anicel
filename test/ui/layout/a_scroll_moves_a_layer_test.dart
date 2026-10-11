import 'dart:typed_data';

import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid_scroll_controller.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A SCROLL MOVES A LAYER; IT REPAINTS NOTHING**
/// (playback-page-turn-repaints-the-whole-timeline, 10-11).
///
/// What follows a scroll from outside it — a ruler over the frame cells, a
/// rail beside them ([ScrollFollower]) — repainted on every pixel of
/// scroll, and being no repaint boundary that repaint climbed to the
/// panel's: 🔬379 of the timeline's render objects for a one-pixel scroll
/// of its frame axis, the same 379 at every page a running playhead turned.
///
/// ⚠️The panels' own pins read positions off the RENDER tree, and those were
/// right before and are right now. The move is a LAYER's here, so what is
/// pinned is what the compositor makes of it: the picture of the panel,
/// where a layer the scene did not add again would still stand at its old
/// place.
void main() {
  const panel = ValueKey<String>('panel');
  const ruler = ValueKey<String>('follower-ruler');

  void useRatio(WidgetTester tester, double ratio) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
    addTearDown(tester.view.reset);
  }

  /// A ruler [rulerWidth] wide following a horizontal scroll of cells
  /// [viewportWidth] wide, both 2000 long and each marked at [markAt],
  /// [markWidth] wide — red on the ruler, blue on the cells — and a
  /// neighbour beside them, all on one layer.
  Widget harness(
    ScrollController controller, {
    required double ratio,
    double viewportWidth = 300,
    double rulerWidth = 300,
    double markAt = 500,
    double markWidth = 1,
    _Mark? rulerPainter,
    _Mark? besidePainter,
  }) => MediaQuery(
    data: MediaQueryData(devicePixelRatio: ratio),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: EffectiveDevicePixelRatioScope(
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: panel,
            child: SizedBox(
              width: 800,
              height: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: rulerWidth,
                    height: 20,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxWidth: 2000,
                        child: ScrollFollower(
                          controller: controller,
                          axisDirection: AxisDirection.right,
                          child: CustomPaint(
                            key: ruler,
                            painter:
                                rulerPainter ??
                                _Mark(
                                  const Color(0xFFFF0000),
                                  at: markAt,
                                  width: markWidth,
                                ),
                            size: const Size(2000, 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: viewportWidth,
                    height: 40,
                    child: SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: DeviceGridScrollBody(
                        controller: controller,
                        axisDirection: AxisDirection.right,
                        child: CustomPaint(
                          painter: _Mark(
                            const Color(0xFF0000FF),
                            at: markAt,
                            width: markWidth,
                          ),
                          size: const Size(2000, 40),
                        ),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: besidePainter ?? _Mark(const Color(0xFF00FF00)),
                    size: const Size(300, 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The panel as the compositor makes it, one device pixel a sample.
  Future<({ByteData bytes, int width})> picture(
    WidgetTester tester,
    double ratio,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(panel),
    );
    final read = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (bytes: bytes!, width: width);
    });
    return read!;
  }

  /// The device column each mark comes out of the compositor at, in the
  /// ruler's band and the cells' — null where none does.
  Future<({int? ruler, int? cells})> marks(
    WidgetTester tester,
    double ratio,
  ) async {
    final read = await picture(tester, ratio);
    int? firstColumn(double logicalY, {required bool red}) {
      final row = (logicalY * ratio).floor();
      for (var x = 0; x < read.width; x += 1) {
        final at = (row * read.width + x) * 4;
        final r = read.bytes.getUint8(at);
        final b = read.bytes.getUint8(at + 2);
        if (red ? r > 128 && b < 64 : b > 128 && r < 64) {
          return x;
        }
      }
      return null;
    }

    return (
      ruler: firstColumn(10, red: true),
      cells: firstColumn(40, red: false),
    );
  }

  /// Every device column each mark covers, with how much of it (alpha) —
  /// where a mark a fraction of a pixel off the grid shows, and its first
  /// column alone may not.
  Future<({List<(int, int)> ruler, List<(int, int)> cells})> coverage(
    WidgetTester tester,
    double ratio,
  ) async {
    final read = await picture(tester, ratio);
    List<(int, int)> covered(double logicalY) {
      final row = (logicalY * ratio).floor();
      return [
        for (var x = 0; x < read.width; x += 1)
          if (read.bytes.getUint8((row * read.width + x) * 4 + 3)
              case final alpha when alpha > 0)
            (x, alpha),
      ];
    }

    return (ruler: covered(10), cells: covered(40));
  }

  /// A mark [width] logical wide standing ON the grid from device column
  /// [first]: whole columns, each covered all the way.
  List<(int, int)> landed(int first, double width, double ratio) => [
    for (var x = first; x < first + (width * ratio).round(); x += 1) (x, 255),
  ];

  testWidgets('🚨a pixel of scroll repaints neither what follows it nor what '
      'stands beside it — and what follows still moves', (tester) async {
    useRatio(tester, 1);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final rulerPaints = _Mark(const Color(0xFFFF0000));
    final besidePaints = _Mark(const Color(0xFF00FF00));
    await tester.pumpWidget(
      harness(
        controller,
        ratio: 1,
        rulerPainter: rulerPaints,
        besidePainter: besidePaints,
      ),
    );
    controller.jumpTo(300);
    await tester.pump();
    final before = (ruler: rulerPaints.paints, beside: besidePaints.paints);
    expect(before.ruler, greaterThan(0), reason: 'fixture: it painted once');

    for (var step = 1; step <= 5; step += 1) {
      controller.jumpTo(300 + step.toDouble());
      await tester.pump();
    }

    expect(
      rulerPaints.paints,
      before.ruler,
      reason: 'the ruler is painted once and moved — ↩️it was repainted at '
          'every pixel',
    );
    expect(
      besidePaints.paints,
      before.beside,
      reason: '🚨and the repaint does not climb to what stands beside it — '
          '↩️it repainted the panel\'s whole layer',
    );
    final seen = await marks(tester, 1);
    expect(seen.cells, 195, reason: 'fixture: the cells\' mark, 500 - 305');
    expect(seen.ruler, seen.cells, reason: 'and the ruler\'s stands over it');
  });

  for (final ratio in <double>[1, 1.35]) {
    testWidgets('🚨what follows lands where the cells land — on the device '
        'grid, ratio $ratio (F-32)', (tester) async {
      useRatio(tester, ratio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller, ratio: ratio));

      for (final at in <double>[250.37, 400.5, 377.77, 300]) {
        controller.jumpTo(at);
        await tester.pump();
        final seen = await marks(tester, ratio);
        expect(seen.cells, isNotNull, reason: 'fixture: the mark is in view');
        expect(seen.ruler, seen.cells, reason: 'scrolled to $at');
      }
    });
  }

  testWidgets('🚨a scroll redraws its bar and nothing beside it — though a '
      'LayoutBuilder stands around both', (tester) async {
    useRatio(tester, 1);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const thumb = ValueKey<String>('bar-thumb');
    final besidePaints = _Mark(const Color(0xFF00FF00));
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            child: SizedBox(
              width: 300,
              height: 80,
              // As the timeline's grid lays its bar out: under a
              // LayoutBuilder, whose layout runs the rebuilds below it.
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    SizedBox(
                      height: 40,
                      child: SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: const SizedBox(width: 2000, height: 40),
                      ),
                    ),
                    SizedBox(
                      height: 16,
                      child: AppControllerScrollbar(
                        controller: controller,
                        axis: Axis.horizontal,
                        thumbKey: thumb,
                      ),
                    ),
                    CustomPaint(
                      painter: besidePaints,
                      size: const Size(300, 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final painted = besidePaints.paints;
    final thumbAt = tester.getTopLeft(find.byKey(thumb)).dx;

    for (var step = 1; step <= 5; step += 1) {
      controller.jumpTo(step * 100.0);
      await tester.pump();
    }

    expect(
      tester.getTopLeft(find.byKey(thumb)).dx,
      greaterThan(thumbAt),
      reason: 'fixture: the bar follows the scroll',
    );
    expect(
      besidePaints.paints,
      painted,
      reason: '🚨and what stands beside it is not painted again — ↩️the bar\'s '
          'rebuild was laid out by the LayoutBuilder around it, and its '
          'relayout repainted the layer they share',
    );
  });

  for (final ratio in <double>[1, 1.5]) {
    testWidgets('🚨a viewport that pulls its position back during layout '
        'takes what follows it along — with no listener told, and both on '
        'the grid, ratio $ratio (F-95 · F-32)', (tester) async {
      useRatio(tester, ratio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      // ⚠️At 1.5 the narrow viewport is no whole number of device pixels,
      // so the nudge onto the grid before the pull is not the one after it:
      // a half still wearing the old one stands a quarter of a device pixel
      // off the other, and off the grid (10-11 — the cells wore it).
      final narrow = ratio == 1 ? 300.0 : 300.5;
      // The ruler as wide as the cells will be, and the marks at 1800 and
      // two wide: in view before the pull and after it, and whole device
      // pixels at both ratios when they land.
      final rulerPaints = _Mark(const Color(0xFFFF0000), at: 1800, width: 2);
      Widget panelOf(double viewportWidth) => harness(
        controller,
        ratio: ratio,
        viewportWidth: viewportWidth,
        rulerWidth: 800,
        markAt: 1800,
        markWidth: 2,
        rulerPainter: rulerPaints,
      );
      /// Where the marks land with the position at [offset].
      int landsAt(double offset) =>
          (1800 * ratio - (offset * ratio).roundToDouble()).round();

      await tester.pumpWidget(panelOf(narrow));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(controller.offset, 2000 - narrow, reason: 'fixture: at the end');
      final before = await coverage(tester, ratio);
      expect(
        before.cells,
        landed(landsAt(2000 - narrow), 2, ratio),
        reason: 'fixture: the cells on the grid',
      );
      expect(before.ruler, before.cells, reason: 'fixture: the ruler over it');

      var told = 0;
      controller.addListener(() => told += 1);
      final painted = rulerPaints.paints;
      // The cells' viewport grows past their end; the ruler's box does not
      // change at all, so nothing lays it out or paints it.
      await tester.pumpWidget(panelOf(800));

      expect(controller.offset, 1200, reason: 'fixture: pulled back');
      expect(told, 0, reason: 'fixture: and nobody was told');
      expect(
        rulerPaints.paints,
        painted,
        reason: 'fixture: nor was the ruler painted',
      );
      final after = await coverage(tester, ratio);
      expect(
        after.cells,
        landed(landsAt(1200), 2, ratio),
        reason: 'the cells land on the grid by the PULLED position — '
            '↩️they kept the nudge read as they were built, before the pull',
      );
      expect(
        after.ruler,
        after.cells,
        reason: 'and the ruler still stands over the cells it numbers, to the '
            'device pixel — its layer read the pulled position as the frame '
            'was composited',
      );
    });
  }

  testWidgets('🚨a new grid — another screen\'s ratio — lands both halves on '
      'it', (tester) async {
    useRatio(tester, 1.25);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller, ratio: 1.25, markWidth: 2));
    // Where the nudge at 1.25 (-0.3) is not the one at 1.5 (-1/6), and the
    // marks at 500 are in view.
    controller.jumpTo(300.5);
    await tester.pump();

    useRatio(tester, 1.5);
    await tester.pumpWidget(harness(controller, ratio: 1.5, markWidth: 2));

    final seen = await coverage(tester, 1.5);
    expect(
      seen.cells,
      landed((500 * 1.5 - (300.5 * 1.5).roundToDouble()).round(), 2, 1.5),
      reason: 'the cells land on the new grid — the scrollable makes itself '
          'a new position at a new ratio, and the viewport paints them with '
          'the nudge read then',
    );
    expect(seen.ruler, seen.cells, reason: 'and the ruler with them');
  });

  testWidgets('🚨what follows, painted again while scrolled, still stands over '
      'the cells — its layer moves it, its paint does not', (tester) async {
    useRatio(tester, 1);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final again = ValueNotifier<int>(0);
    addTearDown(again.dispose);
    final rulerPaints = _Mark(const Color(0xFFFF0000), repaint: again);
    await tester.pumpWidget(
      harness(controller, ratio: 1, rulerPainter: rulerPaints),
    );
    controller.jumpTo(305);
    await tester.pump();
    final painted = rulerPaints.paints;

    again.value += 1;
    await tester.pump();

    expect(
      rulerPaints.paints,
      greaterThan(painted),
      reason: 'fixture: the ruler was painted again, scrolled',
    );
    final seen = await marks(tester, 1);
    expect(seen.cells, 195, reason: 'fixture: the cells\' mark, 500 - 305');
    expect(
      seen.ruler,
      seen.cells,
      reason: 'and the ruler\'s stands over it — one painted at the scroll '
          'AND moved by its layer would stand 305 further on',
    );
  });
}

/// A painter that draws one upright line [width] wide at [at] and counts its
/// paints — and repaints only when [repaint] says so.
class _Mark extends CustomPainter {
  _Mark(this.color, {this.at = 500, this.width = 1, super.repaint});

  final Color color;
  final double at;
  final double width;
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints += 1;
    canvas.drawRect(
      Rect.fromLTWH(at, 0, width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Mark oldDelegate) => false;
}
