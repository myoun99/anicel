import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// Selecting a rail row LANDS the editing focus on it (user 2026-07-29,
/// superseding #741's "row picks never move the focus"): the label lands
/// where the playhead already stands — the same landing its own cell press
/// makes — and ⑭ then reads the INDEX for the cut, so an S row's label and
/// the V row's label agree about which cut is active. Standing in a GAP is
/// the one place the landing still parks, because there is no cut to take.
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

  /// The first global frame past every cut on the track — the trailing gap.
  int pastTheEnd(EditorSessionManager manager) {
    var total = 0;
    for (final cut in manager.repository.requireProject().tracks.first.cuts) {
      total += cut.duration;
    }
    return total + 2;
  }

  testWidgets('tapping an S row\'s LABEL selects the row and KEEPS the cut '
      'the index names — the row moved, the cut did not', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final seId = seLayerIdForTrack(trackId, 1);
    manager.selectFrameIndex(3);
    await tester.pumpAndSettle();
    final cutBefore = manager.activeCutId;
    expect(cutBefore, isNotNull);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-se-label-${trackId.value}-1')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, LayerRowAddress(seId));
    expect(
      manager.activeCutId,
      cutBefore,
      reason: '⑭: a cut covers frame 3, so the label press keeps it',
    );
    expect(manager.gapParkedGlobalFrame, isNull);
    expect(manager.currentFrameIndex, 3);
  });

  testWidgets('standing in a GAP, the same label tap still parks — there is '
      'no cut at that index to take', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final gapFrame = pastTheEnd(manager);
    manager.selectGlobalFrame(gapFrame);
    await tester.pumpAndSettle();
    expect(manager.activeCutId, isNull);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-se-label-${trackId.value}-1')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, LayerRowAddress(seLayerIdForTrack(trackId, 1)));
    expect(manager.activeCutId, isNull, reason: 'the gap has no cut to take');
    expect(
      manager.gapParkedGlobalFrame,
      gapFrame,
      reason: 'parked exactly where the playhead stood',
    );
  });

  testWidgets('the V row\'s label does NOT invent a cut in a gap — ⑭ reads '
      'the index, and an empty index names nothing', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final gapFrame = pastTheEnd(manager);
    manager.selectGlobalFrame(gapFrame);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-label-${trackId.value}')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, TrackRowAddress(trackId));
    expect(manager.activeCutId, isNull);
    expect(manager.gapParkedGlobalFrame, gapFrame);
  });

  testWidgets('the V row\'s label takes the playhead cut when one IS there '
      '— the verb that was never supposed to move', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.selectedTrackId;
    final cutBefore = manager.activeCutId;
    manager.selectFrameIndex(3);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-label-${trackId.value}')),
    );
    await tester.pumpAndSettle();

    expect(manager.selectedRow, TrackRowAddress(trackId));
    expect(manager.activeCutId, cutBefore);
    expect(manager.currentFrameIndex, 3);
  });
}
