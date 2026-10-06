import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// F-281 (유저 2026-10-04): 「se행의 복사,붙여넣기, 타임라인패널에선 되는데
/// 콘티패널에선 se블록을 복사가 안됨. 로컬이든 글로벌이든 가능하도록 통일.
/// 다른 로컬/글로벌 트랙 존재하는 행도 마찬가지 법 통일」.
///
/// The clipboard read its place off the cut's view — the active layer, the
/// cut's playhead, the cut's band — so the storyboard, standing on the very
/// sound the timeline copied, had four dark buttons, and in a gap (no cut,
/// no active layer) both panels did. The verbs take a PLACE now and each
/// panel answers only where it stands.
///
/// Every case stands in the SECOND cut or in a gap: in the first cut a
/// track row's frames and the cut's are the same numbers.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
FrameClipboard boardOf(EditorSessionManager session) => session.clipboard;

/// A row's blocks as (start, length, the name its drawing wears).
List<(int, int, String?)> blocksOf(Layer layer) => [
  for (final entry in layer.timeline.entries)
    if (entry.value.isDrawing)
      (
        entry.key,
        entry.value.length!,
        layer.frameById(entry.value.frameId!)?.name,
      ),
];

/// The four buttons as a panel answers them: cut, copy, paste, linked paste.
List<bool> fourOf(ToolbarPanelContext panel) => [
  panel.canCutRun,
  panel.canCopyFrame,
  panel.canPasteIndependentFrame,
  panel.canPasteLinkedFrame,
];

