import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/canvas_size.dart';

/// "Does this row own a Transform group?" — ONE answer for every kind of row a
/// rail shows.
///
/// Stated as a rule rather than settled by deleting one row's lanes, because it
/// is a rule that may be wanted for other rows (user, 2026-08-10: "혹시 다른
/// 행에서도 추가할수있는 규칙이거든? 그러니 공통사용가능하게 해줘"). What the
/// tests below pin is that a rail has somewhere to ASK, so giving another row
/// the same answer is one case and not an edit at every rail.
void main() {
  group('a LAYER row answers through its kind', () {
    test('the rows that carry a picture own one', () {
      for (final kind in [
        LayerKind.animation,
        LayerKind.storyboard,
        LayerKind.image,
        LayerKind.text,
        LayerKind.se,
        LayerKind.instruction,
        LayerKind.folder,
      ]) {
        expect(
          timelineRowOwnsTransform(
            subject: TimelineTransformSubject.layer,
            layerKind: kind,
          ),
          isTrue,
          reason: '$kind',
        );
      }
    });

    test('camera, adjustment and transition rows do not', () {
      for (final kind in [
        LayerKind.camera,
        LayerKind.adjustment,
        LayerKind.transition,
      ]) {
        expect(
          timelineRowOwnsTransform(
            subject: TimelineTransformSubject.layer,
            layerKind: kind,
          ),
          isFalse,
          reason: '$kind',
        );
      }
    });

    test('it agrees with layerKindHasLayerTransform — one source, not two', () {
      for (final kind in LayerKind.values) {
        expect(
          timelineRowOwnsTransform(
            subject: TimelineTransformSubject.layer,
            layerKind: kind,
          ),
          layerKindHasLayerTransform(kind),
          reason: '$kind',
        );
      }
    });

    test('a layer row with no kind to ask about owns nothing', () {
      expect(
        timelineRowOwnsTransform(subject: TimelineTransformSubject.layer),
        isFalse,
      );
    });
  });

  group('the V (TRACK) row', () {
    test('does NOT own a Transform group', () {
      expect(
        timelineRowOwnsTransform(subject: TimelineTransformSubject.track),
        isFalse,
      );
    });

    test('and the model has no track transform left to author', () {
      final track = Track(
        id: const TrackId('t1'),
        name: 'V1',
        cuts: [
          Cut(
            id: const CutId('c1'),
            name: 'c1',
            layers: const [],
            duration: 12,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      );

      // What a track keeps: its static opacity, its fx chain and its fx
      // master. What it lost: the pose lanes and the fade's opacity lane.
      expect(track.opacity, 1.0);
      expect(track.effects, isEmpty);
      expect(track.fxEnabled, isTrue);
      expect(track.toJson().containsKey('transform'), isFalse);
    });

    test('a file written BEFORE the teardown still loads — the key is read '
        'and dropped, so an old project opens one row lighter', () {
      final json = <String, dynamic>{
        'id': const TrackId('t1').toJson(),
        'name': 'V1',
        'type': 'video',
        'cuts': [
          Cut(
            id: const CutId('c1'),
            name: 'c1',
            layers: const [],
            duration: 12,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ).toJson(),
        ],
        'seLayers': <dynamic>[],
        // The retired shape: a track pose keyed on the global axis.
        'transform': {
          'keyframes': {
            '0': {
              'center': {'x': 1.0, 'y': 2.0},
              'zoom': 1.5,
              'rotationDegrees': 10.0,
            },
          },
        },
      };

      final loaded = Track.fromJson(json);

      expect(loaded.id, const TrackId('t1'));
      expect(loaded.cuts, hasLength(1));
      expect(
        loaded.toJson().containsKey('transform'),
        isFalse,
        reason: 'and it is not written back',
      );
    });
  });
}
