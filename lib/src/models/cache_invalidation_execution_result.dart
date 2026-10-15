/// What one plan's execution invalidated — the layer tiles, the one kind a
/// [CacheInvalidationPlan] carries ([CacheInvalidationPlan] says why).
class CacheInvalidationExecutionResult {
  CacheInvalidationExecutionResult({required this.layerTileCount}) {
    _validateCount(layerTileCount, 'layerTileCount');
  }

  final int layerTileCount;

  int get totalCount => layerTileCount;

  bool get didInvalidate => totalCount > 0;

  CacheInvalidationExecutionResult copyWith({int? layerTileCount}) {
    return CacheInvalidationExecutionResult(
      layerTileCount: layerTileCount ?? this.layerTileCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheInvalidationExecutionResult &&
          other.layerTileCount == layerTileCount;

  @override
  int get hashCode => layerTileCount.hashCode;

  @override
  String toString() =>
      'CacheInvalidationExecutionResult(layerTileCount: $layerTileCount)';
}

void _validateCount(int count, String name) {
  if (count < 0) {
    throw ArgumentError.value(
      count,
      name,
      'CacheInvalidationExecutionResult.$name must be greater than or equal to 0.',
    );
  }
}
