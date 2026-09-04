import '../core/collection_equality.dart';
import 'dirty_region.dart';
import 'tile_coord.dart';

class DirtyTileSet {
  DirtyTileSet([Iterable<TileCoord> coords = const []])
    : _coords = Set<TileCoord>.unmodifiable(coords);

  factory DirtyTileSet.empty() => DirtyTileSet();

  factory DirtyTileSet.fromRegion({
    required DirtyRegion region,
    required int tileSize,
  }) {
    return DirtyTileSet(region.toTileCoords(tileSize: tileSize));
  }

  factory DirtyTileSet.fromRegions({
    required Iterable<DirtyRegion> regions,
    required int tileSize,
  }) {
    return DirtyTileSet(
      regions.expand((region) => region.toTileCoords(tileSize: tileSize)),
    );
  }

  final Set<TileCoord> _coords;

  Set<TileCoord> get coords => Set.unmodifiable(_coords);

  int get length => _coords.length;

  bool get isEmpty => _coords.isEmpty;

  bool get isNotEmpty => _coords.isNotEmpty;

  DirtyTileSet copyWith({Iterable<TileCoord>? coords}) {
    return DirtyTileSet(coords ?? _coords);
  }

  bool contains(TileCoord coord) => _coords.contains(coord);

  DirtyTileSet add(TileCoord coord) => DirtyTileSet({..._coords, coord});

  DirtyTileSet addAll(Iterable<TileCoord> coords) {
    return DirtyTileSet({..._coords, ...coords});
  }

  DirtyTileSet remove(TileCoord coord) {
    final nextCoords = Set<TileCoord>.of(_coords)..remove(coord);
    return DirtyTileSet(nextCoords);
  }

  DirtyTileSet union(DirtyTileSet other) {
    return DirtyTileSet({..._coords, ...other._coords});
  }

  DirtyTileSet intersect(DirtyTileSet other) {
    return DirtyTileSet(_coords.where(other._coords.contains));
  }

  DirtyTileSet difference(DirtyTileSet other) {
    return DirtyTileSet(
      _coords.where((coord) => !other._coords.contains(coord)),
    );
  }

  Map<String, dynamic> toJson() => {
    'coords': _coords.map((coord) => coord.toJson()).toList(),
  };

  factory DirtyTileSet.fromJson(Map<String, dynamic> json) {
    return DirtyTileSet(
      (json['coords'] as List? ?? const []).map(
        (coordJson) => TileCoord.fromJson(coordJson as Map<String, dynamic>),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirtyTileSet && setEquals(other._coords, _coords);

  @override
  int get hashCode => Object.hashAllUnordered(_coords);

  @override
  String toString() => 'DirtyTileSet(length: $length, coords: $_coords)';
}
