import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/edge_drag.dart';
import 'package:anicel/src/ui/session/range_selections.dart';
import 'package:anicel/src/ui/session/storyboard_cursor.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// F-283 (유저 2026-10-04): 「타임라인패널의 se블록에 대해 코마조절 1,2,3,4
/// 버튼이 작동안함. 콘티패널에선 작동하는데. 또 법 멋대로 사본만든건지
/// 발견된거같은데 통일. 다른 글로벌트랙도 확인하는거 잊지말고. 블록이면
/// 1,2,3,4 등 코마조절버튼 작동하는게 규칙임」.
///
/// The two panels pressed two verbs. The timeline's read the block off the
/// row the cut SHOWS and handed its start on as it was — and a track-owned
/// row keys its blocks on the track's axis, so past the first cut that start
/// named nothing. Every case here stands in the SECOND cut, where the two
/// axes differ; in the first they agree and all of this passed by accident.
///
/// The collaborators the law lives in — named so `tool/mutation_run.dart`
/// runs this file for each of them.
EdgeDragVerbs commaOf(EditorSessionManager session) => session.edgeDrag;

StoryboardCursor cursorOf(EditorSessionManager session) =>
    session.storyboardCursor;

RangeSelections bandsOf(EditorSessionManager session) =>
    session.rangeSelections;

/// [layer]'s drawing blocks as (start, length), in the keys it stores.
List<(int, int)> blocksOf(Layer layer) => [
  for (final entry in layer.timeline.entries)
    if (entry.value.isDrawing) (entry.key, entry.value.length!),
];

