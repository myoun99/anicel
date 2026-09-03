// TWO GATES OF THE COMPOSITE PLAN: A LAYER WITH ANY GEOMETRIC KEY HAS A
// POSE, AND A HIDDEN LAYER NEVER REACHES THE PICTURE.
//
// Two survivors of the mutation campaign (2026-09-03): the identity check's
// `&&` became `||` (one empty lane made the whole track "identity", so a
// layer keyed on position alone lost its pose) and the visibility gate's
// `||` became `&&` (a hidden layer with opacity still composited). Nothing
// noticed either; these pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

const _canvas = CanvasSize(width: 64, height: 64);

Layer _drawn(String id, {bool isVisible = true, TransformTrack? track}) =>
    Layer(
      id: LayerId(id),
      name: id,
      isVisible: isVisible,
      frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
      timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 1)},
      transformTrack: track,
    );

void main() {
  group('resolveLayerPoseAt', () {
    test('an unkeyed track has no pose (opacity alone never forces one)', () {
      expect(
        resolveLayerPoseAt(
          layer: _drawn('a'),
          canvasSize: _canvas,
          frameIndex: 0,
        ),
        isNull,
      );
    });

    test('one geometric key is enough for a pose', () {
      final keyed = TransformTrack().withKeyframe(
        0,
        TransformPose(center: CanvasPoint(x: 10, y: 12)),
      );
      final pose = resolveLayerPoseAt(
        layer: _drawn('a', track: keyed),
        canvasSize: _canvas,
        frameIndex: 0,
      );
      expect(pose, isNotNull);
      expect(pose!.center, CanvasPoint(x: 10, y: 12));
    });
  });

  test('a hidden layer never reaches the composite entries', () {
    final cut = Cut(
      id: const CutId('c'),
      name: '1',
      duration: 4,
      canvasSize: _canvas,
      layers: [_drawn('shown'), _drawn('hidden', isVisible: false)],
    );
    final entries = resolveCutFrameCompositeEntries(cut: cut, frameIndex: 0);
    expect(entries.map((entry) => entry.layer.id), [const LayerId('shown')]);
  });
}