void main() {
  group('inside a cut past the first', () {
    late EditorSessionManager session;
    late LayerId s1;
    late LayerId cel;
    late int cut2;
    late StoryboardToolbarPanelContext rail;
    late TimelineToolbarPanelContext timeline;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      s1 = session.activeTrack.seLayers.first.id;
      session.cutVerbs.createCut();
      cut2 = session.activeCutGlobalStartFrame;
      expect(cut2, greaterThan(0), reason: 'fixture premise');
      // Two sounds: 「a」 on frames 3–4 of the cut, 「b」 on frame 6.
      session.selectLayer(s1);
      session.selectFrameIndex(3);
      session.seEntries.createSeEntryAtCurrentFrame(name: 'a', lengthFrames: 2);
      session.selectFrameIndex(6);
      session.seEntries.createSeEntryAtCurrentFrame(name: 'b', lengthFrames: 1);
      // The timeline's own row holds a cel under its cursor, so wherever the
      // rail answered with the timeline's place its copy would be lit.
      cel = session.layers
          .firstWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      session.selectLayer(cel);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      rail = StoryboardToolbarPanelContext(session);
      timeline = TimelineToolbarPanelContext(session);
    });
    tearDown(() => session.dispose());

    Layer sound() =>
        session.activeTrack.seLayers.firstWhere((layer) => layer.id == s1);

    /// Stands the rail on the S row at [local] of the open cut, the way a
    /// press on its cell does.
    void standOnTheSoundRow(int local) => session.standing.standInStoryboard(
      () {
        session.selectRow(LayerRowAddress(s1));
        session.selectGlobalFrame(cut2 + local);
      },
    );

    void sweep(int firstLocal, int lastLocal) =>
        session.rangeSelections.updateTrackRowRangeSelectionByFrame(
          layerId: s1,
          anchorGlobalFrame: cut2 + firstLocal,
          headGlobalFrame: cut2 + lastLocal,
        );

    test('standing on a sound, the rail\'s cut and copy are lit — as the '
        'timeline\'s are over the same block', () {
      standOnTheSoundRow(3);

      expect(
        fourOf(rail),
        [true, true, false, false],
        reason: '「콘티패널에선 se블록을 복사가 안됨」 — every one of the four '
            'was dark here',
      );
      expect(fourOf(timeline), fourOf(rail), reason: 'one answer, two doors');
    });

    test('a copy made on the rail pastes one comma at the track\'s frame the '
        'rail stands at — one undo', () {
      standOnTheSoundRow(3);
      rail.copyFrame();
      standOnTheSoundRow(10);
      expect(fourOf(rail), [false, false, true, false]);

      rail.pasteIndependentFrame();

      expect(blocksOf(sound()), [
        (cut2 + 3, 2, 'a'),
        (cut2 + 6, 1, 'b'),
        (cut2 + 10, 1, 'a'),
      ]);
      session.undo();
      expect(blocksOf(sound()), [(cut2 + 3, 2, 'a'), (cut2 + 6, 1, 'b')]);
    });

    test('a cut lifts the sound under the rail\'s cursor, and the board '
        'gives it back', () {
      standOnTheSoundRow(6);

      rail.cutRun();

      expect(blocksOf(sound()), [(cut2 + 3, 2, 'a')]);
      standOnTheSoundRow(12);
      rail.pasteIndependentFrame();
      expect(blocksOf(sound()), [(cut2 + 3, 2, 'a'), (cut2 + 12, 1, 'b')]);
    });

    test('a sound links nowhere, from either panel (F-115)', () {
      standOnTheSoundRow(3);
      rail.copyFrame();
      standOnTheSoundRow(10);

      expect(rail.canPasteLinkedFrame, isFalse);
      rail.pasteLinkedFrame();

      expect(blocksOf(sound()), [(cut2 + 3, 2, 'a'), (cut2 + 6, 1, 'b')]);
    });

    test('a band swept on the rail is the run: copied with its commas and '
        'its gap', () {
      sweep(3, 6);
      standOnTheSoundRow(3);
      expect(session.trackFrameRangeSelection.value, isNotNull);

      rail.copyFrame();
      session.clearStoryboardCutSelection();
      standOnTheSoundRow(14);
      rail.pasteIndependentFrame();

      expect(
        blocksOf(sound()),
        [
          (cut2 + 3, 2, 'a'),
          (cut2 + 6, 1, 'b'),
          (cut2 + 14, 2, 'a'),
          (cut2 + 17, 1, 'b'),
        ],
        reason: 'a band on the track\'s axis was no selection to the board: '
            'the copy banked the one cell under the cursor',
      );
    });

    test('a cut under the rail\'s band lifts exactly the band, and lets it '
        'go', () {
      sweep(3, 4);
      standOnTheSoundRow(3);

      rail.cutRun();

      expect(blocksOf(sound()), [(cut2 + 6, 1, 'b')]);
      expect(session.trackFrameRangeSelection.value, isNull);
    });

    test('a paste under the rail\'s band replaces what the band covers — '
        'wherever the cursor stands on that row', () {
      standOnTheSoundRow(6);
      rail.copyFrame();
      sweep(3, 4);
      standOnTheSoundRow(10);
      expect(session.trackFrameRangeSelection.value, isNotNull);

      rail.pasteIndependentFrame();

      expect(
        blocksOf(sound()).first,
        (cut2 + 3, 1, 'b'),
        reason: '「선택이 있으면 갈아끼우기」 — the clip goes in where the band '
            'starts, on the track\'s axis, not at the cursor',
      );
      expect(
        blocksOf(sound()).where((block) => block.$3 == 'a'),
        isEmpty,
        reason: 'the two cells the band covered came out',
      );
      expect(session.trackFrameRangeSelection.value, isNull);
    });

    test('the timeline serves the rail\'s band where it covers the row the '
        'timeline stands on, and stands down where it does not', () {
      standOnTheSoundRow(6);
      rail.copyFrame();
      sweep(3, 4);
      // The timeline, on the same S row, away from the band's cells.
      session.selectLayer(s1);
      session.selectFrameIndex(10);
      expect(session.trackFrameRangeSelection.value, isNotNull);

      // On the cel row first: the band names a row that press would miss.
      session.selectLayer(cel);
      session.selectFrameIndex(0);
      expect(
        fourOf(timeline),
        [false, false, false, false],
        reason: 'a band is a subject claim on either axis — the press must '
            'not land on a row the band never swept',
      );
      timeline.copyFrame();
      expect(boardOf(session).bankedRowLayerIds, [s1]);

      session.selectLayer(s1);
      session.selectFrameIndex(10);
      timeline.pasteIndependentFrame();

      expect(blocksOf(sound()).first, (cut2 + 3, 1, 'b'));
      expect(session.trackFrameRangeSelection.value, isNull);
    });

    test('the cut\'s own band, from the timeline: a cut is lit by the band '
        'alone — the cursor on a hold\'s ghost, where no block stands — '
        'lifts what the band covers, and lets the band go', () {
      session.rangeMove.setRunEdgeBehavior(
        layerId: cel,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      session.selectLayer(cel);
      session.selectFrameIndex(2);
      final held = session.layerById(cel)!.timeline;
      expect(
        coveringDrawingBlockAt(held, 2)?.entry.ghost,
        isTrue,
        reason: 'fixture: the cursor stands on the hold\'s ghost',
      );
      expect(
        timeline.canCutRun,
        isFalse,
        reason: 'premise (F-107): standing there with no band, a cut would '
            'lift nothing',
      );
      session.updateFrameRangeSelectionDrag(
        layerId: cel,
        anchorIndex: 0,
        headIndex: 0,
      );

      expect(timeline.canCutRun, isTrue, reason: 'the band is what it lifts');
      timeline.cutRun();

      expect(blocksOf(session.layerById(cel)!), isEmpty);
      expect(session.frameRangeSelection.value, isNull);
    });

    test('…and a paste under it replaces what it covers and lets it go', () {
      session.selectLayer(cel);
      session.selectFrameIndex(0);
      timeline.copyFrame();
      session.updateFrameRangeSelectionDrag(
        layerId: cel,
        anchorIndex: 0,
        headIndex: 0,
      );
      expect(session.frameRangeSelection.value, isNotNull, reason: 'fixture');

      timeline.pasteIndependentFrame();

      expect(blocksOf(session.layerById(cel)!), hasLength(1));
      expect(session.frameRangeSelection.value, isNull);
    });

    test('a band over two S rows takes both, each on its own row', () {
      rail.addLayer();
      final s2 = session.activeTrack.seLayers.last.id;
      expect(s2, isNot(s1), reason: 'fixture: a second S row');
      session.selectLayer(s2);
      session.selectFrameIndex(3);
      session.seEntries.createSeEntryAtCurrentFrame(name: 'c', lengthFrames: 2);
      Layer second() =>
          session.activeTrack.seLayers.firstWhere((layer) => layer.id == s2);
      session.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: session.selectedTrackId,
        anchorRow: LayerRowAddress(s1),
        rows: [LayerRowAddress(s1), LayerRowAddress(s2)],
        startFrame: cut2 + 3,
        endFrameExclusive: cut2 + 5,
      );
      standOnTheSoundRow(3);

      rail.cutRun();

      expect(boardOf(session).bankedRowLayerIds, [s1, s2]);
      expect(blocksOf(sound()), [(cut2 + 6, 1, 'b')]);
      expect(blocksOf(second()), isEmpty);

      session.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: session.selectedTrackId,
        anchorRow: LayerRowAddress(s1),
        rows: [LayerRowAddress(s1), LayerRowAddress(s2)],
        startFrame: cut2 + 12,
        endFrameExclusive: cut2 + 14,
      );
      standOnTheSoundRow(12);
      rail.pasteIndependentFrame();

      expect(blocksOf(sound()), [(cut2 + 6, 1, 'b'), (cut2 + 12, 2, 'a')]);
      expect(blocksOf(second()), [(cut2 + 12, 2, 'c')]);
    });

    test('on the V row and the transition row the rail stands on nothing '
        'the board serves — whatever the timeline\'s own cursor holds', () {
      standOnTheSoundRow(3);
      rail.copyFrame();
      session.selectLayer(cel);
      session.selectFrameIndex(0);
      expect(
        fourOf(timeline),
        [true, true, true, false],
        reason: 'premise: the timeline\'s place is lit',
      );

      for (final row in [
        TrackRowAddress(session.selectedTrackId),
        LayerRowAddress(session.activeTrack.transitionLayer.id),
      ]) {
        session.selectRow(row);
        expect(session.storyboardStandingRow, row, reason: 'fixture');
        expect(fourOf(rail), [false, false, false, false], reason: '$row');
      }
    });
  });

  group('parked in a gap', () {
    const trackId = TrackId('f281-track');
    const seLayerId = LayerId('f281-se');

    Cut cut(String id, int duration, {int leadingGap = 0}) => Cut(
      id: CutId(id),
      name: id,
      duration: duration,
      leadingGapFrames: leadingGap,
      canvasSize: const CanvasSize(width: 320, height: 180),
      layers: [
        Layer(
          id: LayerId('$id-cel'),
          name: 'A',
          frames: const [],
          timeline: {},
        ),
      ],
    );

    /// cut-1 covers [0,8); a gap at [8,12); cut-2 covers [12,18). The S row
    /// holds one sound, inside the gap: frames 9–10.
    EditorSessionManager session() {
      final manager = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('f281'),
          name: 'F-281',
          createdAt: DateTime.utc(2026, 10, 6),
          tracks: [
            Track(
              id: trackId,
              name: 'Video',
              cuts: [cut('cut-1', 8), cut('cut-2', 6, leadingGap: 4)],
              seLayers: [
                Layer(
                  id: seLayerId,
                  name: 'S1',
                  kind: LayerKind.se,
                  frames: [
                    Frame(
                      id: const FrameId('se-one'),
                      duration: 2,
                      name: 'One!',
                      strokes: const [],
                    ),
                  ],
                  timeline: const {
                    9: TimelineExposure.drawing(FrameId('se-one'), length: 2),
                  },
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(manager.dispose);
      manager.selectRow(const LayerRowAddress(seLayerId));
      return manager;
    }

    Layer row(EditorSessionManager s) => s.trackSeGlobalLayerById(seLayerId)!;

    test('a track\'s row answers with no cut at all — the rail copies, '
        'pastes and cuts where the timeline has no row to stand on', () {
      final s = session();
      final rail = StoryboardToolbarPanelContext(s);
      s.selectGlobalFrame(9);
      expect(
        [s.editingSession.playheadInGap, s.activeCutOrNull, s.activeLayer],
        [true, null, null],
        reason: 'fixture premise: parked in the gap, with no cut and so no '
            'active layer',
      );
      expect(fourOf(TimelineToolbarPanelContext(s)), [
        false,
        false,
        false,
        false,
      ]);

      expect(
        fourOf(rail),
        [true, true, false, false],
        reason: 'H11: 「각 행들은 독립적인 글로벌행이라 뭐든 가능해야함」',
      );
      rail.copyFrame();
      s.selectGlobalFrame(11);
      rail.pasteIndependentFrame();
      expect(blocksOf(row(s)), [(9, 2, 'One!'), (11, 1, 'One!')]);

      s.selectGlobalFrame(9);
      rail.cutRun();
      expect(blocksOf(row(s)), [(11, 1, 'One!')]);
      s.undo();
      expect(blocksOf(row(s)), [(9, 2, 'One!'), (11, 1, 'One!')]);
    });

    test('what was copied in the gap pastes inside a cut, at the track\'s '
        'frame', () {
      final s = session();
      final rail = StoryboardToolbarPanelContext(s);
      s.selectGlobalFrame(9);
      rail.copyFrame();
      s.selectGlobalFrame(0);
      expect(
        rail.canPasteIndependentFrame,
        isTrue,
        reason: 'the film\'s first frame is a frame like any other — the '
            'place refuses a NEGATIVE frame, not frame 0',
      );

      s.selectGlobalFrame(14); // cut-2 covers [12,18): its frame 2.
      expect(s.activeCutOrNull?.id, const CutId('cut-2'), reason: 'fixture');
      rail.pasteIndependentFrame();

      expect(blocksOf(row(s)), [(9, 2, 'One!'), (14, 1, 'One!')]);
    });
  });
}
