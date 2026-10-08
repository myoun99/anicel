import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️I-73 (유저 2026-10-08): 「v행 아래에 콘티행 만들어서 거기서 … 콘티행에
/// 서야 콘티행에 서도록」 · 「콘티행도 동일하게 하고싶으니까」 · 「삭제는
/// 컷이아니라 해당 서있는 칸이지워지게」.
///
/// The conte row is ONE row over every cut, and what it stands on is the
/// conte layer of the cut under the playhead — the layer standing there
/// seated the timeline on ([conteLayerInHand]). While that holds, the frame
/// buttons the storyboard has no answer of its own for are the TIMELINE's,
/// on the same cell: the answers its own panel gives. Where the row holds
/// no cell — a cut with no conte layer, a gap, a layer picked in the
/// timeline since — they are dark, and nothing of another row moves.
///
/// Cut a (0..24) has a conte layer of three panels of eight, the third
/// showing the FIRST's cel; cut b (24..48) has none; four frames of gap;
/// cut c (52..76) has one panel.
void main() {
  const trackId = TrackId('t');
  const a = CutId('a');
  const conteA = LayerId('sb-a');
  final conteRow = LayerRowAddress(trackConteRowId(trackId));

  Layer conte(String cut, Map<int, (String, int)> panels) => Layer(
    id: LayerId('sb-$cut'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [
      for (final cel in {for (final panel in panels.values) panel.$1})
        Frame(id: FrameId('$cel-$cut'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final MapEntry(:key, :value) in panels.entries)
        key: TimelineExposure.drawing(
          FrameId('${value.$1}-$cut'),
          length: value.$2,
        ),
    },
  );

  Cut cut(String id, {Layer? conteLayer, int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: LayerId('cel-$id'),
        name: 'A',
        frames: [
          Frame(id: FrameId('c1-$id'), duration: 1, strokes: const []),
          Frame(id: FrameId('c2-$id'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('c1-$id'), length: 12),
          12: TimelineExposure.drawing(FrameId('c2-$id'), length: 12),
        },
      ),
      ?conteLayer,
    ],
  );

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [
              cut(
                'a',
                conteLayer: conte('a', {
                  0: ('p1', 8),
                  8: ('p2', 8),
                  16: ('p1', 8),
                }),
              ),
              cut('b'),
              cut('c', gap: 4, conteLayer: conte('c', {0: ('p1', 24)})),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(a);
    session.selectLayer(const LayerId('cel-a'));
    return session;
  }

  /// The storyboard, stood on its conte row at [globalFrame].
  EditorSessionManager onTheConteRow(int globalFrame) => open()
    ..standOnRow(
      conteRow,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: globalFrame,
    );

  /// The TIMELINE, stood on cut a's conte layer at [frame] — the panel whose
  /// answers the conte row borrows.
  EditorSessionManager onTheTimelinesRow(int frame) => open()
    ..standOnRow(const LayerRowAddress(conteA))
    ..selectFrameIndex(frame);

  Layer conteOf(EditorSessionManager session, [CutId cutId = a]) =>
      storyboardLayerForCut(
        session.repository.requireProject().tracks.single.cuts.firstWhere(
          (cut) => cut.id == cutId,
        ),
      )!;

  /// The row's blocks as `key: (cel, length)`.
  Map<int, (String, int)> blocksOf(EditorSessionManager session) => {
    for (final MapEntry(:key, :value) in conteOf(session).timeline.entries)
      if (!value.ghost) key: (value.frameId!.value, value.length!),
  };

  /// What a panel's buttons answer — every one the conte row borrows.
  Map<String, Object?> answersOf(
    ToolbarPanelContext panel,
    EditorSessionManager session,
  ) => {
    'edit': panel.canEditInstance,
    'X': panel.canBlankExposure,
    'mark': panel.canToggleMark,
    'cut': panel.canCutRun,
    'copy': panel.canCopyFrame,
    'paste': panel.canPasteIndependentFrame,
    'paste linked': panel.canPasteLinkedFrame,
    'row span': panel.canSelectRowSpan,
    'unlink': panel.canUnlink,
    'auto-name': panel.canAutoName,
    'push': session.blockShift.canPushBlocks(
      currentRow: panel.shiftCurrentRow,
    ),
    'pull': session.blockShift.canPullBlocks(
      currentRow: panel.shiftCurrentRow,
    ),
  };

  Map<String, Object?> storyboardsAnswers(EditorSessionManager session) =>
      answersOf(StoryboardToolbarPanelContext(session), session);

  Map<String, Object?> timelinesAnswers(EditorSessionManager session) =>
      answersOf(TimelineToolbarPanelContext(session), session);

  group('over a panel', () {
    // Frame 18 is inside the THIRD panel, which shows the first's cel.
    test('⛔전제: standing there seated the timeline on the cut\'s conte '
        'layer', () {
      final session = onTheConteRow(18);
      expect(session.storyboardStandingRow, conteRow);
      expect(session.activeLayerId, conteA);
      expect(session.workingPanel, WorkingPanel.storyboard);
    });

    test('every borrowed button answers as the timeline\'s does on that '
        'cell', () {
      final storyboard = storyboardsAnswers(onTheConteRow(18));
      final timeline = timelinesAnswers(onTheTimelinesRow(18));

      expect(storyboard, timeline);
      expect(
        [
          for (final lit in ['edit', 'mark', 'cut', 'copy', 'row span'])
            storyboard[lit],
          storyboard['unlink'],
          storyboard['push'],
        ],
        everyElement(isTrue),
        reason: 'LIVENESS: they are lit — two dark panels agree as well',
      );
    });

    test('Edit is the panel\'s own', () {
      final panel = StoryboardToolbarPanelContext(onTheConteRow(18));
      expect(panel.editTarget, isA<StoryboardEditConteCells>());
    });

    test('🗣️Delete removes the PANEL — the timeline\'s own delete, on that '
        'cell — and the cut stays', () {
      final session = onTheConteRow(10);
      final panel = StoryboardToolbarPanelContext(session);
      expect(panel.deleteSubject, PillSubject.cells);
      panel.deleteSelectionSubject();

      final timeline = onTheTimelinesRow(10);
      TimelineToolbarPanelContext(timeline).deleteSelectionSubject();

      expect(
        blocksOf(session),
        {0: ('p1-a', 16), 16: ('p1-a', 8)},
        reason: 'the second panel is gone, and the one before it took its '
            'frames — a conte row has no hole',
      );
      expect(blocksOf(session), blocksOf(timeline));
      expect(
        session.repository.requireProject().tracks.single.cuts.map(
          (cut) => cut.id.value,
        ),
        ['a', 'b', 'c'],
        reason: '↩️D28 kept the CUT answer for a panel under the V row',
      );
    });

    test('행 전체 선택 takes the cut\'s conte row whole — a band of the '
        'cut\'s own, as a sweep on this row is', () {
      final session = onTheConteRow(10);
      StoryboardToolbarPanelContext(session).selectRowSpan();

      final band = session.frameRangeSelection.value;
      expect(band?.layerId, conteA);
      expect((band?.startIndex, band?.endIndexExclusive), (0, 24));
      expect(session.trackFrameRangeSelection.value, isNull);
    });

    test('링크 독립 gives the panel a cel of its own', () {
      final session = onTheConteRow(18);
      StoryboardToolbarPanelContext(session).unlink();

      final cels = [for (final block in blocksOf(session).values) block.$1];
      expect(cels.toSet(), hasLength(3), reason: 'three panels, three cels');
      expect(cels.first, 'p1-a', reason: 'the other keeps the one it had');
    });

    test('the shove moves this row\'s panels, as the timeline\'s shove of '
        'that row does', () {
      final session = onTheConteRow(10);
      final panel = StoryboardToolbarPanelContext(session);
      session.blockShift.pushBlocks(1, currentRow: panel.shiftCurrentRow);

      final timeline = onTheTimelinesRow(10);
      timeline.blockShift.pushBlocks(
        1,
        currentRow: TimelineToolbarPanelContext(timeline).shiftCurrentRow,
      );

      expect(blocksOf(session), isNot(blocksOf(open())), reason: 'LIVENESS');
      expect(blocksOf(session), blocksOf(timeline));
    });
  });

  /// Every button the row borrows, dark.
  final dark = isA<Map<String, Object?>>().having(
    (answers) => answers.values.toSet(),
    'answers',
    {false},
  );

  group('where the row holds no cell, nothing is lit and no other row '
      'moves', () {
    test('crossed into a cut with no conte layer', () {
      // Stood on a panel, then the ruler into cut b: the row is still the
      // conte row, and the timeline is on a row of b's own.
      final session = onTheConteRow(10)..selectGlobalFrame(30);
      expect(session.storyboardStandingRow, conteRow, reason: '⛔전제');
      expect(session.activeLayerId, const LayerId('cel-b'), reason: '⛔전제');
      final panel = StoryboardToolbarPanelContext(session);

      expect(storyboardsAnswers(session), dark);
      expect(panel.editTarget, isNull);
      expect(panel.deleteSubject, PillSubject.nothing);
      expect(panel.canSetComma, isFalse);
      expect(panel.canCreateInstance, isFalse);
      expect(
        timelinesAnswers(session)['push'],
        isTrue,
        reason: 'LIVENESS: the timeline\'s own shove of the cel is there — '
            'it is this rail\'s that refuses it',
      );
    });

    test('parked in the gap', () {
      final session = onTheConteRow(10)..selectGlobalFrame(49);
      expect(session.activeCutOrNull, isNull, reason: '⛔전제');
      expect(session.storyboardStandingRow, conteRow, reason: '⛔전제');
      final panel = StoryboardToolbarPanelContext(session);

      expect(storyboardsAnswers(session), dark);
      expect(panel.deleteSubject, PillSubject.nothing);
      expect(panel.canSetComma, isFalse);
      expect(panel.canCreateInstance, isFalse);
    });

    test('a layer picked in the timeline since is that panel\'s subject, '
        'not this row\'s', () {
      final session = onTheConteRow(10)
        ..standOnRow(const LayerRowAddress(LayerId('cel-a')));
      expect(session.storyboardStandingRow, conteRow, reason: '⛔전제');
      expect(session.activeLayerId, const LayerId('cel-a'), reason: '⛔전제');

      expect(storyboardsAnswers(session), dark);
      expect(
        timelinesAnswers(session)['copy'],
        isTrue,
        reason: 'LIVENESS: the timeline\'s cel is there to copy',
      );
    });
  });

  // F-186 named 링크 독립 among the verbs a conte-block band takes from the
  // timeline, and the rung never asked it (🧪2026-10-08).
  test('a band over a panel that shares its cel lights 링크 독립, as the '
      'timeline\'s band does', () {
    final session = onTheConteRow(18)
      ..updateFrameRangeSelectionDrag(
        layerId: conteA,
        anchorIndex: 17,
        headIndex: 18,
      );
    expect(session.cells.cellSelectionClaimsSubject, isTrue, reason: '⛔전제');

    expect(StoryboardToolbarPanelContext(session).canUnlink, isTrue);
    expect(TimelineToolbarPanelContext(session).canUnlink, isTrue);
  });

  test('the V row above stays the CUT\'s: none of the timeline\'s cell '
      'buttons, and Delete names the cut', () {
    // From the conte row, so the timeline still stands on the conte layer
    // — a cut keeps the row it was left on. What is in hand is not what
    // decides: the ROW the storyboard stands on does.
    final session = onTheConteRow(10)
      ..standOnRow(
        const TrackRowAddress(trackId),
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 10,
      );
    expect(session.activeLayerId, conteA, reason: '⛔전제');
    final panel = StoryboardToolbarPanelContext(session);

    expect(panel.editTarget, isA<StoryboardEditCut>());
    expect(panel.canToggleMark, isFalse);
    expect(panel.canCopyFrame, isFalse);
    expect(panel.canSelectRowSpan, isTrue, reason: 'D40: the cuts\' span');
    session.storyboardCursor.deleteBlockAtStoryboardCursor();
    expect(
      session.repository.requireProject().tracks.single.cuts.map(
        (cut) => cut.id.value,
      ),
      ['b', 'c'],
    );
  });
}
