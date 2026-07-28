import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';

void main() {
  group('FrameCompositeCacheKey', () {
    final key = FrameCompositeCacheKey(
      cutId: const CutId('cut-a'),
      frameIndex: 3,
    );



    test('rejects negative frameIndex', () {
      expect(
        () =>
            FrameCompositeCacheKey(cutId: const CutId('cut-a'), frameIndex: -1),
        throwsArgumentError,
      );
    });

    test('copyWith updates cutId', () {
      expect(key.copyWith(cutId: const CutId('cut-b')).cutId.value, 'cut-b');
    });

    test('copyWith updates frameIndex', () {
      expect(key.copyWith(frameIndex: 4).frameIndex, 4);
    });

    test('equality includes all fields', () {
      expect(
        key,
        FrameCompositeCacheKey(cutId: const CutId('cut-a'), frameIndex: 3),
      );
      expect(key, isNot(key.copyWith(cutId: const CutId('other'))));
      expect(key, isNot(key.copyWith(frameIndex: 4)));
    });

    test('hashCode is value-based', () {
      expect(
        key.hashCode,
        FrameCompositeCacheKey(
          cutId: const CutId('cut-a'),
          frameIndex: 3,
        ).hashCode,
      );
    });

    test('toJson/fromJson round-trips', () {
      expectJsonRoundTrip(key, FrameCompositeCacheKey.fromJson);
    });


  });
}
