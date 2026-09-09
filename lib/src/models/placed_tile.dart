import 'bitmap_tile.dart';
import 'tile_coord.dart';

/// A tile AND where it sits — the pair every draw needs.
///
/// 🚨★★★**THE COORDINATE IS THE MAP KEY, AND A TILE TRAVELLING ALONE HAS
/// LOST IT.** `BitmapSurface` stores tiles in a `Map<TileCoord,
/// BitmapTile>`, so the surface already knows where each one goes; a
/// `coord` field on the tile itself is a second spelling of that, kept in
/// step only by a runtime check. This pair is how a tile keeps its place
/// while it is out of the map — in a parameter, in a local — without the
/// duplicate.
///
/// ⛔**A PAIR IS A PARAMETER OR A LOCAL, NEVER A STORED FIELD OF A KEYED
/// COLLECTION.** `Map<TileCoord, PlacedTile>` would put the coordinate
/// back in two places with nothing keeping them equal, which is the exact
/// state this exists to end. A `List<PlacedTile>` is fine — nothing keys
/// it, so there is no second answer to disagree with.
typedef PlacedTile = ({TileCoord coord, BitmapTile tile});
