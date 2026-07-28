import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';

Layer _layer({TransformTrack? track}) => Layer(
  id: const LayerId('layer-1'),
  name: 'A',
  frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
  timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
  transformTrack: track,
);

void main() {
  test('layers default to an empty (identity) transform track that never '
      'serializes', () {
    final layer = _layer();
    expect(layer.transformTrack.isEmpty, isTrue);
    expect(layer.toJson().containsKey('transform'), isFalse);
    expect(Layer.fromJson(layer.toJson()), layer);
  });

  test('a keyed transform track round-trips through json', () {
    final track = TransformTrack(
      keyframes: {
        0: TransformPose(center: CanvasPoint(x: 12, y: 34)),
        8: TransformPose(
          center: CanvasPoint(x: 56, y: 78),
          zoom: 1.5,
          rotationDegrees: -12,
        ),
      },
    );
    final layer = _layer(track: track);

    expect(layer.toJson()['transform'], isNotNull);
    final restored = Layer.fromJson(layer.toJson());
    expect(restored, layer);
    expect(restored.transformTrack, track);
  });

  test('copyWith carries and replaces the track; equality sees it', () {
    final track = TransformTrack(
      keyframes: {0: TransformPose(center: CanvasPoint(x: 1, y: 2))},
    );
    final plain = _layer();
    final moved = plain.copyWith(transformTrack: track);

    expect(moved.transformTrack, track);
    expect(moved.copyWith(name: 'B').transformTrack, track);
    expect(moved, isNot(plain));
  });
}
