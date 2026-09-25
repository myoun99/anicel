import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/panels/onion_skin_panel.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/raster_parity.dart';

/// A dock region drawn from ONE image while it stays the same
/// (유저 2026-09-25, raster-cache-when-still-Q1: 「가만히 있는 동안만 한
/// 장으로」) — and painted again the very frame anything in it changes.
///
/// The second half is the whole contract. A region that keeps drawing an
/// old image shows the user a panel that did not react, and nothing about
/// the pixels says so. So every way a region's content can change without
/// its own paint running — a nested boundary repainting, a layer property
/// moving, an ancestor moving it — is driven here and must show on the
/// next frame.
const double _left = 20;
const double _top = 20;
const double _width = 240;
const double _height = 200;

RenderStillRaster _region(WidgetTester tester) =>
    tester.renderObject<RenderStillRaster>(find.byType(StillRaster));

/// One frame with nothing asked of it — what a stroke on the canvas gives
/// every region beside it. A test binding draws a frame only when one was
/// asked for, and a region counts its stillness in frames.
Future<void> _frame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

/// Frames until the region draws from its image, and no more.
Future<void> _untilImage(WidgetTester tester) async {
  for (var i = 0; i < StillRaster.maxStillFrames * 2; i += 1) {
    if (_region(tester).debugDrawnFromImage) {
      return;
    }
    await _frame(tester);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Key? key,
  double left = _left,
}) =>
    pumpSurface(
      tester,
      StillRaster(key: key, debugLabel: 'test', child: child),
      left: left,
      width: _width,
      height: _height,
    );

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

const _red = Color(0xFFE53935);
const _blue = Color(0xFF1E88E5);

/// A box that is its own repaint boundary, so a property of a layer ABOVE
/// it can change while its picture stays exactly the one it was.
Widget _box({Color color = _red}) =>
    RepaintBoundary(child: ColoredBox(color: color));

class _Fill extends CustomPainter {
  _Fill(this.color) : super(repaint: color);

  final ValueNotifier<Color> color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color.value);
  }

  @override
  bool shouldRepaint(_Fill oldDelegate) => oldDelegate.color != color;
}

class _RectClip extends CustomClipper<Rect> {
  const _RectClip(this.inset);

  final double inset;

  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(inset);

  @override
  bool shouldReclip(_RectClip oldClipper) => oldClipper.inset != inset;
}

class _PathClip extends CustomClipper<Path> {
  const _PathClip(this.inset);

  final double inset;

  @override
  Path getClip(Size size) =>
      Path()..addOval((Offset.zero & size).deflate(inset));

  @override
  bool shouldReclip(_PathClip oldClipper) => oldClipper.inset != inset;
}

/// Every kind of layer a region can hold, each with a property that
/// changes WITHOUT the picture under it being recorded again — the one
/// change a region cannot see by its own paint, and has to see by its
/// layer tree.
final _layerChanges = <String, Widget Function(bool changed)>{
  'an opacity': (changed) =>
      Opacity(opacity: changed ? 0.3 : 0.8, child: _box()),
  'a transform': (changed) => Transform.scale(
    scale: changed ? 0.5 : 0.9,
    child: _box(),
  ),
  'a boundary moved inside the region': (changed) => Stack(
    children: <Widget>[
      Positioned(
        left: changed ? 120 : 10,
        top: 10,
        width: 60,
        height: 60,
        child: _box(),
      ),
    ],
  ),
  'a rectangular clip': (changed) => ClipRect(
    clipper: _RectClip(changed ? 60 : 4),
    child: _box(),
  ),
  'a rounded clip': (changed) => ClipRRect(
    borderRadius: BorderRadius.circular(changed ? 90 : 4),
    child: _box(),
  ),
  'a superellipse clip': (changed) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(changed ? 90 : 4),
    child: _box(),
  ),
  'a path clip': (changed) => ClipPath(
    clipper: _PathClip(changed ? 60 : 4),
    child: _box(),
  ),
  'a colour filter': (changed) => ColorFiltered(
    colorFilter: ColorFilter.mode(
      changed ? _blue : const Color(0xFF43A047),
      BlendMode.srcIn,
    ),
    child: _box(),
  ),
  'an image filter': (changed) => ImageFiltered(
    imageFilter: ui.ImageFilter.blur(
      sigmaX: changed ? 12 : 1,
      sigmaY: changed ? 12 : 1,
    ),
    child: _box(),
  ),
  'a shader mask': (changed) => ShaderMask(
    shaderCallback: (bounds) => LinearGradient(
      colors: changed
          ? const <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)]
          : const <Color>[Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    ).createShader(bounds),
    child: _box(),
  ),
  'a leader moved inside the region': (changed) => Padding(
    padding: EdgeInsets.only(left: changed ? 100 : 0),
    child: CompositedTransformTarget(link: _link, child: _box()),
  ),
};

