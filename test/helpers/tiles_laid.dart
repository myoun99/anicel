import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tiles a row lays on its grid's screen while [paint] paints it by
/// hand — each taken as the screen takes it, by a slot of its own
/// ([rowSlot]). Painted outside this, a row has no screen and draws its
/// cells itself.
///
/// The frame up shows what it lays where [shownUp]; else none of it, as a
/// screen whose GPU has not finished the lay.
List<TimelineGridScreenTile> tilesLaidBy(
  void Function() paint, {
  bool shownUp = true,
}) => rowSlot(shownUp: shownUp).paintThrough(paint);

/// A slot a test paints a row through by hand, as often as a screen would
/// ([TimelineGridScreenSlot.debugSlot]): what the row laid is held till it
/// paints through it again, and till the test ends.
TimelineGridScreenDebugSlot rowSlot({bool shownUp = true}) {
  final slot = TimelineGridScreenSlot.debugSlot(shownUp: shownUp);
  addTearDown(slot.letGo);
  return slot;
}
