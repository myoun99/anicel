import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';

/// The camera geometry the conte and the camera row share (유저 2026-09-30:
/// 「이 꼭짓점 궤도 그리는건 카메라레이어에서도 나중에 쓸거니까 공용화 잘
/// 해주고」): a camera's frame at each key, the trail each corner draws, the
/// canvas they sweep — and a view that shows exactly a region of it.
void main() {
  const size = CanvasSize(width: 160, height: 90);

  CameraPose at(double x, double y, {double zoom = 1, double turn = 0}) =>
      CameraPose(
        center: CanvasPoint(x: x, y: y),
        zoom: zoom,
        rotationDegrees: turn,
      );

  void expectPoints(List<Offset> actual, List<Offset> expected) {
    expect(actual, hasLength(expected.length));
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-9), reason: 'x $index');
      expect(actual[index].dy, closeTo(point.dy, 1e-9), reason: 'y $index');
    }
  }

  List<Offset> cornersOf(Rect rect) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  test('the keys inside a span, in frame order, each as the frame the camera '
      'shows there', () {
    final frames = cameraKeyFrames(
      {12: at(240, 45), 0: at(80, 45), 30: at(400, 45), 6: at(160, 45)},
      size,
      from: 0,
      toExclusive: 24,
    );
    expect(frames.map((frame) => frame.frameIndex), [0, 6, 12]);
    expectPoints(
      frames.first.corners,
      cornersOf(const Rect.fromLTRB(0, 0, 160, 90)),
    );
    expectPoints(
      cameraKeyFrames({0: at(80, 45, zoom: 2)}, size).single.corners,
      cornersOf(const Rect.fromLTRB(40, 22.5, 120, 67.5)),
    );
  });

  test('each corner draws its own trail through every key — four, top-left '
      'first — and the canvas they sweep holds every corner', () {
    final frames = [
      for (final frame in cameraKeyFrames({
        0: at(80, 45),
        6: at(160, 90, turn: 90),
        12: at(240, 45),
      }, size))
        frame.corners,
    ];
    final trails = cameraCornerTrails(frames);
    expect(trails, hasLength(4));
    for (var corner = 0; corner < 4; corner += 1) {
      expectPoints(trails[corner], [
        for (final frame in frames) frame[corner],
      ]);
    }
    final bounds = cameraFramesBounds(frames);
    for (final frame in frames) {
      for (final corner in frame) {
        expect(
          bounds.inflate(1e-9).contains(corner),
          isTrue,
          reason: '$corner inside $bounds',
        );
      }
    }
    expect(bounds.left, closeTo(0, 1e-9));
    expect(bounds.right, closeTo(320, 1e-9));
    expect(
      bounds.bottom,
      closeTo(170, 1e-9),
      reason: 'the turned frame stands 160 tall about y 90',
    );
  });

  test('a view over a region shows exactly that region, square to it', () {
    const region = Rect.fromLTRB(40, 10, 360, 190);
    final view = cameraViewOver(region);
    expect(view.frameSize, const CanvasSize(width: 320, height: 180));
    expectPoints(
      cameraFrameCornersInCanvas(
        pose: view.pose,
        cameraFrameSize: view.frameSize,
      ),
      cornersOf(region),
    );
  });

  test('a panel\'s picture shows the camera\'s view — or, over a region, the '
      'region', () {
    final camera = (pose: at(80, 45), frameSize: size);
    expect(pictureView(camera, null), camera);
    const region = Rect.fromLTRB(0, 0, 320, 90);
    expect(pictureView(camera, region), cameraViewOver(region));
  });
}
