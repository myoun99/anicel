import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

import '../../helpers/poll_until.dart';

/// Waits until [store] has nothing queued or in flight, and fails the test
/// if that never comes. Idle is the store's word
/// ([TimelineGridTileStore.debugBusy]), not a quiet spell: a slow drain on
/// a loaded machine must not read as a finished one. [seen] goes into the
/// failure — what the test had counted landing by then.
///
/// It asks at once (board `the-tile-store-drain-wait-is-written-four-times`,
/// 2026-10-17): the store raises the word in the call that schedules the
/// work — a request is pending before its drain is a microtask, a warm-up's
/// flag is up before its own, and a drain counts itself before its first
/// await. Two of the four waits this replaces gave up a turn before asking,
/// with no reason written, and the word held the pending requests already
/// when they were.
Future<void> tileStoreIdle(
  TimelineGridTileStore store, {
  String Function()? seen,
}) async {
  if (!await pollUntil(() => !store.debugBusy)) {
    fail(
      'the tile store never went idle'
      '${seen == null ? '' : ' (${seen()})'}',
    );
  }
}
