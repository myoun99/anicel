import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 2026-09-12: 「타임라인이랑 같은 법으로 프레임영역에 떨구면 프레임
/// 블록 만들듯이 컷 만들어지도록」. A picture let go on the storyboard's frame
/// area becomes a NEW cut where Create Cut would put one at THAT frame
/// ([CutPlacement.cutCreationPlanAt]) — and the cut behind it keeps its place
/// when the room was already there (#19, [CutInsertion]).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-storyboard-drop');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Future<String> writePng(String name) =>
      writeSolidPng(tempDir, name, rgba: 0xAAAAAAAA);

  /// Two cuts with a roomy gap before the second, the playhead parked in it.
  EditorSessionManager gapped({int gap = 100}) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.first;
    s.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: gap,
    );
    s.selectCut(track.cuts[0].id);
    s.selectGlobalFrame(track.cuts[0].duration + 10);
    expect(
      s.activeCutOrNull,
      isNull,
      reason: 'fixture premise: parked in the gap',
    );
    s.historyManager.clear();
    return s;
  }

  /// Where the [index]-th cut starts and ends — the track axis's own
  /// statement of where a cut SITS, which is what #19 is about.
  int startOf(EditorSessionManager s, int index) =>
      s.trackFrameAxis().entries[index].startFrame;
  int endOf(EditorSessionManager s, int index) =>
      s.trackFrameAxis().entries[index].endFrame;

  Future<bool> dropAt(
    WidgetTester tester,
    EditorSessionManager s,
    int frame,
  ) async {
    final plan = s.cutPlacement.cutCreationPlanAt(frame);
    final ok = await tester.runAsync(
      () async => s.importDoors.importImageFile(
        path: await writePng('drop.png'),
        destination: ImportDestination.newCut,
        copyIntoProject: false,
        spot: NewCutSpot(
          index: plan.index,
          leadingGapFrames: plan.leadingGapFrames,
        ),
      ),
    );
    // The warm scheduler arms an idle timer whenever the playhead moves.
    s.playbackRig.prerenderScheduler.cancel();
    return ok!;
  }

  testWidgets('dropped in a gap, the new cut starts at the frame it was let '
      'go on — and the cut after the gap does not move', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);
    final frame = endOf(s, 0) + 10;
    final followerStart = startOf(s, 1);

    expect(await dropAt(tester, s, frame), isTrue);

    expect(s.repository.requireProject().tracks.first.cuts, hasLength(3));
    expect(startOf(s, 1), frame, reason: 'where the file was let go');
    expect(
      startOf(s, 2),
      followerStart,
      reason: 'the room the new cut needed was already free (#19)',
    );
  });

  testWidgets('dropped on a cut\'s very first frame, the new cut lands right '
      'of THAT cut — not at the parked playhead', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);
    final landedOn = s.repository.requireProject().tracks.first.cuts[0].id;
    final cutEnd = endOf(s, 0);
    final followerStart = startOf(s, 1);

    expect(await dropAt(tester, s, startOf(s, 0)), isTrue);

    expect(
      s.repository.requireProject().tracks.first.cuts[0].id,
      landedOn,
      reason: 'the cut the drop landed on keeps its place in front',
    );
    expect(
      startOf(s, 1),
      cutEnd,
      reason: 'right after the cut the drop landed on',
    );
    expect(startOf(s, 2), followerStart);
  });

  for (final (where, walkIn) in const [('outside', 10), ('inside', 44)]) {
    testWidgets('dropped $where a live empty range, the new cut still starts '
        'where the file was let go', (tester) async {
      final s = gapped();
      addTearDown(s.dispose);
      final trackId = s.repository.requireProject().tracks.first.id;
      final gapStart = endOf(s, 0);
      s.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: trackId,
        anchorRow: TrackRowAddress(trackId),
        startFrame: gapStart + 40,
        endFrameExclusive: gapStart + 50,
      );

      expect(await dropAt(tester, s, gapStart + walkIn), isTrue);

      expect(
        startOf(s, 1),
        gapStart + walkIn,
        reason:
            'a frame drop names its own cell, as the timeline\'s does '
            '(frameDropSpot) — the range the Create Cut button asks first '
            'does not speak for a drop',
      );
    });
  }

  testWidgets('one undo takes the dropped cut back out and gives the follower '
      'back the gap it had', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);
    final frame = endOf(s, 0) + 10;
    final followerStart = startOf(s, 1);

    expect(await dropAt(tester, s, frame), isTrue);
    s.undo();

    final cuts = s.repository.requireProject().tracks.first.cuts;
    expect(cuts, hasLength(2));
    expect(cuts[1].leadingGapFrames, 100);
    expect(startOf(s, 1), followerStart);
  });
}
