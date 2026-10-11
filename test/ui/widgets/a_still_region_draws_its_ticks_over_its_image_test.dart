import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/raster_parity.dart';

/// 🚨WHAT A TICK MOVES IS DRAWN OVER A STILL REGION'S IMAGE, NOT IN IT
/// (10-12): a cut playing changed the timeline's dock on every film frame —
/// its cursor, its playhead's writing, its counter, each on a tick layer of
/// its own — so the region was never still, and every frame drew all of it
/// again (the side rails, which hold no tick, came from their images on 75
/// frames of 75; the timeline's dock on none).
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

Future<void> _untilImage(WidgetTester tester) async {
  for (var i = 0; i < StillRaster.maxStillFrames * 2; i += 1) {
    if (_region(tester).debugDrawnFromImage) {
      return;
    }
    await _frame(tester);
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
}) {
  final tick = TickLayer(child: CustomPaint(painter: _Mark(at)));
  return StillRaster(
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

  testWidgets('🚨a region whose only change is a tick stays drawn from its '
      'image — and the tick moves over it, leaving no trace where it was', (
    tester,
  ) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(tester, _regionWith(at));
    await _untilImage(tester);
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise: still');

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
        _pixelAt(tester, bytes, const Offset(_left + 5, _top + 5)),
        x == 0 ? _mark : _ground,
        reason: 'the image holds no tick of its own',
      );
    }
    expect(region.debugCaptureCount, 1, reason: 'the image was not retaken');
  });

  testWidgets('🚨a tick something painted after it covers keeps the region '
      'painting — over the image it would cover what covered it', (
    tester,
  ) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        after: const Positioned(
          left: 0,
          top: 0,
          width: 100,
          height: 100,
          child: RepaintBoundary(child: ColoredBox(color: _cover)),
        ),
      ),
    );
    await _untilImage(tester);

    expect(_region(tester).debugDrawnFromImage, isFalse);
    expect(_region(tester).standDown, StillStandDown.unvouched);
    final bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 5, _top + 5)),
      _cover,
      reason: 'what is painted after the tick stays over it',
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
    await _untilImage(tester);

    expect(_region(tester).debugDrawnFromImage, isTrue);
  });

  testWidgets('a tick under a transform keeps the region painting — it cannot '
      'be put back over the image as it was', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        wrap: (tick) => Transform.scale(scale: 0.5, child: tick),
      ),
    );
    await _untilImage(tester);

    expect(_region(tester).debugDrawnFromImage, isFalse);
    expect(_region(tester).standDown, StillStandDown.unvouched);
  });

  testWidgets('🚨a tick under a clip is clipped over the image as it was in '
      'place', (tester) async {
    final at = ValueNotifier<double>(0);
    addTearDown(at.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        wrap: (tick) => ClipRect(
          clipper: const _LeftHalf(),
          child: tick,
        ),
      ),
    );
    await _untilImage(tester);
    expect(_region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');

    at.value = 150;
    await tester.pump();

    expect(_region(tester).debugDrawnFromImage, isTrue);
    final bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 155, _top + 5)),
      _ground,
      reason: 'past the clip the tick does not show, over the image either',
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

  testWidgets('🚨the frame the rest of the region changes, a tick inside a '
      'layer of its own still shows — the image\'s scene left it out of that '
      'layer, and the next scene builds the layer again', (tester) async {
    final at = ValueNotifier<double>(0);
    final elsewhere = ValueNotifier<Color>(_ground);
    addTearDown(at.dispose);
    addTearDown(elsewhere.dispose);
    await _pump(
      tester,
      _regionWith(
        at,
        wrap: (tick) => RepaintBoundary(child: tick),
        after: Positioned(
          left: 0,
          top: 120,
          width: 100,
          height: 40,
          child: RepaintBoundary(
            child: ValueListenableBuilder<Color>(
              valueListenable: elsewhere,
              builder: (context, color, child) => ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
    await _untilImage(tester);
    expect(_region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');

    elsewhere.value = _cover;
    await tester.pump();

    expect(_region(tester).debugDrawnFromImage, isFalse, reason: '⛔premise');
    expect(
      _pixelAt(
        tester,
        await captureBytes(tester),
        const Offset(_left + 5, _top + 5),
      ),
      _mark,
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
}

class _LeftHalf extends CustomClipper<Rect> {
  const _LeftHalf();

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(_LeftHalf oldClipper) => false;
}
