import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

/// Counts the tiles [store] draws off the paint from here to the end of
/// the test — not those baked in the ask that wanted them
/// ([TimelineGridTileStore.debugBeforeDrawing]). Answers how many so far.
int Function() countTilesDrawnOffThePaint(TimelineGridTileStore store) {
  var count = 0;
  store.debugBeforeDrawing = () async {
    count += 1;
  };
  addTearDown(() => store.debugBeforeDrawing = null);
  return () => count;
}

/// Holds each tile [store] draws off the paint from here to the end of the
/// test until the test completes its own — in the order they reached it,
/// each then drawn: a raster a test needs in flight. Those still held at
/// the end are let go.
List<Completer<void>> holdTilesDrawnOffThePaint(TimelineGridTileStore store) {
  final held = <Completer<void>>[];
  store.debugBeforeDrawing = () {
    final draw = Completer<void>();
    held.add(draw);
    return draw.future;
  };
  addTearDown(() {
    store.debugBeforeDrawing = null;
    for (final draw in held) {
      if (!draw.isCompleted) {
        draw.complete();
      }
    }
  });
  return held;
}
