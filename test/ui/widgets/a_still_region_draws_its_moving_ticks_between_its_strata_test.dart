import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/raster_parity.dart';

/// 🚨WHAT A TICK MOVES IS DRAWN LIVE BETWEEN A STILL REGION'S STRATA
/// (10-12): a cut playing changed the timeline's dock on every film frame —
/// its cursor, its playhead's writing, its counter, each on a tick layer of
/// its own — so the region was never still, and every frame drew all of it
/// again (the side rails, which hold no tick, came from their images on 75
/// frames of 75; the timeline's dock on none). A still region is cut at
/// every tick that moved while the rest of it stood still, each part a
/// part of one image, the ticks drawn live in their places — so the order
/// the region paints in is kept by construction.
const double _left = 20;
const double _top = 20;
const double _width = 240;
const double _height = 200;

const _ground = Color(0xFF1E88E5);
const _mark = Color(0xFFE53935);
const _cover = Color(0xFF43A047);

RenderStillRaster _region(WidgetTester tester) =>
    tester.renderObject<RenderStillRaster>(find.byType(StillRaster));

Future<void> _frame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

/// Moves the tick a pixel a frame — a tick that moves while the rest of
/// the region stands still — until the region draws from its strata.
Future<void> _moveUntilStill(
  WidgetTester tester,
  ValueNotifier<double> at,
) async {
  for (var i = 0; i < StillRaster.maxStillFrames * 4; i += 1) {
    if (_region(tester).debugDrawnFromImage) {
      return;
    }
    at.value = (at.value + 1) % 180;
    await tester.pump();
  }
}

Color _pixelAt(WidgetTester tester, ByteData bytes, Offset logical) {
  final ratio = tester.view.devicePixelRatio;
  final width = (parityCaptureWidth * ratio).round();
  final i =
      ((logical.dy * ratio).floor() * width + (logical.dx * ratio).floor()) *
      4;
  return Color.fromARGB(
    bytes.getUint8(i + 3),
    bytes.getUint8(i),
    bytes.getUint8(i + 1),
    bytes.getUint8(i + 2),
  );
}

/// A 10×10 mark at [at] along the tick's 200×40 box.
class _Mark extends CustomPainter {
  _Mark(this.at) : super(repaint: at);

  final ValueNotifier<double> at;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(at.value, 0, 10, 10),
      Paint()..color = _mark,
    );
  }

  @override
  bool shouldRepaint(_Mark oldDelegate) => oldDelegate.at != at;
}

/// A region of still ground with a tick across its top — [wrap] put around
/// the tick, [after] painted over everything once the tick is.
Widget _regionWith(
  ValueNotifier<double> at, {
  Widget Function(Widget tick)? wrap,
  Widget? after,
  Key? key,
}) {
  final tick = TickLayer(child: CustomPaint(painter: _Mark(at)));
  return StillRaster(
    key: key,
    debugLabel: 'test',
    child: Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(child: ColoredBox(color: _ground)),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: 200,
          height: 40,
          child: wrap == null ? tick : wrap(tick),
        ),
        ?after,
      ],
    ),
  );
}

/// Painted after the tick, over its left half.
const Widget _coverOverTheTick = Positioned(
  left: 0,
  top: 0,
  width: 100,
  height: 100,
  child: RepaintBoundary(child: ColoredBox(color: _cover)),
);

