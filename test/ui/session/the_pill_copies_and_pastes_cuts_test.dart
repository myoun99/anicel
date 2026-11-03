import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/link_mirror.dart'
    show linkedCutSiblings;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/app_clipboard.dart';
import 'package:anicel/src/ui/session/cut_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/pill_row_clipboard.dart';

/// 🗣️I-150 (유저 2026-11-03): 「컷 잘라내기/복사/붙여넣기/링크붙여넣기등
/// 공용알약 사용 가능하게. 병합만 불가능? 우선은?」 · 「링크붙여넣기는 물론
/// 겸용컷으로 만들면서 붙여넣는단느낌. 그리고 이를 통해 다른트랙에도
/// 링크붙여넣기 가능」 · 「다른트랙에 블록 복사해서 붙여넣는다던가 전부
/// 가능하게」 — the storyboard's pill takes the cuts in hand, and puts them
/// down where a new cut would land.
///
/// The verbs these live in — named so `tool/mutation_run.dart` runs this
/// file for them.
CutClipboard cutBoardOf(EditorSessionManager session) => session.cutClipboard;

void main() {
  // A drawn cel's picture is warmed in the quiet the binding keeps.
  TestWidgetsFlutterBinding.ensureInitialized();
  const v = TrackId('v');

  Cut cut(String name) => Cut(
    id: CutId('cut-$name'),
    name: name,
    duration: 4,
    canvasSize: const CanvasSize(width: 32, height: 32),
    layers: [Layer(id: LayerId('cut-$name-a'), name: 'A', frames: const [])],
  );

  /// Cuts 10 11 12 13 of four frames each on V.
  Project fourCuts() => Project(
    id: const ProjectId('cut-board'),
    name: 'Cuts',
    createdAt: DateTime.utc(2026, 11, 3),
    tracks: [
      Track(
        id: v,
        name: 'V',
        cuts: [for (final name in ['10', '11', '12', '13']) cut(name)],
      ),
    ],
  );

  EditorSessionManager session({AppClipboard? board}) {
    final s = EditorSessionManager(
      initialProject: fourCuts(),
      appClipboard: board,
    );
    addTearDown(s.dispose);
    return s;
  }

  List<String> namesOn(EditorSessionManager s, TrackId track) => [
    for (final cut in s.repository
        .requireProject()
        .tracks
        .firstWhere((one) => one.id == track)
        .cuts)
      cut.name,
  ];

  /// Standing on the V row at [frame].
  StoryboardToolbarPanelContext standOnV(EditorSessionManager s, int frame) {
    s.selectGlobalFrame(frame);
    s.selectTrackRow(v);
    return StoryboardToolbarPanelContext(s);
  }

  test('standing on a cut, the pill copies THAT cut, and a paste puts its '
      'copy right after the cut you stand in — ONE undo', () {
    final s = session();
    final pill = standOnV(s, 5);
    expect(pill.canCopyFrame, isTrue);

    pill.copyFrame();
    expect(s.cutClipboard.holdsCuts, isTrue);
    final steps = s.historyManager.undoCount;
    pill.pasteIndependentFrame();

    expect(namesOn(s, v), ['10', '11', '11 Copy', '12', '13']);
    expect(s.historyManager.undoCount, steps + 1, reason: 'ONE step');
    s.undo();
    expect(namesOn(s, v), ['10', '11', '12', '13']);
  });

  test('a band of cuts is copied whole and lands after the band\'s last '
      'cut, in its order', () {
    final s = session();
    final pill = standOnV(s, 1);
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 5,
      headGlobalFrame: 9,
    );
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      [const CutId('cut-11'), const CutId('cut-12')],
      reason: '⛔전제',
    );

    pill.copyFrame();
    pill.pasteIndependentFrame();

    expect(namesOn(s, v), [
      '10',
      '11',
      '12',
      '11 Copy',
      '12 Copy',
      '13',
    ]);
  });

  test('in a gap the copy lands where a new cut would — the block walking '
      'into it as one, linked or not', () {
    final s = session();
    standOnV(s, 1);
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 1,
      headGlobalFrame: 5,
    );
    StoryboardToolbarPanelContext(s).copyFrame();
    s.trackFrameRangeSelection.value = null;

    final pill = standOnV(s, 20);
    expect(
      s.editingSession.gapGlobalFrame,
      20,
      reason: '⛔전제: parked in the gap past the last cut',
    );
    List<(String, int)> lastTwo() => [
      for (final cut in s.repository.requireProject().tracks.first.cuts.skip(
        4,
      ))
        (cut.name, cut.leadingGapFrames),
    ];

    pill.pasteIndependentFrame();
    expect(lastTwo(), [('10 Copy', 4), ('11 Copy', 0)], reason: '16 → 20');

    s.undo();
    standOnV(s, 20).pasteLinkedFrame();
    expect([for (final (_, gap) in lastTwo()) gap], [4, 0]);
    s.undo();
    expect(namesOn(s, v), ['10', '11', '12', '13'], reason: 'undone in a gap');
  });

  test('a band over the gap claims the copy, and the paste lands in it', () {
    final s = session();
    standOnV(s, 1).copyFrame();
    final pill = standOnV(s, 1);
    s.trackFrameRangeSelection.value = const TrackFrameRangeSelection(
      trackId: v,
      anchorRow: TrackRowAddress(v),
      rows: [TrackRowAddress(v)],
      startFrame: 18,
      endFrameExclusive: 20,
    );
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      isEmpty,
      reason: '⛔전제: the band names no cut',
    );
    expect(pill.canCopyFrame, isFalse, reason: 'not the cut stood in');

    pill.pasteIndependentFrame();
    final last = s.repository.requireProject().tracks.first.cuts.last;
    expect((last.name, last.leadingGapFrames), ('10 Copy', 2));
  });

  test('a 잘라내기 lifts the cut you stand in, and the paste puts it back '
      'with its drawing — the board\'s, the store has none of it left', () {
    final s = session();
    standOnV(s, 1);
    s.selectLayer(const LayerId('cut-10-a'));
    drawOnCurrentFrame(s);
    final drawn = s.requireActiveCut;
    final row = drawn.layers.single;
    final picture = s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(drawn, row.id, row.frames.single.id),
    );
    expect(picture, isNotNull, reason: '⛔전제: a drawing');

    final pill = standOnV(s, 1);
    expect(pill.canCutRun, isTrue);
    pill.cutRun();
    expect(namesOn(s, v), ['11', '12', '13']);
    expect(
      s.appClipboard.heldPictures,
      contains(same(picture)),
      reason: 'the memory census weighs what the hand holds',
    );
    expect(
      pill.canPasteLinkedFrame,
      isFalse,
      reason: 'a cut cut away has no cel left to share',
    );

    pill.pasteIndependentFrame();
    final pasted = s.repository.requireProject().tracks.first.cuts
        .singleWhere((cut) => cut.name == '10 Copy');
    final cel = pasted.layers.single.frames.single;
    expect(
      s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(pasted, pasted.layers.single.id, cel.id),
      ),
      same(picture),
    );
  });

  test('a 잘라내기 takes what the delete takes: a band over every cut, '
      'which the project would not keep, cuts nothing', () {
    final s = session();
    final pill = standOnV(s, 1);
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 0,
      headGlobalFrame: 15,
    );
    expect(pill.canCopyFrame, isTrue, reason: 'the copy takes them');
    expect(pill.canCutRun, isFalse);

    s.cutClipboard.cut();
    expect(namesOn(s, v), ['10', '11', '12', '13']);
    expect(s.cutClipboard.holdsCuts, isFalse, reason: 'nothing lifted');
  });

  test('a linked paste makes a 겸용 cut of each copied cut where the paste '
      'lands — named on from the cut in front of it', () {
    final s = session();
    standOnV(s, 1).copyFrame();
    final pill = standOnV(s, 9);
    expect(pill.canPasteLinkedFrame, isTrue);

    pill.pasteLinkedFrame();

    expect(namesOn(s, v), ['10', '11', '12', '12A', '13']);
    final project = s.repository.requireProject();
    final made = project.tracks.first.cuts[3].id;
    expect(linkedCutSiblings(project, cutId: made), [const CutId('cut-10')]);
  });

  test('🗣️「다른트랙에 겸용컷만드는게 가능」: copied in one timeline, a '
      'linked paste makes its 겸용 cut in the timeline open now', () {
    final s = session();
    standOnV(s, 1).copyFrame();
    s.timelineVerbs.addTimeline();
    final open = s.repository.requireProject().currentTimeline;
    expect(open.number, 2, reason: '⛔전제: the new timeline is open');

    final pill = StoryboardToolbarPanelContext(s);
    expect(pill.canPasteLinkedFrame, isTrue);
    pill.pasteLinkedFrame();

    final project = s.repository.requireProject();
    final track = project.tracks.single;
    final made = track.cuts.last;
    expect(linkedCutSiblings(project, cutId: made.id), [
      const CutId('cut-10'),
    ]);
    expect(
      {
        for (final group in project.linkRegistry.groups)
          for (final member in group.members)
            if (member.cutId == made.id) member.trackId,
      },
      {track.id},
      reason: 'a member of its links on the track it stands on',
    );
  });

  test('copied in another project, the cuts paste independent only — a '
      'link is the same cel, and no cel of that project is one of this', () {
    final board = AppClipboard();
    final there = session(board: board);
    standOnV(there, 1).copyFrame();
    final here = session(board: board);
    final pill = standOnV(here, 1);

    expect(pill.canPasteLinkedFrame, isFalse);
    expect(pill.canPasteIndependentFrame, isTrue);
    pill.pasteIndependentFrame();
    expect(namesOn(here, v), ['10', '10 Copy', '11', '12', '13']);
  });

  test('one copy in hand: cuts let the rows go, and rows the cuts', () {
    final s = session();
    standOnV(s, 1);
    s.selectLayer(const LayerId('cut-10-a'));
    copyRowsWithThePill(s);
    expect(s.layerClipboard.hasLayerClipboard, isTrue, reason: '⛔전제');

    standOnV(s, 1).copyFrame();
    expect(s.layerClipboard.hasLayerClipboard, isFalse);

    copyRowsWithThePill(s);
    expect(s.cutClipboard.holdsCuts, isFalse);
  });

  test('the timeline panel puts no cut down: its blocks are a cut\'s own', () {
    final s = session();
    standOnV(s, 1).copyFrame();

    final timeline = TimelineToolbarPanelContext(s);
    expect(timeline.canPasteIndependentFrame, isFalse);
    expect(timeline.canPasteLinkedFrame, isFalse);

    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 1,
      headGlobalFrame: 5,
    );
    expect(
      timeline.canCopyFrame,
      isFalse,
      reason: 'a band of cuts is no copy of the timeline\'s',
    );
  });
}
