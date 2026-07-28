import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';

void main() {
  group('PlaybackPreviewCacheKey', () {
    final key = PlaybackPreviewCacheKey(
      cutId: const CutId('cut-a'),
      frameIndex: 3,
      previewSize: const CanvasSize(width: 320, height: 180),
    );



    test('rejects negative frameIndex', () {
      expect(
        () => PlaybackPreviewCacheKey(
          cutId: const CutId('cut-a'),
          frameIndex: -1,
          previewSize: const CanvasSize(width: 1, height: 1),
        ),
        throwsArgumentError,
      );
    });

    test('copyWith updates cutId', () {
      expect(key.copyWith(cutId: const CutId('cut-b')).cutId.value, 'cut-b');
    });

    test('copyWith updates frameIndex', () {
      expect(key.copyWith(frameIndex: 4).frameIndex, 4);
    });

    test('copyWith updates previewSize', () {
      expect(
        key
            .copyWith(previewSize: const CanvasSize(width: 640, height: 360))
            .previewSize,
        const CanvasSize(width: 640, height: 360),
      );
    });

    test('equality includes all fields', () {
      expect(
        key,
        PlaybackPreviewCacheKey(
          cutId: const CutId('cut-a'),
          frameIndex: 3,
          previewSize: const CanvasSize(width: 320, height: 180),
        ),
      );
      expect(key, isNot(key.copyWith(cutId: const CutId('other'))));
      expect(key, isNot(key.copyWith(frameIndex: 4)));
      expect(
        key,
        isNot(key.copyWith(previewSize: const CanvasSize(width: 1, height: 1))),
      );
    });

    test('hashCode is value-based', () {
      expect(
        key.hashCode,
        PlaybackPreviewCacheKey(
          cutId: const CutId('cut-a'),
          frameIndex: 3,
          previewSize: const CanvasSize(width: 320, height: 180),
        ).hashCode,
      );
    });

    test('toJson/fromJson round-trips', () {
      expectJsonRoundTrip(key, PlaybackPreviewCacheKey.fromJson);
    });

    test('different previewSize creates different key', () {
      expect(
        key,
        isNot(
          key.copyWith(previewSize: const CanvasSize(width: 320, height: 181)),
        ),
      );
    });


  });
}
