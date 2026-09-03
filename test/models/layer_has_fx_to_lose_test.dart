// A LAYER HAS FX TO LOSE WHEN ANY ONE OF ITS CHANNELS IS SET.
//
// The mutation campaign (2026-09-03) turned the predicate's `||` into `&&`
// — a layer keyed on transform alone then had "nothing to warn about" —
// and nothing noticed. These pins set one channel at a time.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';

void main() {
  test('a bare layer has nothing to lose', () {
    expect(
      layerHasFxToLose(
        Layer(id: const LayerId('l'), name: 'L', frames: const []),
      ),
      isFalse,
    );
  });

  test('a transform key alone is worth the warning', () {
    final keyed = TransformTrack().withKeyframe(
      0,
      TransformPose(center: CanvasPoint(x: 1, y: 1)),
    );
    expect(
      layerHasFxToLose(
        Layer(
          id: const LayerId('l'),
          name: 'L',
          frames: const [],
          transformTrack: keyed,
        ),
      ),
      isTrue,
    );
  });

  test('an SE name tag alone is worth the warning', () {
    expect(
      layerHasFxToLose(
        Layer(
          id: const LayerId('l'),
          name: 'L',
          frames: const [],
          seNameTag: const SeNameTag(),
        ),
      ),
      isTrue,
    );
  });
}
