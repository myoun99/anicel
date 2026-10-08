import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/models/cel_bank_lanes.dart';
import 'package:anicel/src/models/drawing_block_move.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/session/storyboard_cursor.dart';

/// 🗣️F-227 (유저 2026-09-29/30): 「ol주는컷은 콘티블록의 마지막블록을 늘리고
/// 받는컷은 처음블록을 늘리라」 · 「콘티블록의 첫블록을 여백길이 이하로
/// 못줄이게하는게 근본적 맞지않나? … 예를들어 ol여백 12코마면 콘티 첫블록을
/// 12밑으로 못줄이거나」.
///
/// Two 48-frame cuts, each with a two-panel conte (20 + 28), and an O.L of
/// 24 frames centred on their boundary — 12 frames of のりしろ on each side.
/// The のりしろ part of a block is the O.L's, derived: no edit reaches it,
/// and the panel's own part keeps its one-frame floor, so the block never
/// drops below 12 + 1.
void main() {
  const giving = CutId('a');
  const receiving = CutId('b');

  Layer conte(String cut) => Layer(
    id: LayerId('conte-$cut'),
    name: 'conte',
    kind: LayerKind.storyboard,
    frames: [
      Frame(id: FrameId('$cut-p1'), duration: 1, strokes: const []),
      Frame(id: FrameId('$cut-p2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-p1'), length: 20),
      20: TimelineExposure.drawing(FrameId('$cut-p2'), length: 28),
    },
  );

  Cut cut(CutId id) => Cut(
    id: id,
    name: id.value,
    duration: 48,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: [conte(id.value)],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut(giving), cut(receiving)],
          ),
        ],
      ),
    );
    s.transitions.updateTransitionInstructions({
      36: const InstructionEvent(instructionId: 'ol', length: 24),
    });
    return s;
  }

  Layer conteRow(EditorSessionManager s, CutId cutId) => requireLayer(
    s.repository.requireProject(),
    cutId: cutId,
    layerId: LayerId('conte-${cutId.value}'),
  );

  FrameId? shownAt(EditorSessionManager s, CutId cutId, int frame) =>
      exposedFrameIdAt(conteRow(s, cutId).timeline, frame);

  int durationOf(EditorSessionManager s, CutId cutId) => s
      .repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == cutId)
      .duration;

  /// How many of the cut's first frames its first panel is shown for.
  int firstBlockFrames(EditorSessionManager s, CutId cutId) {
    final first = shownAt(s, cutId, 0);
    var frame = 0;
    while (shownAt(s, cutId, frame) == first) {
      frame += 1;
    }
    return frame;
  }

  test('the RECEIVING cut\'s first panel holds back over its 12 frames, '
      'and its second keeps the conte\'s time', () {
    final s = session();
    addTearDown(s.dispose);
    expect(firstBlockFrames(s, receiving), 12 + 20);
    expect(shownAt(s, receiving, 32), const FrameId('b-p2'));
    expect(
      shownAt(s, receiving, 59),
      const FrameId('b-p2'),
      reason: 'the last panel reaches the drawn end, 12 + 48',
    );
  });

  test('the GIVING cut\'s last panel holds 12 frames past the red line', () {
    final s = session();
    addTearDown(s.dispose);
    expect(shownAt(s, giving, 47), const FrameId('a-p2'));
    expect(shownAt(s, giving, 59), const FrameId('a-p2'));
    expect(shownAt(s, giving, 60), isNull);
  });

  test('dragging the receiving cut\'s first panel shorter stops at ONE '
      'conte frame — the block never goes below 12 + 1', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(receiving);
    // The first panel's real block starts where the conte does: 12.
    expect(
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('conte-b'),
        blockStartIndex: 12,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateExposureEdgeDrag(-100);
    s.edgeDrag.endExposureEdgeDrag();
    expect(firstBlockFrames(s, receiving), 12 + 1);
    expect(shownAt(s, receiving, 13), const FrameId('b-p2'));
    expect(
      durationOf(s, receiving),
      1 + 28,
      reason: 'the cut follows its conte, not the のりしろ in front of it',
    );
  });

  test('pulling the giving cut\'s red end line in stops at the last panel\'s '
      'one frame', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(giving);
    expect(
      s.edgeDrag.beginCutEdgeDrag(
        cutId: giving,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateCutEdgeDrag(-100);
    s.edgeDrag.endCutEdgeDrag();
    final cutNow = s.repository.requireProject().tracks.single.cuts.first;
    expect(cutNow.duration, 20 + 1, reason: 'the last panel keeps one frame');
    expect(shownAt(s, giving, 20), const FrameId('a-p2'));
  });

  test('pulling the receiving cut\'s red end line in stops at ITS last '
      'panel\'s one frame — its floor counts the conte, not the のりしろ', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(receiving);
    expect(
      s.edgeDrag.beginCutEdgeDrag(
        cutId: receiving,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.edgeDrag.updateCutEdgeDrag(-100);
    s.edgeDrag.endCutEdgeDrag();
    expect(durationOf(s, receiving), 20 + 1);
    expect(firstBlockFrames(s, receiving), 12 + 20);
  });

  test('a panel of the receiving cut traded on the storyboard keeps the '
      'conte\'s time — the strip counts from the conte start', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(receiving);
    expect(
      s.edgeDrag.beginCutEdgeDrag(
        cutId: receiving,
        edge: TimelineBlockEdge.start,
        panelIndex: 1,
      ),
      isTrue,
    );
    s.edgeDrag.updateCutEdgeDrag(5);
    s.edgeDrag.endCutEdgeDrag();
    expect(firstBlockFrames(s, receiving), 12 + 25);
    expect(shownAt(s, receiving, 37), const FrameId('b-p2'));
    expect(durationOf(s, receiving), 48);
  });

  test('the O.L going away brings the receiving cut\'s panels back to its '
      'conte\'s own start', () {
    final s = session();
    addTearDown(s.dispose);
    s.transitions.updateTransitionInstructions(const {});
    expect(
      {
        for (final entry in conteRow(s, receiving).timeline.entries)
          entry.key: entry.value.length,
      },
      {0: 20, 20: 28},
    );
  });

  test('a receiving cut\'s conte slides no panel into its のりしろ — the '
      'row still has no room in front of its first panel', () {
    final s = session();
    addTearDown(s.dispose);
    final row = conteRow(s, receiving);
    expect(
      planDrawingRangeMove(
        source: row,
        target: row,
        rangeStartIndex: 12,
        rangeEndIndexExclusive: 32,
        frameDelta: -5,
        sourceBank: CelBankLanes.unshared,
        cutFrameCount: 48,
      ),
      isNull,
    );
  });

  test('the receiving cut\'s first REAL panel carries no front grip — its '
      'front is the conte\'s start, the frames before it are derived', () {
    final s = session();
    addTearDown(s.dispose);
    final grips = timelineLayerGripBlocks(
      conteRow(s, receiving),
      suppressFirstStartGrip: true,
    );
    expect(grips.first.startIndex, 12);
    expect(grips.first.startGrip, isFalse);
    expect(grips.last.startGrip, isTrue);
  });

  // The storyboard and the conte tab count the CONTE's time; the row counts
  // the cut's frames — which begin 12 early in the receiving cut.
  group('conte-time verbs find the receiving cut\'s panel by its conte '
      'time', () {
    test('an action written on panel 2 lands on panel 2 — and the conte '
        'sheet prints it there', () {
      final s = session();
      addTearDown(s.dispose);
      s.storyboardCursor.setStoryboardCellAction(
        cutId: receiving,
        cellIndex: 1,
        action: 'run',
      );
      expect(conteRow(s, receiving).timeline[32]!.memo?.actionMemo, 'run');
      final sheet = buildConteSheetSource(s.repository.requireProject());
      final cut = sheet.cuts.firstWhere(
        (cut) => cut.cutId == receiving,
      );
      expect(cut.cells[1].action, 'run');
    });

    test('ink named for panel 2 in the conte tab is written on panel 2', () {
      final s = session();
      addTearDown(s.dispose);
      final inkId = s.storyboardCursor.conteInkIdFor(receiving, 20);
      s.storyboardCursor.writeConteBlockInk(receiving, inkId);
      expect(conteRow(s, receiving).timeline[32]!.memo?.inkId, inkId);
    });

    test('the storyboard cursor 25 frames into the receiving cut stands on '
        'panel 2 on the conte row — conte time, not the held-back frames', () {
      final s = session();
      addTearDown(s.dispose);
      s.selectCut(receiving);
      s.standOnRow(
        LayerRowAddress(trackConteRowId(const TrackId('t'))),
        panel: WorkingPanel.storyboard,
        frameIndex: 25,
      );
      final block = s.storyboardCursor.storyboardCursorBlockOrNull();
      expect(block, isA<StoryboardCursorStoryboardPanel>());
      expect(
        (block! as StoryboardCursorStoryboardPanel).panelStartIndex,
        32,
      );
    });

    // I-73 (유저 2026-10-08: 「v행에서는 콘티블록에 서있다거나 하는걸
    // 안하도록」): ↩️the V row answered with that panel until the panels had
    // a row of their own.
    test('… and on the V row, on the CUT', () {
      final s = session();
      addTearDown(s.dispose);
      s.selectCut(receiving);
      s.standOnRow(
        const TrackRowAddress(TrackId('t')),
        panel: WorkingPanel.storyboard,
        frameIndex: 25,
      );
      final block = s.storyboardCursor.storyboardCursorBlockOrNull();
      expect(block, isA<StoryboardCursorCutBlock>());
      expect((block! as StoryboardCursorCutBlock).cut.id, receiving);
    });
  });
}
