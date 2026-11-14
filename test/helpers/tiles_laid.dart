import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';

/// The tiles a row lays on its grid's screen while [paint] paints it by
/// hand — each as the screen would take it ([TimelineGridScreenSlot.laying]).
/// Painted outside this, a row has no screen and draws its cells itself.
List<TimelineGridScreenTile> tilesLaidBy(void Function() paint) {
  final laid = _Laid();
  TimelineGridScreenSlot.debugLayThrough(laid, paint);
  return laid.tiles;
}

final class _Laid implements TimelineGridScreenLaying {
  final List<TimelineGridScreenTile> tiles = [];

  @override
  void lay(TimelineGridScreenTile tile) => tiles.add(tile);
}
