import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';

void main() {
  group('CameraPose', () {
    test('serializes to and from json', () {
      final pose = CameraPose(
        center: CanvasPoint(x: 100.5, y: 200.25),
        zoom: 1.5,
        rotationDegrees: -30,
      );

      expect(CameraPose.fromJson(pose.toJson()), pose);
    });

    test('missing rotation in json defaults to 0', () {
      final pose = CameraPose.fromJson({
        'center': {'x': 1.0, 'y': 2.0},
        'zoom': 2.0,
      });

      expect(pose.rotationDegrees, 0);
    });

    test('rejects non-positive or non-finite zoom', () {
      expect(
        () => CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: 0),
        throwsArgumentError,
      );
      expect(
        () => CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: -1),
        throwsArgumentError,
      );
      expect(
        () =>
            CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: double.infinity),
        throwsArgumentError,
      );
    });

    test('rejects non-finite rotation', () {
      expect(
        () => CameraPose(
          center: CanvasPoint(x: 0, y: 0),
          rotationDegrees: double.nan,
        ),
        throwsArgumentError,
      );
    });
  });

  group('CutCamera', () {
    test('keeps keyframes sorted by frame index', () {
      final camera = CutCamera(
        keyframes: {12: _pose(x: 12), 0: _pose(x: 0), 5: _pose(x: 5)},
      );

      expect(camera.keyframes.keys.toList(), [0, 5, 12]);
    });

    test('rejects negative keyframe indexes', () {
      expect(
        () => CutCamera(keyframes: {-1: _pose(x: 0)}),
        throwsArgumentError,
      );
    });

    test('withKeyframe adds or replaces without mutating the original', () {
      final camera = CutCamera(keyframes: {0: _pose(x: 0)});

      final added = camera.withKeyframe(8, _pose(x: 8));
      final replaced = added.withKeyframe(0, _pose(x: 99));

      expect(camera.keyframes.keys.toList(), [0]);
      expect(added.keyframes.keys.toList(), [0, 8]);
      expect(replaced.keyframeAt(0), _pose(x: 99));
    });

    test('withoutKeyframe removes and tolerates missing indexes', () {
      final camera = CutCamera(keyframes: {0: _pose(x: 0), 8: _pose(x: 8)});

      expect(camera.withoutKeyframe(8).keyframes.keys.toList(), [0]);
      expect(camera.withoutKeyframe(99), camera);
    });

    test('serializes to and from json', () {
      final camera = CutCamera(
        keyframes: {0: _pose(x: 0), 8: _pose(x: 8, zoom: 2)},
      );

      expect(CutCamera.fromJson(camera.toJson()), camera);
    });

    test('rejects duplicate keyframe indexes in json', () {
      expect(
        () => CutCamera.fromJson({
          'keyframes': [
            {'index': 0, 'pose': _pose(x: 0).toJson()},
            {'index': 0, 'pose': _pose(x: 1).toJson()},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('Cut camera field', () {
    test('defaults to an empty camera and round-trips through json', () {
      final cut = _cut();
      expect(cut.camera.isEmpty, isTrue);

      final withCamera = cut.copyWith(
        camera: CutCamera(keyframes: {0: _pose(x: 10)}),
      );
      // Loading backfills the SE/instruction fixture rows.
      expect(
        Cut.fromJson(withCamera.toJson()),
        withCamera.copyWith(
          layers: withEnsuredSectionLayers(withCamera.id, withCamera.layers),
        ),
      );
    });

    test('json without a camera field loads as an empty camera', () {
      final json = _cut().toJson()..remove('camera');

      expect(Cut.fromJson(json).camera, CutCamera.empty());
    });
  });
}

CameraPose _pose({required double x, double zoom = 1}) => CameraPose(
  center: CanvasPoint(x: x, y: 0),
  zoom: zoom,
);

Cut _cut() => Cut(
  id: const CutId('cut-1'),
  name: 'Cut',
  layers: const [],
  duration: 24,
  canvasSize: const CanvasSize(width: 1920, height: 1080),
);
