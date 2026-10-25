import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show acrossBox, alongBox, extentAlong;
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/superellipse_clip.dart';

/// A bar's TRACK is ONE box (card frame-panels-build-in-one-frame,
/// 2026-10-25), where a probe of its length, a [DecoratedBox], a
/// [SuperellipseClip] and a [CustomPaint] were four.
///
/// Every case is asked of the box and of the four it replaced, and the two
/// must answer alike: the pixels, the size, the length handed to the
/// gesture math, where a pointer lands, and what the box says it needs.
void main() {
  const trackKey = ValueKey<String>('track');

  // A fill that reaches the frame's edge, so a corner the clip lost would
  // show, and writing over it, so the order would.
  final fill = _HalfFill(const Color(0xFF3355FF));
  const writing = Center(
    child: Text(
      '42%',
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
    ),
  );

  // The four, as the bar spelled them.
  Widget four({
    required Axis axis,
    required ShapeDecoration frame,
    required double radius,
    required ValueChanged<double> onExtent,
  }) => _ExtentProbe(
    axis: axis,
    onExtent: onExtent,
    child: DecoratedBox(
      decoration: frame,
      child: SuperellipseClip(
        shape: AppShapes.container(radius),
        child: CustomPaint(
          painter: fill,
          child: acrossBox(axis, 18, child: writing),
        ),
      ),
    ),
  );

  Widget one({
    required Axis axis,
    required ShapeDecoration frame,
    required double radius,
    required ValueChanged<double> onExtent,
  }) => FieldSliderTrack(
    axis: axis,
    onExtent: onExtent,
    frame: frame,
    fill: fill,
    shape: AppShapes.container(radius),
    child: acrossBox(axis, 18, child: writing),
  );

  Widget host(Widget track, {required Axis axis}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        child: ColoredBox(
          color: const Color(0xFF101010),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: alongBox(
              axis,
              120,
              child: KeyedSubtree(key: trackKey, child: track),
            ),
          ),
        ),
      ),
    ),
  );

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
  }

  ({
    Uint8List pixels,
    Size size,
    List<double> extents,
    List<bool> hits,
    List<double> intrinsics,
  })
  answersOf(
    WidgetTester tester,
    Uint8List drawn,
    List<double> extents,
  ) {
    final box = tester.renderObject<RenderBox>(find.byKey(trackKey));
    final size = box.size;
    bool hits(Offset local) {
      final result = BoxHitTestResult();
      return box.hitTest(result, position: local);
    }

    return (
      pixels: drawn,
      size: size,
      extents: List.of(extents),
      hits: [
        hits(size.center(Offset.zero)),
        // A cut corner, and a hair inside the silhouette at the same
        // corner.
        hits(const Offset(0.3, 0.3)),
        hits(const Offset(3, 3)),
        hits(Offset(size.width - 0.3, size.height - 0.3)),
      ],
      intrinsics: [
        box.getMinIntrinsicWidth(double.infinity),
        box.getMaxIntrinsicWidth(double.infinity),
        box.getMinIntrinsicHeight(double.infinity),
        box.getMaxIntrinsicHeight(double.infinity),
      ],
    );
  }

  for (final axis in Axis.values) {
    for (final enabled in [true, false]) {
      testWidgets('the track draws, sizes, reports and is hit as the four '
          'did — $axis, ${enabled ? 'enabled' : 'disabled'}', (tester) async {
        final frame = FieldSlider.frameOf(18, enabled: enabled);
        final radius = FieldSlider.radiusFor(18);

        final oldExtents = <double>[];
        await tester.pumpWidget(
          host(
            four(
              axis: axis,
              frame: frame,
              radius: radius,
              onExtent: oldExtents.add,
            ),
            axis: axis,
          ),
        );
        final old = answersOf(tester, await pixels(tester), oldExtents);

        await tester.pumpWidget(const SizedBox());
        final newExtents = <double>[];
        await tester.pumpWidget(
          host(
            one(
              axis: axis,
              frame: frame,
              radius: radius,
              onExtent: newExtents.add,
            ),
            axis: axis,
          ),
        );
        final now = answersOf(tester, await pixels(tester), newExtents);

        expect(now.size, old.size);
        expect(now.extents, old.extents);
        expect(now.extents, isNotEmpty, reason: 'fixture: a length came');
        expect(now.hits, old.hits);
        expect(now.hits.first, isTrue, reason: 'fixture: the middle is hit');
        expect(now.hits[1], isFalse, reason: 'fixture: the corner is cut');
        expect(now.intrinsics, old.intrinsics);
        expect(now.pixels, old.pixels);
      });
    }
  }

  testWidgets('a new value repaints the track and lays out nothing', (
    tester,
  ) async {
    var laidOut = 0;
    Widget at(double t) => host(
      FieldSliderTrack(
        axis: Axis.horizontal,
        onExtent: (_) => laidOut += 1,
        frame: FieldSlider.frameOf(18, enabled: true),
        fill: _HalfFill(const Color(0xFF3355FF), t: t),
        shape: AppShapes.container(FieldSlider.radiusFor(18)),
        child: acrossBox(Axis.horizontal, 18, child: writing),
      ),
      axis: Axis.horizontal,
    );
    await tester.pumpWidget(at(0.5));
    final box = tester.renderObject<RenderBox>(find.byKey(trackKey));
    final before = laidOut;

    await tester.pumpWidget(at(0.7));

    expect(
      box,
      paints..rect(
        rect: Rect.fromLTWH(0, 0, box.size.width * 0.7, 18),
        color: const Color(0xFF3355FF),
      ),
      reason: 'the fill moved',
    );
    expect(laidOut, before, reason: 'a fill is a paint, never a layout');
  });

  testWidgets('a bar mounts its track as one box — no frame, clip or '
      'painter of its own around it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: FieldSlider(
                value: 0.5,
                min: 0,
                max: 1,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final track = find.byType(FieldSliderTrack);
    expect(track, findsOneWidget);
    for (final kind in [DecoratedBox, SuperellipseClip, CustomPaint]) {
      expect(
        find.descendant(
          of: find.byType(FieldSlider),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType == kind &&
                find
                    .ancestor(
                      of: find.byWidget(widget),
                      matching: track,
                    )
                    .evaluate()
                    .isEmpty,
          ),
        ),
        findsNothing,
        reason: 'the track draws its own $kind',
      );
    }
  });
}

/// The fill a bar draws: the accent over the first [t] of the track.
class _HalfFill extends CustomPainter {
  _HalfFill(this.color, {this.t = 0.5});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * t, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HalfFill oldDelegate) =>
      oldDelegate.color != color || oldDelegate.t != t;
}

/// The probe the track replaced: its length, handed on as it is laid out.
class _ExtentProbe extends SingleChildRenderObjectWidget {
  const _ExtentProbe({
    required this.axis,
    required this.onExtent,
    required super.child,
  });

  final Axis axis;
  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExtentProbe(axis, onExtent);
}

class _RenderExtentProbe extends RenderProxyBox {
  _RenderExtentProbe(this.axis, this.onExtent);

  final Axis axis;
  final ValueChanged<double> onExtent;

  @override
  void performLayout() {
    super.performLayout();
    onExtent(extentAlong(axis, constraints.biggest));
  }
}
