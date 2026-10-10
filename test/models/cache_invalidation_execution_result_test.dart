import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cache_invalidation_execution_result.dart';

void main() {
  group('CacheInvalidationExecutionResult', () {
    test('stores the count', () {
      final result = CacheInvalidationExecutionResult(layerTileCount: 1);

      expect(result.layerTileCount, 1);
    });

    test('rejects a negative count', () {
      expect(
        () => CacheInvalidationExecutionResult(layerTileCount: -1),
        throwsArgumentError,
      );
    });

    test('totalCount is the layer tiles', () {
      expect(CacheInvalidationExecutionResult(layerTileCount: 3).totalCount, 3);
    });

    test('didInvalidate false when totalCount is 0', () {
      expect(
        CacheInvalidationExecutionResult(layerTileCount: 0).didInvalidate,
        isFalse,
      );
    });

    test('didInvalidate true when totalCount > 0', () {
      expect(
        CacheInvalidationExecutionResult(layerTileCount: 1).didInvalidate,
        isTrue,
      );
    });

    test('copyWith preserves omitted values', () {
      final result = CacheInvalidationExecutionResult(layerTileCount: 1);

      expect(result.copyWith(), result);
    });

    test('copyWith updates the count', () {
      final result = CacheInvalidationExecutionResult(layerTileCount: 1);

      expect(
        result.copyWith(layerTileCount: 4),
        CacheInvalidationExecutionResult(layerTileCount: 4),
      );
    });

    test('equality / hashCode / toString', () {
      final a = CacheInvalidationExecutionResult(layerTileCount: 1);
      final b = CacheInvalidationExecutionResult(layerTileCount: 1);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a.toString(),
        'CacheInvalidationExecutionResult(layerTileCount: 1)',
      );
    });
  });
}
