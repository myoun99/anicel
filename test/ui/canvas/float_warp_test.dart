import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/canvas_selection.dart';
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

  TransformBox box({double scale = 1}) => TransformBox(
    affine: SelectionAffine(
      pivot: CanvasPoint(x: 100, y: 50),
      sx: scale,
      sy: scale,
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
      final host = _Host(open);
      final preview = FloatResamplePreview(host);
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
      host = _Host(warp(box(scale: 2)));
      preview = FloatResamplePreview(host);
      addTearDown(preview.discard);
    });

    testWidgets('a screen window reaching past the wall is cut at the wall', (
      tester,
    ) async {
      host.visible = (left: -500, top: -500, right: 500, bottom: 500);

      preview.schedule();

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
}

class _Host implements FloatWarpHost {
  _Host(this.floatWarp);

  @override
  final FloatWarp floatWarp;

  SelectionVisibleRect? visible;

  @override
  bool get mounted => true;

  @override
  SelectionVisibleRect? previewVisibleRect() => visible;

  @override
  void previewChanged() {}
}
