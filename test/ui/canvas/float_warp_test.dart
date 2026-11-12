import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/straight_rgba_image.dart'
    show straightRgbaOf;
import 'package:anicel/src/services/stamp_carry.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/float_warp.dart';
import 'package:anicel/src/ui/canvas/transform_box.dart';

/// Where the open box puts the float, read without a selection layer
/// around it: [FloatWarp]'s geometry, and the [FloatResamplePreview] that
/// resamples through it.
///
/// Each of these was a line nothing failed for while it lived inside the
/// layer's state — the move to a file of its own is what made them
/// reachable one at a time.
void main() {
  // A 40×20 float centred at (100, 50): its rect is (80, 40)–(120, 60).
  BrushDab float() => BrushDab(
    center: CanvasPoint(x: 100, y: 50),
    color: 0xFF000000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'float',
      width: 40,
      height: 20,
      rgba: Uint8List.fromList(List<int>.filled(40 * 20 * 4, 255)),
    ),
  );

  // The wall cuts the float's scaled rect on the LEFT only.
  final wall = DirtyRegion(
    left: 70,
    top: 0,
    rightExclusive: 1000,
    bottomExclusive: 1000,
  );

  TransformBox box({double scale = 1, double tx = 0, double ty = 0}) =>
      TransformBox(
        affine: SelectionAffine(
          pivot: CanvasPoint(x: 100, y: 50),
          sx: scale,
          sy: scale,
          tx: tx,
          ty: ty,
        ),
        baseWidth: 40,
        baseHeight: 20,
      );

  FloatWarp warp(
    TransformBox box, {
    TransformMode mode = TransformMode.normal,
  }) => FloatWarp(
    box: box,
    float: float(),
    options: TransformToolOptions(mode: mode),
    pasteboard: wall,
  );

  final zero = CanvasPoint(x: 0, y: 0);

  test('a quad corner sits where its offset moves it, on both axes', () {
    final open = box();
    open.warp.corners = [CanvasPoint(x: 5, y: -3), zero, zero, zero];

    final corner = warp(open, mode: TransformMode.perspective).placedCorners!
        .first;

    expect((corner.x, corner.y), (85.0, 37.0));
  });

  test('an affine lands the float in the affine\'s rect, not its own', () {
    final out = warp(box(scale: 2)).outputRect();

    expect(out, (left: 60, top: 30, width: 80, height: 40));
  });

  test('the mesh ring walks every edge: top, right, bottom, left', () {
    final open = box();
    open.warp.meshColumns = 2;
    open.warp.meshRows = 2;
    // Point i is at x = i, so the ring reads back as grid indices.
    final points = [
      for (var i = 0; i < 9; i += 1) CanvasPoint(x: i * 1.0, y: 0),
    ];

    final ring = warp(open, mode: TransformMode.mesh).meshBoundary(points);

    expect(
      [for (final point in ring) point.x.toInt()],
      [0, 1, 2, 5, 8, 7, 6, 3],
    );
  });

  /// `a-warp-over-a-frame-range-lands-on-one-cel` (2026-10-06): what the
  /// open box hands the cels a range confirm reaches — the mapping the
  /// float itself goes through, whichever of the three it is.
  group('what the open box does, for any stamp on the canvas', () {
    TransformBox quadBox() =>
        box()..warp.corners = [CanvasPoint(x: 5, y: -3), zero, zero, zero];
    TransformBox meshBox() => box()
      ..warp.meshColumns = 2
      ..warp.meshRows = 2
      ..warp.mesh = [
        for (var i = 0; i < 9; i += 1)
          if (i == 4) CanvasPoint(x: 3, y: 2) else zero,
      ];

    test('it is the shape the box is in', () {
      expect(warp(box(scale: 2)).carry, isA<AffineCarry>());
      expect(
        warp(quadBox(), mode: TransformMode.perspective).carry,
        isA<QuadCarry>(),
      );
      expect(warp(meshBox(), mode: TransformMode.mesh).carry, isA<MeshCarry>());
    });

    test('🚨F-570: 퍼스 and 메쉬 stand on the box 일반 draws, not on the '
        'pixels the float holds past it', () {
      // The float is 40×20 at (80, 40); the box framing the selection it
      // was lifted from is 30×10 inside it — the lift rounds out to whole
      // pixels and a grow or a feather widens it.
      TransformBox inside() => TransformBox(
        affine: SelectionAffine(pivot: CanvasPoint(x: 100, y: 50)),
        baseWidth: 30,
        baseHeight: 10,
      );
      const drawn = (left: 85.0, top: 45.0, width: 30.0, height: 10.0);
      final quad = warp(
        inside()..warp.corners = [CanvasPoint(x: 5, y: -3), zero, zero, zero],
        mode: TransformMode.perspective,
      );
      final mesh = warp(
        inside()
          ..warp.meshColumns = 2
          ..warp.meshRows = 2
          ..warp.mesh = [
            for (var i = 0; i < 9; i += 1)
              if (i == 4) CanvasPoint(x: 3, y: 2) else zero,
          ],
        mode: TransformMode.mesh,
      );

      expect(quad.baseCorners(), cornersOfStampRect(drawn));
      expect((quad.carry! as QuadCarry).base, cornersOfStampRect(drawn));
      expect(
        quad.placedCorners!.skip(1),
        cornersOfStampRect(drawn).skip(1),
        reason: 'the corners no offset moved are the box\'s own',
      );
      expect((mesh.carry! as MeshCarry).base, drawn);
    });

    test('a box that changes no pixel carries nothing', () {
      expect(warp(box()).carry, isNull);
      expect(warp(box(), mode: TransformMode.perspective).carry, isNull);
      expect(warp(box(), mode: TransformMode.mesh).carry, isNull);
    });

    test('🚨it stops at the pasteboard wall — another cel\'s picture is not '
        'resampled past it either', () {
      for (final carry in [
        warp(box(scale: 2)).carry!,
        warp(quadBox(), mode: TransformMode.perspective).carry!,
        warp(meshBox(), mode: TransformMode.mesh).carry!,
      ]) {
        expect(
          carry.within,
          (left: 70.0, top: 0.0, right: 1000.0, bottom: 1000.0),
          reason: '${carry.runtimeType}',
        );
      }
    });

    test('the float through it is what the commit lands', () {
      final open = warp(box(scale: 2));
      final preview = FloatResamplePreview(_Host(), () => open);
      addTearDown(preview.discard);

      final landed = preview.warped()!;
      final carried = open.carry!.through(float());

      expect(carried.center, landed.center);
      expect(carried.stamp!.rgba, landed.stamp!.rgba);
    });
  });

  group('the preview through the warp', () {
    late _Host host;
    late FloatResamplePreview preview;

    setUp(() {
      host = _Host();
      final open = warp(box(scale: 2));
      preview = FloatResamplePreview(host, () => open);
      addTearDown(preview.discard);
    });

    testWidgets('a screen window reaching past the wall is cut at the wall', (
      tester,
    ) async {
      host.visible = (left: -500, top: -500, right: 500, bottom: 500);

      preview.schedule();
      await tester.pump();

      expect(
        debugLastResampledFloat!.stamp!.width,
        140 - 70,
        reason: 'the scaled rect is 60–140; nothing is resampled left of 70',
      );
    });

    testWidgets('the commit never lands the window the preview drew', (
      tester,
    ) async {
      host.visible = (left: 100, top: -500, right: 500, bottom: 500);
      preview.schedule();
      await tester.pump();
      expect(
        debugLastResampledFloat!.stamp!.width,
        140 - 100,
        reason: 'the premise: the preview drew a window of the rect',
      );

      expect(
        preview.warped()!.stamp!.width,
        140 - 70,
        reason: 'the commit resamples the whole rect up to the wall',
      );
    });
  });

  group('🚨a move is not uploaded '
      '(a-drag-in-an-open-box-resamples-a-move)', () {
    // One float, as a session holds it through every state of its box.
    final lifted = float();
    FloatWarp over(TransformBox box) => FloatWarp(
      box: box,
      float: lifted,
      options: TransformToolOptions.defaults,
      pasteboard: wall,
    );

    testWidgets('a box that only moves the float shows no resample of its '
        'own — the float\'s pixels draw it — and lands it moved', (
      tester,
    ) async {
      final now = over(box(tx: 40, ty: 30));
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);

      preview.schedule();
      await tester.pump();

      expect(preview.shown, isNull);
      final landed = preview.warped()!;
      expect(landed.center, CanvasPoint(x: 140, y: 80));
      expect(landed.stamp, same(lifted.stamp), reason: 'its own picture');
    });

    testWidgets('a resample shown for a scale is let go once the box only '
        'moves again', (tester) async {
      var now = over(box(scale: 2));
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);
      preview.schedule();
      await tester.pump();
      expect(
        preview.shown,
        isNotNull,
        reason: '⛔premise: a scale shows its resample',
      );

      now = over(box(tx: 40, ty: 30));
      preview.schedule();
      await tester.pump();

      expect(preview.shown, isNull);
    });

    testWidgets('🚨the resample shown holds itself as tiles where it lands '
        '— what the engine lays (flip lane ⓐ-2)', (tester) async {
      final now = over(box(scale: 2));
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);
      preview.schedule();
      await tester.pump();

      final FloatResampleShown(:dab, :landing, :tiles) = preview.shown!;
      final stamp = dab.stamp!;
      expect(landing, stamp.landingRect(dab.center));
      expect(
        bitmapSurfaceRegionPixels(
          BitmapSurface(
            canvasSize: const CanvasSize(width: 1000, height: 1000),
            tiles: tiles,
          ),
          landing,
        ),
        stamp.rgba,
      );
    });

    testWidgets('a resample asked for as the box ends is never shown — '
        'letting go takes the ask with it', (tester) async {
      final now = over(box(scale: 2));
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);
      preview.schedule();

      preview.discard();
      await tester.pump();

      expect(preview.shown, isNull);
    });
  });

  // 🧭관제 2026-11-11 18:47 (a-float-premultiplies-in-the-c-each-step):
  // 「플로트를 엔진에 놓아 … Flutter 표시용 디코드 자체를 없애는 쪽」 — and
  // one resample a frame, the last the hand asked for, where one upload at
  // a time had paced it.
  group('what an open box shows, a frame at a time', () {
    FloatWarp scaled(double by) => FloatWarp(
      box: box(scale: by),
      float: float(),
      options: TransformToolOptions.defaults,
      pasteboard: wall,
    );

    testWidgets('every ask before the frame ends waits for it, and the last '
        'is what runs', (tester) async {
      var now = scaled(2);
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);
      debugLastResampledFloat = null;

      preview.schedule();
      now = scaled(3);
      preview.schedule();

      expect(debugLastResampledFloat, isNull, reason: 'nothing ran yet');
      expect(preview.caughtUp, isFalse);
      await tester.pump();

      expect(preview.caughtUp, isTrue);
      expect(
        debugLastResampledFloat!.stamp!.height,
        20 * 3,
        reason: 'the box as it is when the frame ends — the wall cuts its '
            'width, not its height',
      );
      expect(preview.shown!.dab, same(debugLastResampledFloat));
    });

    testWidgets('🚨the resample shown is pictured for no one till a canvas '
        'draws it', (tester) async {
      final preview = FloatResamplePreview(_Host(), () => scaled(2));
      addTearDown(preview.discard);
      preview.schedule();
      await tester.pump();
      final shown = preview.shown!;

      expect(shown.debugPictured, isFalse);
      // CONTROL: a canvas that draws pictures asks — and gets the dab's
      // pixels, where it lands: its alpha exactly, and its colour where
      // it is whole (a straight read of a premultiplied picture rounds a
      // part-clear one).
      final picture = shown.picture;
      expect(shown.debugPictured, isTrue);
      expect(
        (picture.width, picture.height),
        (shown.landing.width, shown.landing.height),
      );
      final read = (await tester.runAsync(() => straightRgbaOf(picture)))!;
      final rgba = shown.dab.stamp!.rgba;
      expect(read.length, rgba.length);
      for (var at = 0; at < rgba.length; at += 4) {
        final alpha = rgba[at + 3];
        expect(
          alpha == 255 ? read.sublist(at, at + 4) : read[at + 3],
          alpha == 255 ? rgba.sublist(at, at + 4) : alpha,
          reason: 'pixel ${at ~/ 4}',
        );
      }
    });

    testWidgets('a picture made is let go once its resample is shown no '
        'more — another taking its place, or the box ending', (tester) async {
      var now = scaled(2);
      final preview = FloatResamplePreview(_Host(), () => now);
      addTearDown(preview.discard);
      Future<ui.Image> pictured() async {
        preview.schedule();
        await tester.pump();
        return preview.shown!.picture;
      }

      Future<void> pastTheFramesThatMayDrawIt() async {
        for (var frame = 0; frame < 4; frame += 1) {
          await tester.pump();
        }
      }

      final replaced = await pictured();
      now = scaled(3);
      final ended = await pictured();
      expect(replaced.debugDisposed, isFalse, reason: '⛔CONTROL: not yet');
      await pastTheFramesThatMayDrawIt();
      expect(replaced.debugDisposed, isTrue, reason: 'another took its place');

      preview.discard();
      expect(ended.debugDisposed, isFalse, reason: '⛔CONTROL: not yet');
      await pastTheFramesThatMayDrawIt();
      expect(ended.debugDisposed, isTrue, reason: 'the box ended');
    });
  });
}

class _Host implements FloatWarpHost {
  SelectionVisibleRect? visible;

  @override
  SelectionVisibleRect? previewVisibleRect() => visible;

  @override
  void previewChanged() {}
}
