import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';

/// What a panel can spare for its rail: everything but its own scrollbar
/// lane, the splitter and the frame area's reserve — the one formula the
/// timeline, the x-sheet and the storyboard each spelled (the audit's clone
/// scan, 2026-09-06).
void main() {
  const lane = 12.0;
  const chrome =
      lane + LayerRailSplitter.thickness + layerRailFrameReserveExtent;

  test('a horizontal rail reads the bounded WIDTH', () {
    expect(
      layerRailAvailableExtent(
        const BoxConstraints(maxWidth: 800, maxHeight: 300),
        railAxis: Axis.horizontal,
        scrollbarLaneExtent: lane,
      ),
      800 - chrome,
    );
  });

  test('a vertical rail (the x-sheet\'s stood-up header) reads the '
      'bounded HEIGHT', () {
    expect(
      layerRailAvailableExtent(
        const BoxConstraints(maxWidth: 800, maxHeight: 300),
        railAxis: Axis.vertical,
        scrollbarLaneExtent: lane,
      ),
      300 - chrome,
    );
  });

  test('an unbounded panel gives no ceiling at all', () {
    expect(
      layerRailAvailableExtent(
        const BoxConstraints(maxHeight: 300),
        railAxis: Axis.horizontal,
        scrollbarLaneExtent: lane,
      ),
      isNull,
    );
    expect(
      layerRailAvailableExtent(
        const BoxConstraints(maxWidth: 800),
        railAxis: Axis.vertical,
        scrollbarLaneExtent: lane,
      ),
      isNull,
    );
  });

  test('a panel narrower than its own chrome spares nothing, never a '
      'negative width', () {
    expect(
      layerRailAvailableExtent(
        const BoxConstraints(maxWidth: 10, maxHeight: 10),
        railAxis: Axis.horizontal,
        scrollbarLaneExtent: lane,
      ),
      0,
    );
  });
}