Future<void> _pump(WidgetTester tester, Widget region, {double left = _left}) =>
    pumpSurface(tester, region, left: left, width: _width, height: _height);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    StaticRaster.ensureFrameClock();
  });

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  testWidgets('🚨a region whose only change is a tick is drawn from its '
      'strata — the tick moving live between them, leaving no trace where '
      'it was', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at));
    await _moveUntilStill(tester, at);
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');
    final taken = region.debugCaptureCount;

    for (final x in [50.0, 120.0, 30.0]) {
      at.value = x;
      await tester.pump();
      expect(region.debugDrawnFromImage, isTrue, reason: 'the tick at $x');
      final bytes = await captureBytes(tester);
      expect(
        _pixelAt(tester, bytes, Offset(_left + x + 5, _top + 5)),
        _mark,
        reason: 'the tick drawn where it is now, $x',
      );
      expect(
        _pixelAt(tester, bytes, const Offset(_left + 175, _top + 5)),
        _ground,
        reason: 'the strata hold no tick of their own',
      );
    }
    expect(region.debugCaptureCount, taken, reason: 'not retaken');
  });

  testWidgets('🚨a stratum is cut to the region — a child laid out past it '
      'costs the image no pixel the region cannot show', (tester) async {
    // A picture's bounds are its boundary's whole box: a row of a timeline
    // is as wide as its whole run, the region shows a page of it.
    await _pump(
      tester,
      const StillRaster(
        debugLabel: 'test',
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _width * 8,
          maxWidth: _width * 8,
          child: RepaintBoundary(child: ColoredBox(color: _ground)),
        ),
      ),
    );
    final region = _region(tester);
    for (var i = 0; i < StillRaster.stillFrames + 2; i += 1) {
      await _frame(tester);
    }
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');
    final ratio = tester.view.devicePixelRatio;
    // The region's own device pixels, and one more each way for where it
    // sits on the grid.
    final most =
        ((_width * ratio).ceil() + 1) * ((_height * ratio).ceil() + 1) * 4;
    expect(region.rasterBytes, inInclusiveRange(1, most));
  });

  testWidgets('🚨a tick something painted after it covers is drawn UNDER it '
      '— the strata keep the order the region paints in', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at, after: _coverOverTheTick));
    await _moveUntilStill(tester, at);
    final region = _region(tester);
    expect(
      region.debugDrawnFromImage,
      isTrue,
      reason: '↩️a covered tick kept its region painting: a picture\'s '
          'bounds are its boundary\'s box, so nearly every tick in the '
          'timeline read as covered',
    );

    at.value = 50;
    await tester.pump();
    expect(region.debugDrawnFromImage, isTrue);
    var bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 55, _top + 5)),
      _cover,
      reason: 'what is painted after the tick stays over it',
    );

    at.value = 150;
    await tester.pump();
    bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 155, _top + 5)),
      _mark,
      reason: 'past the cover the tick shows',
    );
  });

  testWidgets('🚨a tick under a transform is drawn live under it, as it was '
      'in place', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    Widget scaled(Widget tick) => Transform.scale(scale: 0.5, child: tick);
    await _pump(
      tester,
      _regionWith(at, wrap: scaled, key: const ValueKey('image')),
    );
    await _moveUntilStill(tester, at);
    expect(_region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');
    at.value = 120;
    await tester.pump();
    expect(_region(tester).debugDrawnFromImage, isTrue);
    final fromStrata = await captureBytes(tester);

    StillRaster.debugCachePaysOverride = false;
    await _pump(
      tester,
      _regionWith(at, wrap: scaled, key: const ValueKey('painted')),
    );
    await tester.pumpAndSettle();
    final painted = await captureBytes(tester);
    final result = compareRasters(
      fromStrata,
      painted,
      width: (parityCaptureWidth * tester.view.devicePixelRatio).round(),
      tolerance: parityRoundingTolerance,
    );
    expect(result.over, 0, reason: '${result.where} ${result.samples}');
  });

  testWidgets('🚨a tick under a clip is clipped as it was in place', (
    tester,
  ) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        wrap: (tick) => ClipRect(clipper: const _LeftHalf(), child: tick),
      ),
    );
    await _moveUntilStill(tester, at);
    expect(_region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');

    at.value = 150;
    await tester.pump();

    expect(_region(tester).debugDrawnFromImage, isTrue);
    final bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 155, _top + 5)),
      _ground,
      reason: 'past the clip the tick does not show',
    );
    at.value = 50;
    await tester.pump();
    expect(
      _pixelAt(
        tester,
        await captureBytes(tester),
        const Offset(_left + 55, _top + 5),
      ),
      _mark,
      reason: '⛔premise: inside the clip it does',
    );
  });

  testWidgets('🚨a tick under a fade stands the region down — a fade is the '
      'group\'s, and cut into parts the parts would show through each '
      'other', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        wrap: (tick) => Opacity(opacity: 0.5, child: tick),
      ),
    );
    await _moveUntilStill(tester, at);
    final region = _region(tester);

    expect(region.debugDrawnFromImage, isFalse);
    expect(region.standDown, StillStandDown.unvouched);
    expect(region.debugTickRefusals.single, contains('OpacityLayer'));
  });

  testWidgets('🚨a tick that stood still while the strata were taken is in '
      'its stratum — when it moves, the region paints, and the next strata '
      'draw it live', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at));
    for (var i = 0; i < StillRaster.maxStillFrames * 2; i += 1) {
      if (_region(tester).debugDrawnFromImage) {
        break;
      }
      await _frame(tester);
    }
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');

    at.value = 60;
    await tester.pump();
    expect(
      region.debugDrawnFromImage,
      isFalse,
      reason: 'a tick in a stratum moving is a change of the region\'s',
    );
    expect(
      _pixelAt(
        tester,
        await captureBytes(tester),
        const Offset(_left + 65, _top + 5),
      ),
      _mark,
    );

    await _moveUntilStill(tester, at);
    expect(region.debugDrawnFromImage, isTrue);
    final taken = region.debugCaptureCount;
    at.value = 100;
    await tester.pump();
    expect(region.debugDrawnFromImage, isTrue, reason: 'drawn live now');
    expect(region.debugCaptureCount, taken);
  });

  testWidgets('🚨a tick inside a tick: the inner one moving is drawn live, and '
      'what the outer one holds beside it stays in the strata', (
    tester,
  ) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    // The outer tick is added again with the inner one on every move,
    // whatever it holds itself.
    Widget inside(Widget tick) => SizedBox(
      width: 200,
      height: 40,
      child: TickLayer(
        child: Stack(
          children: [
            const Positioned(
              left: 150,
              top: 20,
              width: 40,
              height: 20,
              child: ColoredBox(color: _cover),
            ),
            Positioned(left: 0, top: 0, width: 140, height: 20, child: tick),
          ],
        ),
      ),
    );
    await _pump(tester, _regionWith(at, wrap: inside));
    await _moveUntilStill(tester, at);
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');
    expect(
      region.debugLiveTicks,
      [const Size(140, 20)],
      reason: 'the inner tick alone is drawn live',
    );
    final taken = region.debugCaptureCount;
    at.value = 70;
    await tester.pump();
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.debugCaptureCount, taken);
    final bytes = await captureBytes(tester);
    expect(_pixelAt(tester, bytes, const Offset(_left + 75, _top + 5)), _mark);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 165, _top + 25)),
      _cover,
      reason: 'what the outer tick holds is drawn from its stratum',
    );
  });

  testWidgets('🚨a tick that moves once a film frame stays live between its '
      'moves — at 144Hz a 24fps film\'s counter stands still for five '
      'refreshes of six', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at));
    await _moveUntilStill(tester, at);
    final region = _region(tester);
    expect(region.debugLiveTicks, hasLength(1), reason: '⛔premise: live');
    final taken = region.debugCaptureCount;

    for (var film = 0; film < 8; film += 1) {
      at.value = (at.value + 7) % 180;
      await tester.pump();
      for (var refresh = 1; refresh < 6; refresh += 1) {
        await _frame(tester);
      }
    }
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.debugLiveTicks, hasLength(1), reason: 'still live');
    expect(region.debugCaptureCount, taken, reason: 'not retaken');
  });

  testWidgets('🚨a live tick that stops moving is taken into its stratum — a '
      'row\'s tile lands once, a film frame\'s counter changes every few '
      'refreshes', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at));
    await _moveUntilStill(tester, at);
    final region = _region(tester);
    expect(region.debugLiveTicks, hasLength(1), reason: '⛔premise: live');

    // It stands still for longer than a moving tick is ever still.
    for (var i = 0; i < StillRaster.maxStillFrames * 3; i += 1) {
      await _frame(tester);
      if (region.debugDrawnFromImage && region.debugLiveTicks.isEmpty) {
        break;
      }
    }
    expect(region.debugLiveTicks, isEmpty, reason: 'taken into its stratum');
    expect(region.debugDrawnFromImage, isTrue);
    expect(
      _pixelAt(
        tester,
        await captureBytes(tester),
        Offset(_left + at.value + 5, _top + 5),
      ),
      _mark,
      reason: 'drawn from the stratum where it stood',
    );
  });

  testWidgets('something painted after a tick but beside it lets the region '
      'be still', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        after: const Positioned(
          left: 0,
          top: 60,
          width: 100,
          height: 100,
          child: RepaintBoundary(child: ColoredBox(color: _cover)),
        ),
      ),
    );
    await _moveUntilStill(tester, at);

    expect(_region(tester).debugDrawnFromImage, isTrue);
  });

  testWidgets('🚨the strata drawn with the tick live are the region as it '
      'paints — a covered tick, at a ratio off the grid', (tester) async {
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(at, after: _coverOverTheTick, key: const ValueKey('image')),
      left: _left + 1 / 3,
    );
    await _moveUntilStill(tester, at);
    expect(_region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');
    expect(_region(tester).debugGridShift, isNot(Offset.zero));
    at.value = 90;
    await tester.pump();
    final fromStrata = await captureBytes(tester);

    StillRaster.debugCachePaysOverride = false;
    await _pump(
      tester,
      _regionWith(at, after: _coverOverTheTick, key: const ValueKey('painted')),
      left: _left + 1 / 3,
    );
    await tester.pumpAndSettle();
    final painted = await captureBytes(tester);
    final result = compareRasters(
      fromStrata,
      painted,
      width: (parityCaptureWidth * 1.5).round(),
      tolerance: parityRoundingTolerance,
    );
    expect(
      result.over,
      lessThanOrEqualTo(parityTieBudget),
      reason: '${result.over} beyond the floor, worst ${result.worst}, in '
          '${result.where}: ${result.samples}',
    );
  });

  testWidgets('a region moved onto a new spot every frame is taken no more '
      'than it was — a move is a change, ticks or none', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    for (var step = 0; step < 12; step += 1) {
      await _pump(tester, _regionWith(at), left: _left + step * 0.25);
    }

    expect(_region(tester).debugCaptureCount, 0);
  });

  testWidgets('🚨an outer tick moving on its own is drawn live WHOLE, the '
      'tick moving inside it with it — not taken into the strata it leaves '
      'on its next move', (tester) async {
    final at = ValueNotifier<double>(0);
    final outer = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    addTearDown(outer.dispose);
    // The outer tick paints a mark of its own beside the inner one.
    Widget inside(Widget tick) => SizedBox(
      width: 200,
      height: 40,
      child: TickLayer(
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _Mark(outer))),
            Positioned(left: 0, top: 20, width: 140, height: 20, child: tick),
          ],
        ),
      ),
    );
    Future<void> step() async {
      at.value = (at.value + 1) % 130;
      outer.value = (outer.value + 1) % 190;
      await tester.pump();
    }

    await _pump(tester, _regionWith(at, wrap: inside));
    final region = _region(tester);
    for (var i = 0; i < StillRaster.maxStillFrames * 4; i += 1) {
      if (region.debugDrawnFromImage) {
        break;
      }
      await step();
    }
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');
    expect(region.debugLiveTicks, [const Size(200, 40)]);
    final taken = region.debugCaptureCount;
    for (var i = 0; i < 12; i += 1) {
      await step();
    }
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.debugCaptureCount, taken, reason: 'not taken again');
    final bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, Offset(_left + outer.value + 5, _top + 5)),
      _mark,
    );
    expect(
      _pixelAt(tester, bytes, Offset(_left + at.value + 5, _top + 25)),
      _mark,
    );
  });

  testWidgets('🚨a tick inside a still tick, still when the strata were taken, '
      'is the one drawn live once it moves — the tick around it drew nothing '
      'new of its own', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    Widget inside(Widget tick) => SizedBox(
      width: 200,
      height: 40,
      child: TickLayer(
        child: Stack(
          children: [
            const Positioned(
              left: 150,
              top: 20,
              width: 40,
              height: 20,
              child: ColoredBox(color: _cover),
            ),
            Positioned(left: 0, top: 0, width: 140, height: 20, child: tick),
          ],
        ),
      ),
    );
    await _pump(tester, _regionWith(at, wrap: inside));
    final region = _region(tester);
    for (var i = 0; i < StillRaster.maxStillFrames * 2; i += 1) {
      if (region.debugDrawnFromImage) {
        break;
      }
      await _frame(tester);
    }
    expect(region.debugLiveTicks, isEmpty, reason: '⛔premise: all taken');

    at.value = 60;
    await tester.pump();
    await _moveUntilStill(tester, at);
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.debugLiveTicks, [const Size(140, 20)]);
  });

  group('the wait before an image follows how long the region stands '
      'still', () {
    /// [_regionWith]'s region with a ground that changes on [ground] — a
    /// change of the region's own, as a page turn is.
    Widget regionOf(ValueNotifier<Color> ground, ValueNotifier<double> at) =>
        StillRaster(
          debugLabel: 'test',
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<Color>(
                    valueListenable: ground,
                    builder: (context, color, _) => ColoredBox(color: color),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: 200,
                height: 40,
                child: TickLayer(child: CustomPaint(painter: _Mark(at))),
              ),
            ],
          ),
        );

    /// The frames until the region is drawn from its image — null when it
    /// is not within [limit].
    Future<int?> framesUntilDrawn(WidgetTester tester, int limit) async {
      for (var frame = 1; frame <= limit; frame += 1) {
        await _frame(tester);
        if (_region(tester).debugDrawnFromImage) {
          return frame;
        }
      }
      return null;
    }

    var shade = 0;
    Future<void> change(WidgetTester tester, ValueNotifier<Color> ground) {
      shade += 1;
      ground.value = Color(0xFF000000 | shade);
      return tester.pump();
    }

    /// Images thrown away the frame after they are first drawn, until the
    /// region waits the most it waits.
    Future<void> backOff(
      WidgetTester tester,
      ValueNotifier<Color> ground,
    ) async {
      for (var round = 0; round < 6; round += 1) {
        expect(
          await framesUntilDrawn(tester, StillRaster.maxStillFrames * 2),
          isNotNull,
          reason: '⛔premise: taken',
        );
        await change(tester, ground);
      }
    }

    testWidgets('🚨an image that lived long enough to pay brings the wait '
        'back to the shortest, however long it was', (tester) async {
      final at = ValueNotifier<double>(0);
      final ground = ValueNotifier<Color>(_ground);
      addTearDown(at.dispose);
      addTearDown(ground.dispose);
      await _pump(tester, regionOf(ground, at));
      await backOff(tester, ground);
      expect(
        await framesUntilDrawn(tester, StillRaster.maxStillFrames - 8),
        isNull,
        reason: '⛔premise: it waits the most',
      );
      expect(
        await framesUntilDrawn(tester, StillRaster.maxStillFrames),
        isNotNull,
      );
      for (var frame = 0; frame < StillRaster.framesToPay; frame += 1) {
        await _frame(tester);
      }

      await change(tester, ground);
      expect(
        await framesUntilDrawn(tester, StillRaster.stillFrames + 2),
        isNotNull,
        reason: 'it paid: the shortest wait again',
      );
    });

    testWidgets('🚨a region that changes sooner than it waits is taken again '
        'once it stood still long enough for an image to have paid', (
      tester,
    ) async {
      final at = ValueNotifier<double>(0);
      final ground = ValueNotifier<Color>(_ground);
      addTearDown(at.dispose);
      addTearDown(ground.dispose);
      await _pump(tester, regionOf(ground, at));
      await backOff(tester, ground);

      // A page every 20 frames — less than the most it waits.
      expect(
        await framesUntilDrawn(tester, 19),
        isNull,
        reason: '⛔premise: it waits the most',
      );
      await change(tester, ground);
      expect(await framesUntilDrawn(tester, 19), isNotNull);
    });

    testWidgets('🚨a tick that moved with the rest of the region is taken '
        'into the strata with it — not drawn live', (tester) async {
      final at = ValueNotifier<double>(0);
      final ground = ValueNotifier<Color>(_ground);
      addTearDown(at.dispose);
      addTearDown(ground.dispose);
      await _pump(tester, regionOf(ground, at));
      expect(
        await framesUntilDrawn(tester, StillRaster.maxStillFrames),
        isNotNull,
        reason: '⛔premise: taken',
      );

      // A page turn: the region and its tick change in the same frame.
      ground.value = _cover;
      at.value = 60;
      await tester.pump();
      expect(
        await framesUntilDrawn(tester, StillRaster.maxStillFrames),
        isNotNull,
      );
      expect(_region(tester).debugLiveTicks, isEmpty);
      expect(
        _pixelAt(
          tester,
          await captureBytes(tester),
          const Offset(_left + 65, _top + 5),
        ),
        _mark,
        reason: 'drawn from the stratum where it stood',
      );
    });
  });
}

class _LeftHalf extends CustomClipper<Rect> {
  const _LeftHalf();

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(_LeftHalf oldClipper) => false;
}