final _link = LayerLink();

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Installed before the first region attaches, so the very first test
    // counts its frames the way every later one does.
    StaticRaster.ensureFrameClock();
  });

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    // Where the still images run, the bakes paint through (Impeller), and
    // a panel's own StaticRaster zones must not bake under a region here
    // either.
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
    StaticRaster.globallyEnabled.value = true;
    MeasurementMode.reset();
  });

  testWidgets('a region is taken after it stays the same, and only once', (
    tester,
  ) async {
    await _pump(tester, _box());
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isFalse);
    for (var still = 1; still <= StillRaster.stillFrames; still += 1) {
      await _frame(tester);
      expect(
        region.debugCaptureCount,
        still < StillRaster.stillFrames ? 0 : 1,
        reason: 'after $still still frames',
      );
    }
    expect(
      region.debugDrawnFromImage,
      isFalse,
      reason: 'the image is taken after the frame, and shows in the next',
    );
    await _frame(tester);
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.standDown, StillStandDown.none);
    for (var i = 0; i < 20; i += 1) {
      await _frame(tester);
    }
    expect(region.debugDrawnFromImage, isTrue);
    expect(region.debugCaptureCount, 1, reason: 'a still region is taken once');
  });

  testWidgets('its image is counted, and let go of with the region', (
    tester,
  ) async {
    await _pump(tester, _box());
    await _untilImage(tester);
    final ratio = tester.view.devicePixelRatio;
    expect(
      StillRaster.censusBytes,
      (_width * ratio).ceil() * (_height * ratio).ceil() * 4,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(StillRaster.census, isEmpty);
    expect(StillRaster.censusBytes, 0);
  });

  testWidgets('a nested boundary that repaints shows in the next frame', (
    tester,
  ) async {
    final color = ValueNotifier<Color>(_red);
    addTearDown(color.dispose);
    final child = RepaintBoundary(
      child: CustomPaint(painter: _Fill(color), size: Size.infinite),
    );
    await _pump(tester, child);
    await _untilImage(tester);
    expect(_region(tester).debugDrawnFromImage, isTrue);

    color.value = _blue;
    await tester.pump();
    expect(_region(tester).debugDrawnFromImage, isFalse);
    final bytes = await captureBytes(tester);
    expect(
      _pixelAt(tester, bytes, const Offset(_left + 100, _top + 100)),
      _blue,
      reason: 'the region kept showing its old image',
    );
  });

  group('a layer property that changes shows in the next frame', () {
    for (final MapEntry(key: what, value: build) in _layerChanges.entries) {
      testWidgets(what, (tester) async {
        await _pump(tester, build(false), key: const ValueKey('cached'));
        await _untilImage(tester);
        expect(
          _region(tester).debugDrawnFromImage,
          isTrue,
          reason: 'the region never took its image, so nothing was tested',
        );
        final before = await captureBytes(tester);

        await _pump(tester, build(true), key: const ValueKey('cached'));
        expect(_region(tester).debugDrawnFromImage, isFalse);
        final after = await captureBytes(tester);

        // The same change, painted by a region that never took an image.
        StillRaster.debugCachePaysOverride = false;
        await _pump(tester, build(true), key: const ValueKey('painted'));
        final painted = await captureBytes(tester);

        final width = (parityCaptureWidth * tester.view.devicePixelRatio)
            .round();
        final moved = compareRasters(
          before,
          after,
          width: width,
          tolerance: 0,
        );
        expect(
          moved.over,
          greaterThan(0),
          reason: 'the change moves no pixel, so this case proves nothing',
        );
        final shown = compareRasters(
          after,
          painted,
          width: width,
          tolerance: 0,
        );
        expect(
          shown.over,
          0,
          reason:
              'the frame after $what changed is not the frame painting '
              'shows: ${shown.over} pixels, worst ${shown.worst}, in '
              '${shown.where} (after vs painted: ${shown.samples})',
        );
      });
    }
  });

  group('content the layer tree cannot vouch for keeps it painting', () {
    final unvouched = <String, Widget>{
      'an external texture': const Texture(textureId: 7),
      'a backdrop filter': BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: _box(),
      ),
    };
    for (final MapEntry(key: what, value: child) in unvouched.entries) {
      testWidgets(what, (tester) async {
        await _pump(tester, child);
        for (var i = 0; i < 20; i += 1) {
          await _frame(tester);
        }
        final region = _region(tester);
        expect(region.debugCaptureCount, 0);
        expect(region.standDown, StillStandDown.unvouched);
      });
    }
  });

  testWidgets('where the engine keeps its own raster cache it never takes '
      'one', (tester) async {
    StillRaster.debugCachePaysOverride = false;
    await _pump(tester, _box());
    for (var i = 0; i < 20; i += 1) {
      await _frame(tester);
    }
    final region = _region(tester);
    expect(region.debugCaptureCount, 0);
    expect(region.standDown, StillStandDown.renderer);
  });

  testWidgets('the bake switch puts it back to painting, and back', (
    tester,
  ) async {
    await _pump(tester, _box());
    await _untilImage(tester);
    final region = _region(tester);
    expect(region.debugDrawnFromImage, isTrue);

    StaticRaster.globallyEnabled.value = false;
    await tester.pump();
    expect(region.debugDrawnFromImage, isFalse);
    expect(region.standDown, StillStandDown.disabled);
    expect(StillRaster.censusBytes, 0);

    StaticRaster.globallyEnabled.value = true;
    await _untilImage(tester);
    expect(region.debugDrawnFromImage, isTrue);
  });

  testWidgets('Show Repaints takes the image again, tinted', (tester) async {
    await _pump(tester, _box());
    await _untilImage(tester);
    final region = _region(tester);
    final untinted = await captureBytes(tester);

    MeasurementMode.showRepaints.value = true;
    await tester.pump();
    expect(region.debugDrawnFromImage, isFalse);
    await _untilImage(tester);
    final tinted = await captureBytes(tester);
    const probe = Offset(_left + 100, _top + 100);
    expect(
      _pixelAt(tester, tinted, probe),
      isNot(_pixelAt(tester, untinted, probe)),
    );
  });

  group('a region that moves', () {
    // Moved by an ancestor, the region's own layer is not re-added at all:
    // the ancestor's boundary moves, and everything under it is retained.
    Future<void> settleAt(
      WidgetTester tester,
      double left, {
      required bool byAncestor,
    }) {
      final region = StillRaster(debugLabel: 'test', child: _box());
      return pumpSurface(
        tester,
        byAncestor ? RepaintBoundary(child: region) : region,
        left: left,
        width: _width,
        height: _height,
      );
    }

    for (final byAncestor in <bool>[false, true]) {
      final who = byAncestor ? 'moved by an ancestor' : 'moved itself';

      testWidgets('$who by whole pixels keeps its image', (tester) async {
        await settleAt(tester, _left, byAncestor: byAncestor);
        await _untilImage(tester);
        final region = _region(tester);
        final taken = region.debugCaptureCount;

        await settleAt(tester, _left + 3, byAncestor: byAncestor);
        expect(region.debugDrawnFromImage, isTrue);
        expect(region.debugCaptureCount, taken);
      });

      testWidgets('$who onto a new sub-pixel phase paints again', (
        tester,
      ) async {
        // 🚨An image drawn half a pixel off the grid is a resample
        // (RasterGridFit), so it has to go the frame the region lands
        // there — however it got there.
        await settleAt(tester, _left, byAncestor: byAncestor);
        await _untilImage(tester);
        final region = _region(tester);
        expect(region.debugDrawnFromImage, isTrue);

        await settleAt(tester, _left + 0.5, byAncestor: byAncestor);
        expect(region.debugDrawnFromImage, isFalse);
      });
    }
  });

  group('a region that keeps changing', () {
    // A pointer sweeping across a row of buttons: still for a few frames,
    // then changed again. Each image thrown away before it paid for itself
    // is a whole render of the region for nothing.
    testWidgets('is not taken again and again', (tester) async {
      final color = ValueNotifier<Color>(_red);
      addTearDown(color.dispose);
      await _pump(
        tester,
        RepaintBoundary(
          child: CustomPaint(painter: _Fill(color), size: Size.infinite),
        ),
      );
      for (var frame = 0; frame < 100; frame += 1) {
        if (frame % 5 == 0) {
          color.value = frame % 10 == 0 ? _blue : _red;
        }
        await _frame(tester);
      }
      expect(_region(tester).debugCaptureCount, lessThanOrEqualTo(2));
    });

    testWidgets('waits the usual frames again once an image paid off', (
      tester,
    ) async {
      final color = ValueNotifier<Color>(_red);
      addTearDown(color.dispose);
      await _pump(
        tester,
        RepaintBoundary(
          child: CustomPaint(painter: _Fill(color), size: Size.infinite),
        ),
      );
      final region = _region(tester);
      // Taken, then changed right away: the next one waits longer.
      await _untilImage(tester);
      color.value = _blue;
      await _frame(tester);

      Future<int> framesUntilTaken() async {
        final taken = region.debugCaptureCount;
        for (var frames = 1; frames <= StillRaster.maxStillFrames; frames++) {
          await _frame(tester);
          if (region.debugCaptureCount > taken) {
            return frames;
          }
        }
        return -1;
      }

      expect(
        await framesUntilTaken(),
        2 * StillRaster.stillFrames,
        reason: 'an image thrown away at once doubles the wait',
      );
      // Drawn long enough to pay for itself, then changed.
      for (var i = 0; i < StillRaster.maxStillFrames; i += 1) {
        await _frame(tester);
      }
      color.value = _red;
      await _frame(tester);
      expect(await framesUntilTaken(), StillRaster.stillFrames);
    });
  });

  // ─── pixels ─────────────────────────────────────────────────────────
  //
  // An image composited from an offscreen is not bit-for-bit what
  // painting in place gives — the price the user took (「가만히 있는 동안만
  // 한 장으로」: 251 of 3.46 million window pixels, none by more than 5/255,
  // measured on the real app). What must never happen is the image being a
  // RESAMPLE: that moves whole rows and columns, and the sweeps below walk
  // exactly the geometry that produces one (the rule and its history are in
  // static_raster_parity_test.dart).

  Widget onionPanel() => OnionSkinPanel(
    settings: const OnionSkinSettings(),
    currentColorOf: () => 0xFF000000,
    onChanged: (_) {},
  );

  Future<void> expectParity(
    WidgetTester tester,
    Widget child, {
    required String what,
    double left = _left,
    double width = 240,
  }) async {
    StillRaster.debugCachePaysOverride = true;
    final fromImage = await surfaceBytes(
      tester,
      StillRaster(
        key: const ValueKey('image'),
        debugLabel: 'parity',
        child: child,
      ),
      left: left,
      width: width,
      height: 240,
      settle: () => _untilImage(tester),
    );
    expect(
      _region(tester).debugDrawnFromImage,
      isTrue,
      reason: '$what never took its image, so nothing was compared',
    );
    StillRaster.debugCachePaysOverride = false;
    final painted = await surfaceBytes(
      tester,
      StillRaster(
        key: const ValueKey('painted'),
        debugLabel: 'parity',
        child: child,
      ),
      left: left,
      width: width,
      height: 240,
      settle: tester.pumpAndSettle,
    );
    final ratio = tester.view.devicePixelRatio;
    final result = compareRasters(
      fromImage,
      painted,
      width: (parityCaptureWidth * ratio).round(),
      tolerance: parityRoundingTolerance,
    );
    expect(
      result.over,
      lessThanOrEqualTo(parityTieBudget),
      reason:
          '$what looks different drawn from its image than painted.\n'
          'ratio $ratio, box ${width}x240 at left $left\n'
          '${result.over} pixels beyond the rounding floor, worst channel '
          '${result.worst}, in ${result.where}\n'
          'Samples (image vs painted): ${result.samples}',
    );
  }

  testWidgets('the image really is being aligned', (tester) async {
    // The fixture-reaches-the-defect guard: every sweep below is vacuous
    // if the region happens to land on the grid anyway.
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, onionPanel(), left: _left + 1 / 3);
    await _untilImage(tester);
    expect(_region(tester).debugGridShift, isNot(Offset.zero));
  });

  testWidgets('what a child paints outside the region is clipped the same '
      'either way', (tester) async {
    // The image covers the region's box and nothing else, so painting
    // clips to that box too — the two ways of showing it cannot disagree
    // about what is inside.
    await expectParity(
      tester,
      const OverflowBox(
        maxWidth: 900,
        maxHeight: 900,
        child: SizedBox(
          width: 900,
          height: 900,
          child: ColoredBox(color: Color(0xFFFF0000)),
        ),
      ),
      what: 'a child painting far outside its box',
    );
  });

  testWidgets('the tool column draws the same from its image', (
    tester,
  ) async {
    await expectParity(
      tester,
      ToolsPanel(tool: CanvasTool.brush, onPress: (_) {}),
      what: 'the tool column',
    );
  });

  for (final ratio in <double>[1.0, 1.25, 1.5, 1.75, 2.0]) {
    testWidgets('the onion panel draws the same at device ratio $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      await expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel at device ratio $ratio',
      );
    });
  }

  testWidgets('a region on a fractional pixel draws the same', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var eighth = 0; eighth < 8; eighth += 1) {
      await expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel at left 20 + $eighth/8',
        left: _left + eighth / 8,
      );
    }
  });

  testWidgets('a region of fractional device size draws the same', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in <double>[240, 240 + 1 / 3, 240.5, 240.75, 241]) {
      await expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel $width wide',
        width: width,
      );
    }
  });
}
