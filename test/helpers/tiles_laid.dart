import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tiles a row lays on its grid's screen while [paint] paints it by
/// hand — each taken as the screen takes it, by a slot of its own
/// ([rowSlot]). Painted outside this, a row has no screen and draws its
/// cells itself.
List<TimelineGridScreenTile> tilesLaidBy(void Function() paint) =>
    rowSlot().paintThrough(paint);

/// A slot a test paints a row through by hand, as often as a screen would
/// ([TimelineGridScreenSlot.debugSlot]): what the row laid is held till it
/// paints through it again, and till the test ends.
TimelineGridScreenDebugSlot rowSlot() {
  final slot = TimelineGridScreenSlot.debugSlot();
  addTearDown(slot.letGo);
  return slot;
}