void main() {
  late EditorSessionManager session;
  late LayerId s1;
  late int cut2;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    s1 = session.activeTrack.seLayers.first.id;
    session.cutVerbs.createCut();
    cut2 = session.activeCutGlobalStartFrame;
    expect(
      cut2,
      greaterThan(0),
      reason: 'fixture premise: the open cut is past the first, so a track '
          'row\'s keys are not the cut\'s frames',
    );
  });
  tearDown(() => session.dispose());

  Layer sound() =>
      session.activeTrack.seLayers.firstWhere((layer) => layer.id == s1);

  /// A sound [length] frames long from [localFrame] of the open cut.
  void placeSound(int localFrame, {required int length}) {
    session.selectLayer(s1);
    session.selectFrameIndex(localFrame);
    session.seEntries.createSeEntryAtCurrentFrame(
      name: 'se$localFrame',
      lengthFrames: length,
    );
  }

  /// A cel on the cut's animation row at frame 0, and that row's id.
  LayerId celAtZero() {
    final id = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(id);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    return id;
  }

  Map<int, int> spans() => session.activeTrack.transitionLayer.instructions
      .map((start, span) => MapEntry(start, span.length));

  group('from the timeline', () {
    test('a sound under the cursor takes the comma, at the frame its row '
        'keys it on', () {
      placeSound(3, length: 2);
      expect(blocksOf(sound()), [(cut2 + 3, 2)], reason: 'fixture');
      session.selectFrameIndex(4);

      // The toolbar's own door: its 1/2/3/4 buttons press this.
      final buttons = TimelineToolbarPanelContext(session);
      expect(buttons.canSetComma, isTrue);
      buttons.setComma(4);

      expect(
        blocksOf(sound()),
        [(cut2 + 3, 4)],
        reason: '「타임라인패널의 se블록에 대해 코마조절 1,2,3,4 버튼이 '
            '작동안함」 — the button was lit and the press found no block at '
            'the cut\'s frame 3 of a row keyed on the track\'s',
      );

      session.undo();
      expect(blocksOf(sound()), [(cut2 + 3, 2)], reason: 'one press, one step');
    });

    test('a cel under the cursor takes it at the CUT\'s frame — a cut\'s own '
        'row is read on the cut\'s axis, a track\'s on the track\'s', () {
      final cel = celAtZero();

      expect(cursorOf(session).canSetCommaForTimelineCursor, isTrue);
      commaOf(session).setCommaForTimelineCursor(3);

      expect(blocksOf(session.layerById(cel)!), [(0, 3)]);
    });

    test('a hold\'s ghost is no block: dark, and the row stays as it '
        'stands', () {
      final cel = celAtZero();
      session.rangeMove.setRunEdgeBehavior(
        layerId: cel,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      session.selectFrameIndex(2);
      final before = session.layerById(cel)!.timeline;
      expect(
        coveringDrawingBlockAt(before, 2)?.entry.ghost,
        isTrue,
        reason: 'fixture: the hold drew a ghost of the cel under the cursor',
      );

      expect(cursorOf(session).canSetCommaForTimelineCursor, isFalse);
      commaOf(session).setCommaForTimelineCursor(3);

      expect(session.layerById(cel)!.timeline, before);
    });

    test('a band over the sound still holds it after the press — in the '
        'cut\'s frames — so the next press finds it', () {
      placeSound(3, length: 2);
      // Off the sound first, so only the band can light the buttons.
      session.selectFrameIndex(10);
      session.updateFrameRangeSelectionDrag(
        layerId: s1,
        anchorIndex: 3,
        headIndex: 4,
      );
      expect(
        cursorOf(session).timelineCursorBlockOrNull(),
        isNull,
        reason: 'premise: the cursor itself stands on nothing',
      );

      expect(cursorOf(session).canSetCommaForTimelineCursor, isTrue);
      commaOf(session).setCommaForTimelineCursor(5);

      expect(blocksOf(sound()), [(cut2 + 3, 5)]);
      final band = session.frameRangeSelection.value;
      expect(
        [band?.startIndex, band?.endIndexExclusive],
        [3, 8],
        reason: 'the band follows the re-timed block. It was let go: the '
            're-snap looked the block up on the row the cut shows, by the '
            'start its track keys',
      );

      commaOf(session).setCommaForTimelineCursor(2);
      expect(blocksOf(sound()), [(cut2 + 3, 2)]);
    });

    test('a band over the conte row AND a sound re-times both, and the cut '
        'follows its conte row', () {
      session.layerStack.addLayerOfKind(LayerKind.storyboard);
      session.selectFrameIndex(5);
      session.createDrawingAtCurrentFrame();
      final conte = storyboardLayerForCut(session.requireActiveCut)!.id;
      placeSound(2, length: 2);
      expect(blocksOf(session.layerById(conte)!), [(0, 5), (5, 19)]);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: conte,
        startIndex: 0,
        endIndexExclusive: 5,
        layerIds: [conte, s1],
      );

      commaOf(session).setCommaForTimelineCursor(8);

      expect(blocksOf(session.layerById(conte)!), [(0, 8), (8, 19)]);
      expect(
        blocksOf(sound()),
        [(cut2 + 2, 8)],
        reason: 'the cut-synced commit read each row as the cut shows it, so '
            'the sound — named by its track key — dropped out of the step',
      );
      expect(session.requireActiveCut.duration, 27);

      session.undo();
      expect(blocksOf(session.layerById(conte)!), [(0, 5), (5, 19)]);
      expect(blocksOf(sound()), [(cut2 + 2, 2)]);
      expect(session.requireActiveCut.duration, 24);
    });

    test('a band keeps the rows it swept through the press', () {
      final cel = celAtZero();
      final rows = [LayerRowAddress(cel), LaneRowAddress(cel, 'position')];
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: cel,
        startIndex: 0,
        endIndexExclusive: 1,
        layerIds: [cel],
        rows: rows,
      );

      commaOf(session).setCommaForTimelineCursor(3);

      expect(blocksOf(session.layerById(cel)!), [(0, 3)]);
      final band = session.frameRangeSelection.value;
      expect([band?.startIndex, band?.endIndexExclusive], [0, 3]);
      expect(
        band?.rows,
        rows,
        reason: 'the same rows over the longer cel — the re-snap rebuilt the '
            'band from its layers and the lane it had swept was let go',
      );
    });

    test('a transition span the cut may edit takes the comma, on the '
        'track\'s row', () {
      session.selectLayer(session.activeTrack.transitionLayer.id);
      session.selectFrameIndex(2);
      session.transitions.createTransitionSpanInCut();
      expect(spans(), {cut2 + 2: 1}, reason: 'fixture');

      expect(cursorOf(session).canSetCommaForTimelineCursor, isTrue);
      commaOf(session).setCommaForTimelineCursor(6);

      expect(
        spans(),
        {cut2 + 2: 6},
        reason: '「다른 글로벌트랙도 확인」 — a span is no timeline entry, so '
            'the block lookup never found one and the lit button did nothing',
      );
    });

    test('an O.L\'s mark is drawn here and edited on the storyboard: dark, '
        'and left alone', () {
      session.transitions.updateTransitionInstructions(
        SplayTreeMap<int, InstructionEvent>.from({
          cut2 - 4: const InstructionEvent(instructionId: 'ol', length: 8),
        }),
      );
      session.selectLayer(session.activeTrack.transitionLayer.id);
      session.selectFrameIndex(1);
      expect(
        session.transitions.transitionShownInCutAt(1),
        isTrue,
        reason: 'fixture: the cut draws the mark under the cursor',
      );

      expect(cursorOf(session).canSetCommaForTimelineCursor, isFalse);
      commaOf(session).setCommaForTimelineCursor(3);

      expect(spans(), {cut2 - 4: 8});
    });

    test('a band swept on the storyboard owns the press from here too — '
        'never the row this panel stands on', () {
      placeSound(2, length: 2);
      final cel = celAtZero();
      bandsOf(session).updateTrackRowRangeSelectionByFrame(
        layerId: s1,
        anchorGlobalFrame: cut2 + 2,
        headGlobalFrame: cut2 + 3,
      );
      expect(
        session.timelineStandingRow,
        LayerRowAddress(cel),
        reason: 'fixture: the timeline stands on the cel row, on a cel',
      );

      expect(cursorOf(session).canSetCommaForTimelineCursor, isTrue);
      commaOf(session).setCommaForTimelineCursor(5);

      expect(blocksOf(sound()), [(cut2 + 2, 5)], reason: 'the band\'s sound');
      expect(
        blocksOf(session.layerById(cel)!),
        [(0, 1)],
        reason: 'the band lit the buttons and the press went past it, onto '
            'the cel this panel\'s cursor stood on',
      );
    });

    test('on an image row the buttons are dark — its one block is pinned '
        'where it stands, and the press never had a branch for it', () {
      session.layerStack.addLayerOfKind(LayerKind.image);
      expect(blocksOf(session.activeLayer!), isNotEmpty, reason: 'fixture');
      // Frame 0: the block itself. The cells after it are its hold's ghosts.
      session.selectFrameIndex(0);
      expect(
        session.cells.canDeleteCellAtCurrentFrame,
        isTrue,
        reason: 'premise: the DELETE gate, which this gate borrowed, is lit '
            'on an image row\'s block (F-98)',
      );

      expect(
        TimelineToolbarPanelContext(session).canSetComma,
        isFalse,
        reason: 'the timeline\'s buttons ask the timeline\'s cursor — the '
            'storyboard\'s stands on the cut here, and would light them',
      );
    });

    test('a synced attach row shows its base\'s blocks and owns none: dark, '
        'and nothing is written', () {
      final base = celAtZero();
      session.folders.addAttachedLayer(AttachedPlacement.above);
      final shown = session.activeLayer!;
      expect(isSyncedAttachedLayer(shown), isTrue, reason: 'fixture');
      session.selectFrameIndex(0);
      expect(
        coveringDrawingBlockAt(shown.timeline, 0)?.entry.ghost,
        isFalse,
        reason: 'premise: the mirror under the cursor is a block and no '
            'ghost, so only whose timing it is turns the press away',
      );

      expect(cursorOf(session).canSetCommaForTimelineCursor, isFalse);
      commaOf(session).setCommaForTimelineCursor(3);

      expect(blocksOf(session.layerById(base)!), [(0, 1)]);
      expect(session.layerById(shown.id)!.timeline, shown.timeline);
    });

    test('standing on a lane, the press is the lane\'s, and a lane has no '
        'blocks: the cel of the layer it belongs to keeps its length', () {
      final cel = celAtZero();
      session.standOnRow(LaneRowAddress(cel, 'position'));
      expect(
        session.cellInstances.createInstancesForSelection(),
        isTrue,
        reason: 'premise: a key at the playhead, which lights the delete gate',
      );
      expect(session.cells.canDeleteCellAtCurrentFrame, isTrue);

      expect(cursorOf(session).canSetCommaForTimelineCursor, isFalse);
      commaOf(session).setCommaForTimelineCursor(4);

      expect(
        blocksOf(session.layerById(cel)!),
        [(0, 1)],
        reason: 'F-87\'s law, which this press had not heard: 「키가 없을때 '
            '삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록」 — a lane row '
            'claims the press, and never hands it to its layer\'s cel',
      );
    });
  });

  group('from the storyboard', () {
    test('a band on the track\'s axis follows its sounds, so the second '
        'press lands on the same three', () {
      for (final frame in [0, 1, 2]) {
        placeSound(frame, length: 1);
      }
      bandsOf(session).updateTrackRowRangeSelectionByFrame(
        layerId: s1,
        anchorGlobalFrame: cut2,
        headGlobalFrame: cut2 + 2,
      );

      commaOf(session).setCommaForStoryboardCursor(10);

      expect(blocksOf(sound()), [(cut2, 10), (cut2 + 10, 10), (cut2 + 20, 10)]);
      final band = session.trackFrameRangeSelection.value;
      expect(
        [band?.startFrame, band?.endFrameExclusive],
        [cut2, cut2 + 30],
        reason: 'on the track\'s axis, where its rows\' keys already are',
      );
      expect(band?.anchorRow, LayerRowAddress(s1));

      commaOf(session).setCommaForStoryboardCursor(1);

      expect(
        blocksOf(sound()),
        [(cut2, 1), (cut2 + 1, 1), (cut2 + 2, 1)],
        reason: 'the cut\'s band has followed its cels since UI-R17 #7; this '
            'one stayed where it was swept, and the sounds the first press '
            'pushed out of it were left on tens',
      );
    });

    test('and it keeps the rows it swept', () {
      placeSound(0, length: 1);
      final rows = [
        LayerRowAddress(s1),
        TrackRowAddress(session.selectedTrackId),
      ];
      session.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: session.selectedTrackId,
        anchorRow: rows.first,
        rows: rows,
        startFrame: cut2,
        endFrameExclusive: cut2 + 1,
      );

      commaOf(session).setCommaForStoryboardCursor(4);

      expect(blocksOf(sound()), [(cut2, 4)]);
      final band = session.trackFrameRangeSelection.value;
      expect([band?.startFrame, band?.endFrameExclusive], [cut2, cut2 + 4]);
      expect(band?.rows, rows);
      expect(band?.trackId, session.selectedTrackId);
    });
  });
}
