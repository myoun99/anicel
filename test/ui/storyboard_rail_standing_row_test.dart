import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

import '../helpers/storyboard_host.dart';

/// The legend's filter on the storyboard rail (R5 #9), and the one row it
/// never hides: the row you are STANDING on — the timeline's rule, for the
/// same reason (a filter must never hide the row you are editing). The S
/// row answers every chip as a layer; the V row answers the fx chip alone.
void main() {
  Future<EditorSessionManager> pumpHost(
    WidgetTester tester, {
    required TimelineRowFilter rowFilter,
    required void Function(EditorSessionManager) arrange,
  }) async {
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);
    arrange(manager);
    // The filter as set — the session's, without the chip's own hand-off
    // of the stand: the row you stand on is what this asks about.
    manager.railView.rowFilter.value = rowFilter;

    await pumpStoryboardHostOn(
      tester,
      manager,
      surface: const Size(1400, 600),
      pixelsPerFrame: 12,
    );
    return manager;
  }

  final markFilter = TimelineRowFilter(
    markColors: {const LayerMark(process: LayerProcess.layout)},
  );

  testWidgets('an S row failing the mark chip hides — unless it is the row '
      'you stand on', (tester) async {
    late String track;
    await pumpHost(
      tester,
      rowFilter: markFilter,
      arrange: (manager) {
        track = manager.selectedTrackId.value;
        manager.selectRow(
          LayerRowAddress(seLayerIdForTrack(manager.selectedTrackId, 1)),
        );
      },
    );
    expect(
      find.byKey(ValueKey<String>('storyboard-se-label-$track-1')),
      findsOneWidget,
      reason: 'S1 fails the mark chip but is the standing row',
    );
    expect(
      find.byKey(ValueKey<String>('storyboard-se-label-$track-2')),
      findsNothing,
      reason: 'S2 fails the mark chip and nobody stands on it',
    );
    expect(
      find.byKey(ValueKey<String>('storyboard-section-zone-$track-v')),
      findsOneWidget,
      reason: 'a track has no mark, so the mark chip leaves the V row alone',
    );
  });

  testWidgets('the V row failing the fx chip hides — unless it is the row '
      'you stand on', (tester) async {
    late String track;
    final manager = await pumpHost(
      tester,
      rowFilter: const TimelineRowFilter(fxOnly: true),
      arrange: (manager) {
        track = manager.selectedTrackId.value;
        manager.effectsAndFx.toggleTrackFx(manager.selectedTrackId);
        manager.selectRow(
          LayerRowAddress(seLayerIdForTrack(manager.selectedTrackId, 1)),
        );
      },
    );
    expect(
      find.byKey(ValueKey<String>('storyboard-section-zone-$track-v')),
      findsNothing,
      reason: 'the track has fx OFF and nobody stands on its row',
    );

    manager.selectTrackRow(manager.selectedTrackId);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('storyboard-section-zone-$track-v')),
      findsOneWidget,
      reason: 'standing on the V row exempts it, as it does an S row',
    );
  });
}
