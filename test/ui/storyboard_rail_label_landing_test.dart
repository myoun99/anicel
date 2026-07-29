import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// Selecting a rail row LANDS the editing focus on it (user 2026-07-29,
/// superseding #741's "row picks never move the focus"): an S row's label
/// releases the active cut and PARKS where the playhead stands — the same
/// landing its own cell press makes — and a V row's label takes the track's
/// playhead-index cut back.
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([
              manager,
              manager.frameSeekCommitted,
            ]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  testWidgets('tapping an S row\'s LABEL releases the active cut and parks '
      'in place — the row is selected and the canvas shows the parked '
      'stack, exactly as the row\'s own cell press lands', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final seId = seLayerIdForTrack(trackId, 1);
    manager.selectFrameIndex(3);
    await tester.pumpAndSettle();
    expect(manager.activeCutId, isNotNull);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-se-label-${trackId.value}-1')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, LayerRowAddress(seId));
    expect(manager.activeCutId, isNull, reason: 'the label press parks');
    expect(
      manager.gapParkedGlobalFrame,
      3,
      reason: 'parked exactly where the playhead stood',
    );
  });

  testWidgets('tapping the V row\'s label afterwards takes the playhead '
      'cut back — the selection round-trips', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final cutBefore = manager.activeCutId;
    manager.selectFrameIndex(3);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-se-label-${trackId.value}-1')),
    );
    await tester.pumpAndSettle();
    expect(manager.activeCutId, isNull);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-label-${trackId.value}')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, TrackRowAddress(trackId));
    expect(manager.activeCutId, cutBefore);
    expect(manager.currentFrameIndex, 3);
  });
}
