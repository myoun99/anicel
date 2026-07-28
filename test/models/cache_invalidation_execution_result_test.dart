import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cache_invalidation_execution_result.dart';

void main() {
  group('CacheInvalidationExecutionResult', () {
    test('stores counts', () {
      final result = CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );

      expect(result.layerTileCount, 1);
      expect(result.frameCompositeCount, 2);
      expect(result.playbackPreviewCount, 3);
    });

    test('rejects negative counts', () {
      expect(
        () => CacheInvalidationExecutionResult(
          layerTileCount: -1,
          frameCompositeCount: 0,
          playbackPreviewCount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => CacheInvalidationExecutionResult(
          layerTileCount: 0,
          frameCompositeCount: -1,
          playbackPreviewCount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => CacheInvalidationExecutionResult(
          layerTileCount: 0,
          frameCompositeCount: 0,
          playbackPreviewCount: -1,
        ),
        throwsArgumentError,
      );
    });

    test('totalCount sums all counts', () {
      expect(
        CacheInvalidationExecutionResult(
          layerTileCount: 1,
          frameCompositeCount: 2,
          playbackPreviewCount: 3,
        ).totalCount,
        6,
      );
    });

    test('didInvalidate false when totalCount is 0', () {
      expect(
        CacheInvalidationExecutionResult(
          layerTileCount: 0,
          frameCompositeCount: 0,
          playbackPreviewCount: 0,
        ).didInvalidate,
        isFalse,
      );
    });

    test('didInvalidate true when totalCount > 0', () {
      expect(
        CacheInvalidationExecutionResult(
          layerTileCount: 1,
          frameCompositeCount: 0,
          playbackPreviewCount: 0,
        ).didInvalidate,
        isTrue,
      );
    });

    test('copyWith preserves omitted values', () {
      final result = CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );

      expect(result.copyWith(), result);
    });

    test('copyWith updates each count', () {
      final result = CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );

      expect(
        result.copyWith(
          layerTileCount: 4,
          frameCompositeCount: 5,
          playbackPreviewCount: 6,
        ),
        CacheInvalidationExecutionResult(
          layerTileCount: 4,
          frameCompositeCount: 5,
          playbackPreviewCount: 6,
        ),
      );
    });

    test('equality / hashCode / toString', () {
      final a = CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );
      final b = CacheInvalidationExecutionResult(
        layerTileCount: 1,
        frameCompositeCount: 2,
        playbackPreviewCount: 3,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a.toString(),
        'CacheInvalidationExecutionResult(layerTileCount: 1, '
        'frameCompositeCount: 2, playbackPreviewCount: 3)',
      );
    });
  });
}
