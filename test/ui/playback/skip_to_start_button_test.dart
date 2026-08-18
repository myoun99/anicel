import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show seekStoryboardPlayheadToTrackStart;

/// D1 (2026-08-17): the storyboard's "to start" button goes to the VERY
/// FIRST frame of the track axis — GAPS INCLUDED. The old body spoke
/// cut-local (selectCut + frame 0) and silently skipped a leading gap;
/// the button now rides the canonical global seek, whose gap law is
/// parking (T12: a gap parking is the only way to be in a gap).
///
/// Driven through the REAL button on the workspace sill
/// (parity-tests-must-drive-real-input) — the seam under test is the
/// free function the sill's callback calls.
Cut _cut(String id, {int leadingGap = 0}) => Cut(
  id: CutId(id),
  name: id,
  duration: 8,
  leadingGapFrames: leadingGap,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: const [],
);

Project _project({required int firstCutLeadingGap}) => Project(
  id: const ProjectId('skip-start'),
  name: 'SkipStart',
  createdAt: DateTime.utc(2026, 8, 18),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        _cut('cut-1', leadingGap: firstCutLeadingGap),
        _cut('cut-2'),
      ],
    ),
  ],
);

Future<dynamic> _pumpStoryboard(
  WidgetTester tester, {
  required int firstCutLeadingGap,
}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(firstCutLeadingGap: firstCutLeadingGap),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
      .session;
}

void main() {
  testWidgets('D1: with a leading gap, the storyboard start button PARKS at '
      'global 0 — the axis origin gaps included, where all-cuts play '
      'begins', (tester) async {
    final session = await _pumpStoryboard(tester, firstCutLeadingGap: 6);
    // Stand somewhere else first, so the seek has work to do.
    session.selectCut(const CutId('cut-2'));
    session.selectFrameIndex(3);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-skip-to-start-button')),
    );
    await tester.pumpAndSettle();

    expect(
      session.gapParkedGlobalFrame,
      0,
      reason: 'a leading gap parks the playhead at global 0 — the old '
          'cut-local body skipped straight to the first cut\'s frame',
    );
    // Parking deselects the active cut (UI-R9 #3) — the established gap
    // law, stated rather than softened.
    expect(session.activeCutOrNull, isNull);
  });

  testWidgets('D1: with no leading gap, the button lands on the first '
      'cut\'s frame 0 — byte-identical to the old resolution', (
    tester,
  ) async {
    final session = await _pumpStoryboard(tester, firstCutLeadingGap: 0);
    session.selectCut(const CutId('cut-2'));
    session.selectFrameIndex(3);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-skip-to-start-button')),
    );
    await tester.pumpAndSettle();

    expect(session.gapParkedGlobalFrame, isNull);
    expect(session.activeCutOrNull?.id, const CutId('cut-1'));
    expect(session.currentFrameIndex, 0);
  });

  test('D1: an EMPTY selected track re-aims at the displayed fallback '
      'track before seeking — the play playlist filters by selected '
      'track with NO fallback, so the parked axis must agree with it', () {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('skip-start-empty'),
        name: 'SkipStartEmpty',
        createdAt: DateTime.utc(2026, 8, 18),
        tracks: [
          Track(id: const TrackId('empty'), name: 'Empty', cuts: const []),
          Track(
            id: const TrackId('video'),
            name: 'Video',
            cuts: [_cut('cut-1', leadingGap: 6), _cut('cut-2')],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectTrackCutAtPlayhead(const TrackId('empty'));
    expect(session.selectedTrackId, const TrackId('empty'));

    seekStoryboardPlayheadToTrackStart(session);

    expect(
      session.selectedTrackId,
      const TrackId('video'),
      reason: 'the storyboard shows the fallback track — to-start re-aims '
          'there (the old selectCut side effect, kept deliberately), or '
          'the play button dies on an empty playlist',
    );
    expect(session.gapParkedGlobalFrame, 0);
  });
}
