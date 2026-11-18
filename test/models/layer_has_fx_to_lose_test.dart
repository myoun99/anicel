// A LAYER HAS FX TO LOSE WHEN ANY ONE OF ITS CHANNELS IS SET.
//
// The mutation campaign (2026-09-03) turned the predicate's `||` into `&&`
// — a layer keyed on transform alone then had "nothing to warn about" —
// and nothing noticed. These pins set one channel at a time.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
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

  // 🗣️attach-rows-lose-the-base-move-when-it-bakes-Q4: a row that wears its
  // base's fx wears none of its own reference fx — the fourth channel.
  group('a reference fx', () {
    Layer showing(MediaReference reference) => Layer(
      id: const LayerId('l'),
      name: 'L',
      frames: const [],
      mediaReference: reference,
    );
    final laid = TransformPose(center: CanvasPoint(x: 50, y: 30));
    MediaReference file({TransformTrack? fx, TransformPose? pose}) =>
        MediaReference(
          assetPath: '/sheet.png',
          pose: pose ?? laid,
          pictureSize: const CanvasSize(width: 100, height: 60),
          fx: fx,
          laid: laid,
        );

    test('standing where its file is laid has nothing to lose', () {
      expect(layerHasFxToLose(showing(file())), isFalse);
    });

    test('a key alone is worth the warning', () {
      expect(
        layerHasFxToLose(
          showing(
            file(
              fx: TransformTrack().withKeyframe(
                0,
                TransformPose(center: CanvasPoint(x: 80, y: 30)),
              ),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('an unkeyed value away from where the file is laid is worth the '
        'warning', () {
      expect(
        layerHasFxToLose(
          showing(file(pose: TransformPose(center: CanvasPoint(x: 80, y: 30)))),
        ),
        isTrue,
      );
    });
  });
}
