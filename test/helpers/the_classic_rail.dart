import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// How wide the rail stood before its lane values took their hands
/// (tool-settings-panel-tidy: the natural rail went 443 → 519, the
/// storyboard's with it).
const double classicRailWidth = 443;

/// Every rail window mounted set to [classicRailWidth], as a hand on its
/// splitter sets it — so a test laid out by the frames it shows finds them
/// where it was written to: the window cuts the rail's tail, and the frames
/// start where they started.
///
/// For a test whose subject is the frames, not the rail. ⛔Not a wider
/// window: in the test window the bottom panel stops at 640, so a wider one
/// gave the frames nothing (measured 2026-10-10 — 800 and 876 both 640, the
/// frames 100 at the natural rail and 176 at this one, as they were).
Future<void> standTheClassicRail(WidgetTester tester) async {
  for (final window in tester.widgetList<LayerRailWindow>(
    find.byType(LayerRailWindow, skipOffstage: false),
  )) {
    window.rail.value = classicRailWidth;
  }
  await tester.pumpAndSettle();
}
