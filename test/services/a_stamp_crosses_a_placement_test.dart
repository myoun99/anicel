// A STAMP CROSSES A ROW'S PLACEMENT AS THE AFFINE IT IS.
//
// A lift takes a posed row's pixels out onto the canvas and a landing puts
// them back (`selection_placement.dart`, a-marquee-on-a-posed-row). The
// crossing was the transform box's own affine built from the pose's numbers
// — a scale about a pivot, then a turn — which says a moved, an evenly
// scaled and a turned row and nothing else.
//
// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
// 반전)」. A row flipped by its lane, a row stretched along one axis, and a
// row under a folder that stretches it askew all lie on the canvas by an
// affine that box cannot say — and the way BACK through a row scaled an
// axis apiece and turned is not one either. These pin the crossing itself.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show placementUnderFolders;
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/services/selection_placement.dart';

import '../helpers/placement_reading.dart';

void main() {
  const canvas = CanvasSize(width: 64, height: 48);
  final centre = CanvasPoint(x: 10, y: 10);

  const red = [255, 0, 0, 255];
  const green = [0, 255, 0, 255];
  const blue = [0, 0, 255, 255];
  const white = [255, 255, 255, 255];

  /// A 2×2 stamp about (10, 10), four distinct opaque colours:
  ///   R G
  ///   B W
  BrushDab stampDab() => BrushDab(
    center: centre,
    color: 0xFFFFFFFF,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'stamp',
      width: 2,
      height: 2,
      rgba: Uint8List.fromList([...red, ...green, ...blue, ...white]),
    ),
  );

  List<List<int>> pixelsOf(BrushDab dab) {
    final stamp = dab.stamp!;
    return [
      for (var i = 0; i < stamp.width * stamp.height; i += 1)
        stamp.rgba.sublist(i * 4, i * 4 + 4),
    ];
  }

  /// A row posed about the stamp's own centre, so a turn or a mirror keeps
  /// the stamp where it is and only its pixels change places.
  LayerPlacement posedAboutTheStamp(TransformPose pose) =>
      placedBy(pose, canvas, anchorPoint: centre);

  test('an unplaced row hands the stamp back as it is, both ways', () {
    final dab = stampDab();

    expect(identical(stampOnCanvas(dab, null), dab), isTrue);
    expect(identical(stampInArtwork(dab, null), dab), isTrue);
  });

  test('a row only MOVED crosses by moving the centre: the same bytes '
      'travel out and come back where they were', () {
    final dab = stampDab();
    final moved = placedBy(
      TransformPose(
        center: CanvasPoint(x: canvas.width / 2 + 7, y: canvas.height / 2 - 3),
      ),
      canvas,
    );

    final out = stampOnCanvas(dab, moved);

    expect(out.center, CanvasPoint(x: 17, y: 7));
    expect(identical(out.stamp!.rgba, dab.stamp!.rgba), isTrue);
    final back = stampInArtwork(out, moved);
    expect(back.center, centre);
    expect(identical(back.stamp!.rgba, dab.stamp!.rgba), isTrue);
  });

  test('a row turned a QUARTER crosses pixel for pixel, and comes back the '
      'bytes it was — the turn is the table\'s, not the library\'s', () {
    final dab = stampDab();
    final turned = posedAboutTheStamp(
      TransformPose(center: centre, rotationDegrees: 90),
    );

    final out = stampOnCanvas(dab, turned);

    // Clockwise on a y-down canvas: R G / B W  →  B R / W G.
    expect(out.center, centre);
    expect((out.stamp!.width, out.stamp!.height), (2, 2));
    expect(pixelsOf(out), [blue, red, white, green]);
    final back = stampInArtwork(out, turned);
    expect(back.center, centre);
    expect(pixelsOf(back), [red, green, blue, white]);
  });

  test('🚨a row FLIPPED by its lane crosses mirrored, byte for byte, and '
      'comes back the bytes it was', () {
    final dab = stampDab();
    final flipped = posedAboutTheStamp(
      TransformPose(center: centre, scaleX: -1),
    );

    final out = stampOnCanvas(dab, flipped);

    expect(out.center, centre);
    expect((out.stamp!.width, out.stamp!.height), (2, 2));
    expect(pixelsOf(out), [green, red, white, blue]);
    final back = stampInArtwork(out, flipped);
    expect(back.center, centre);
    expect(pixelsOf(back), [red, green, blue, white]);
  });

  test('🚨a row scaled an axis apiece AND turned: the way back is S⁻¹·R⁻¹, '
      'which no scale-then-turn says — the stamp comes back the size and '
      'the place it left', () {
    final dab = stampDab();
    final stretchedAndTurned = posedAboutTheStamp(
      TransformPose(center: centre, scaleX: 2, rotationDegrees: 90),
    );

    final out = stampOnCanvas(dab, stretchedAndTurned);

    // Twice as wide, then turned a quarter: 2×2 shows 2 wide, 4 tall.
    expect(out.center, centre);
    expect((out.stamp!.width, out.stamp!.height), (2, 4));
    final back = stampInArtwork(out, stretchedAndTurned);
    expect(back.center, centre);
    expect((back.stamp!.width, back.stamp!.height), (2, 2));
    // Each pixel is still the colour it was: the dominant channel survives
    // the two resamples (the tent feathers a doubled pixel, nothing more).
    expect(
      [for (final pixel in pixelsOf(back)) _dominant(pixel)],
      ['r', 'g', 'b', 'w'],
    );
  });

  test('🚨a folder stretched along one axis over a turned row SHEARS it — '
      'the stamp crosses to the box round where the placement shows it',
      () {
    final LayerPoseSample stretched = (
      pose: TransformPose(
        center: CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
        scaleX: 2,
      ),
      anchorPoint: null,
    );
    final LayerPoseSample askew = (
      pose: TransformPose(center: centre, rotationDegrees: 45),
      anchorPoint: centre,
    );
    final sheared = placementUnderFolders(
      folderPoses: [stretched],
      layerSample: askew,
      canvasSize: canvas,
    )!;
    final corners = [
      for (final (x, y) in [(9.0, 9.0), (11.0, 9.0), (11.0, 11.0), (9.0, 11.0)])
        sheared.apply(CanvasPoint(x: x, y: y)),
    ];
    final xs = [for (final corner in corners) corner.x];
    final ys = [for (final corner in corners) corner.y];
    int floorOf(Iterable<double> values) =>
        values.reduce((a, b) => a < b ? a : b).floor();
    int ceilOf(Iterable<double> values) =>
        values.reduce((a, b) => a > b ? a : b).ceil();

    final out = stampOnCanvas(stampDab(), sheared);

    expect(out.stamp!.width, ceilOf(xs) - floorOf(xs));
    expect(out.stamp!.height, ceilOf(ys) - floorOf(ys));
    expect(
      out.center,
      CanvasPoint(
        x: floorOf(xs) + out.stamp!.width / 2,
        y: floorOf(ys) + out.stamp!.height / 2,
      ),
    );
    // And it is the picture, not an empty box: ink landed in it.
    expect(
      pixelsOf(out).where((pixel) => pixel[3] > 0),
      isNotEmpty,
    );
  });
}

/// The channel a pixel is mostly — `w` for one that is all three.
String _dominant(List<int> pixel) {
  final [r, g, b, _] = pixel;
  if (r > 128 && g > 128 && b > 128) {
    return 'w';
  }
  return r >= g && r >= b ? 'r' : (g >= b ? 'g' : 'b');
}
