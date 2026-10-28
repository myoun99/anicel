import 'package:flutter/material.dart'
    show Builder, MaterialApp, Text, TextButton;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/dialogs/frame_name_conflict_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/paste_linked_asking_first.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/place_lines.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️one-band-no-lane-tail-Q1 (유저 2026-10-27): 「칸과 키를 같이 든다」 — a
/// band swept over a row's cells and its lanes copies both: 「띠의 칸(블록)과
/// 띠의 레인 행 키를 한 복사본에 같이 싣는다. 붙여넣으면 서 있는 칸에 블록, 그
/// 레이어의 같은 레인에 키 — 옮기기(H20)가 띠를 옮기는 것과 같은 모양」. The
/// cut lifts both, the paste and the linked paste lay both, each one undo.
///
/// ↩️The board held one kind at a time, and a frame copy held cells alone:
/// such a band copied its cells and left its keys, and stood on its lane
/// the copy was dark — on the conte it took the one key at the playhead.
const _a = LayerId('band-a');
const _b = LayerId('band-b');
const _c = LayerId('band-c');
const _s1 = LayerId('band-s1');
const _position = 'position';

/// A Position key at [frame] holding (x, x), called [name].
PropertyTrack<CanvasPoint> _keyed(int frame, double x, {String? name}) =>
    PropertyTrack<CanvasPoint>(
      keys: {frame: PropertyKey(CanvasPoint(x: x, y: x), name: name)},
    );

/// A row holding one three-frame block of its drawing from frame 0 — none
/// with [drawn] false — and the Position keys [position].
Layer _row(
  LayerId id, {
  LayerKind kind = LayerKind.animation,
  bool drawn = true,
  required PropertyTrack<CanvasPoint> position,
}) => Layer(
  id: id,
  name: id.value,
  kind: kind,
  transformTrack: TransformTrack.empty().copyWith(position: position),
  frames: [
    if (drawn)
      Frame(
        id: FrameId('${id.value}-f'),
        duration: 3,
        name: 'A1',
        strokes: const [],
      ),
  ],
  timeline: {
    if (drawn) 0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 3),
  },
);

EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('band-project'),
      name: 'Band',
      createdAt: DateTime.utc(2026, 10, 27),
      tracks: [
        Track(
          id: const TrackId('band-track'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('band-cut'),
              name: '1',
              duration: 24,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [
                _row(_a, position: _keyed(0, 1, name: 'K')),
                // The same name, held at another value on another row.
                _row(_b, drawn: false, position: _keyed(10, 5, name: 'K')),
                // Its own drawing called A1, and the name K at another
                // value — with a key of its own inside the first band.
                _row(
                  _c,
                  position: PropertyTrack<CanvasPoint>(
                    keys: {
                      2: PropertyKey(CanvasPoint(x: 7, y: 7)),
                      10: PropertyKey(CanvasPoint(x: 5, y: 5), name: 'K'),
                    },
                  ),
                ),
              ],
            ),
          ],
          seLayers: [
            _row(_s1, kind: LayerKind.se, position: _keyed(0, 1)),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

Layer _cutRow(EditorSessionManager s, LayerId id) =>
    s.layers.firstWhere((layer) => layer.id == id);

Layer _seRow(EditorSessionManager s) =>
    s.repository.requireProject().tracks.single.seLayers.single;

/// [row]'s Position keys by frame, each as (x, name).
Map<int, (double, String?)> _keysOf(Layer row) => {
  for (final MapEntry(key: frame, value: key)
      in row.transformTrack.position.keys.entries)
    frame: (key.value.x, key.name),
};

/// [row]'s blocks by start, each its length.
Map<int, int?> _blocksOf(Layer row) => {
  for (final MapEntry(key: start, value: block) in row.timeline.entries)
    if (!block.ghost && block.frameId != null) start: block.length,
};

/// The band over [_a]'s cells 0..5 and its Position lane.
void _sweepAAndItsLane(EditorSessionManager s) =>
    s.updateFrameRangeSelectionDrag(
      layerId: _a,
      anchorIndex: 0,
      headIndex: 5,
      spanRows: const [LayerRowAddress(_a), LaneRowAddress(_a, _position)],
    );

void main() {
  for (final fromTheLane in [false, true]) {
    test('🚨a band over a row\'s cells and its lane, stood on '
        '${fromTheLane ? 'the lane' : 'the row'}, copies BOTH — and a paste '
        'lays the block where it stands and the key on the same lane of that '
        'row, in one undo', () {
      final s = _session();
      s.standOnRow(
        fromTheLane
            ? const LaneRowAddress(_a, _position)
            : const LayerRowAddress(_a),
        frameIndex: 0,
      );
      _sweepAAndItsLane(s);
      final pill = TimelineToolbarPanelContext(s);
      expect(s.laneVerbs.laneVerbRange, isNull, reason: 'the band claims it');
      expect(pill.canCopyFrame, isTrue);
      pill.copyFrame();
      expect(s.clipboard.bankedRowLayerIds, [_a]);

      s.standOnRow(const LayerRowAddress(_a), frameIndex: 6);
      expect(s.frameRangeSelection.value, isNull, reason: '⛔전제: no band');
      final steps = s.historyManager.undoCount;
      pill.pasteIndependentFrame();

      expect(_blocksOf(_cutRow(s, _a)), {0: 3, 6: 3});
      expect(_keysOf(_cutRow(s, _a)), {
        0: (1.0, 'K'),
        6: (1.0, null),
      }, reason: '「독립 붙여넣기 = 그냥 복제」 — a value of its own');
      expect(s.historyManager.undoCount, steps + 1);
      s.undo();
      expect(_blocksOf(_cutRow(s, _a)), {0: 3});
      expect(_keysOf(_cutRow(s, _a)), {0: (1.0, 'K')});
    });
  }

  test('a copy made standing takes the comma alone — no key rides it', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 6);
    pill.pasteIndependentFrame();

    expect(_blocksOf(_cutRow(s, _a)), {0: 3, 6: 1}, reason: '⛔전제: pasted');
    expect(_keysOf(_cutRow(s, _a)), {0: (1.0, 'K')});
  });

  test('🚨a 잘라내기 of the band lifts its cells and its keys, leaving a '
      'hole, in one undo — and a paste puts both back', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweepAAndItsLane(s);
    final pill = TimelineToolbarPanelContext(s);
    expect(pill.canCutRun, isTrue);
    final steps = s.historyManager.undoCount;
    pill.cutRun();

    expect(_blocksOf(_cutRow(s, _a)), isEmpty);
    expect(_keysOf(_cutRow(s, _a)), isEmpty);
    expect(s.historyManager.undoCount, steps + 1);
    s.undo();
    expect(_blocksOf(_cutRow(s, _a)), {0: 3});
    expect(_keysOf(_cutRow(s, _a)), {0: (1.0, 'K')});
    s.redo();

    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    pill.pasteLinkedFrame();
    expect(_blocksOf(_cutRow(s, _a)), {0: 3});
    expect(_keysOf(_cutRow(s, _a)), {0: (1.0, 'K')});
  });

  test('🚨a 링크 붙여넣기 on another row keeps the key\'s name — and asks '
      'first where that row holds the name at another value; joined, the '
      'key takes what the name holds there', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweepAAndItsLane(s);
    TimelineToolbarPanelContext(s).copyFrame();
    s.standOnRow(const LayerRowAddress(_b), frameIndex: 6);
    final steps = s.historyManager.undoCount;

    final joins = s.clipboard.pasteLinkedAt(s.clipboard.timelinePlace);
    expect(joins, hasLength(1));
    expect(joins!.single.layerId, _b);
    expect(joins.single.held, isEmpty, reason: 'no drawing is called A1');
    expect(joins.single.keyNames, {'K'});
    expect(_keysOf(_cutRow(s, _b)), {10: (5.0, 'K')}, reason: 'nothing yet');
    expect(s.historyManager.undoCount, steps);

    expect(
      s.clipboard.pasteLinkedAt(
        s.clipboard.timelinePlace,
        joinTakenNames: true,
      ),
      isNull,
    );
    expect(_blocksOf(_cutRow(s, _b)), {6: 3});
    expect(_keysOf(_cutRow(s, _b)), {
      6: (5.0, 'K'),
      16: (5.0, 'K'),
    }, reason: 'the keys from there on moved back by what went in (F-388-Q1)');
    expect(s.historyManager.undoCount, steps + 1);
  });

  test('🚨on the conte, a track band over an S row and its lane, stood on '
      'the lane, copies both — and a paste lays both', () {
    final s = _session();
    s.standOnRow(
      const LaneRowAddress(_s1, _position),
      panel: WorkingPanel.storyboard,
    );
    s.updateTrackRowRangeSelectionByFrame(
      layerId: _s1,
      anchorGlobalFrame: 0,
      headGlobalFrame: 5,
      anchorRow: const LayerRowAddress(_s1),
      spanRows: const [LayerRowAddress(_s1), LaneRowAddress(_s1, _position)],
    );
    final pill = StoryboardToolbarPanelContext(s);
    expect(
      s.laneVerbs.laneVerbRange,
      isNull,
      reason: 'the track\'s band claims it as the cut\'s does',
    );
    expect(s.keyClipboard.canCopy, isFalse);
    expect(pill.canCopyFrame, isTrue);
    pill.copyFrame();
    expect(s.clipboard.bankedRowLayerIds, [_s1]);

    s.standOnRow(
      const LayerRowAddress(_s1),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 6,
    );
    pill.pasteIndependentFrame();

    expect(_blocksOf(_seRow(s)), {0: 3, 6: 3});
    expect(_keysOf(_seRow(s)), {0: (1.0, null), 6: (1.0, null)});
  });

  test('a band over two rows and their lanes, pasted over a band of the same '
      'rows, puts each row\'s keys on its own row — replacing the keys the '
      'band covers there, as it replaces the cells (결정 14 ③ⓐ)', () {
    final s = _session();
    void sweep(int from) => s.updateFrameRangeSelectionDrag(
      layerId: _a,
      anchorIndex: from,
      headIndex: from + 5,
      spanRows: const [
        LayerRowAddress(_a),
        LaneRowAddress(_a, _position),
        LayerRowAddress(_c),
        LaneRowAddress(_c, _position),
      ],
    );
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    sweep(0);
    final pill = TimelineToolbarPanelContext(s);
    pill.copyFrame();
    expect(s.clipboard.bankedRowLayerIds, [_a, _c]);

    s.standOnRow(const LayerRowAddress(_a), frameIndex: 8);
    sweep(8);
    pill.pasteIndependentFrame();

    expect(_blocksOf(_cutRow(s, _a)), {0: 3, 8: 3});
    expect(_blocksOf(_cutRow(s, _c)), {0: 3, 8: 3});
    expect(_keysOf(_cutRow(s, _a)), {0: (1.0, 'K'), 8: (1.0, null)});
    expect(_keysOf(_cutRow(s, _c)), {
      2: (7.0, null),
      10: (7.0, null),
    }, reason: 'C\'s own key at 2 put at 8 + 2, where K stood under the band');
  });

  testWidgets('the link window asks of the drawings and the keys a 링크 '
      '붙여넣기 joins on a row together — once, for the one press', (
    tester,
  ) async {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweepAAndItsLane(s);
    TimelineToolbarPanelContext(s).copyFrame();
    s.standOnRow(const LayerRowAddress(_c), frameIndex: 6);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => pasteLinkedAskingFirst(
              context,
              s,
              place: () => s.clipboard.timelinePlace,
            ),
            child: const Text('paste'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('paste'));
    await tester.pumpAndSettle();

    final window = tester.widget<FrameNameConflictDialog>(
      find.byType(FrameNameConflictDialog),
    );
    final project = s.repository.requireProject();
    expect(window.targets, [
      ...drawingPlaceLines(project, _c, const [
        FrameId('band-c-f'),
      ], framePlace: s.framePlaceLabel),
      ...rowPlaceLines(project, _c),
    ]);
    expect(window.message, AppText.strings.linkedPasteConflictBody);
  });

  testWidgets('where only a key joins, the window lists the keys\' row with '
      'their own notice', (tester) async {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_a), frameIndex: 0);
    _sweepAAndItsLane(s);
    TimelineToolbarPanelContext(s).copyFrame();
    s.standOnRow(const LayerRowAddress(_b), frameIndex: 6);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => pasteLinkedAskingFirst(
              context,
              s,
              place: () => s.clipboard.timelinePlace,
            ),
            child: const Text('paste'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('paste'));
    await tester.pumpAndSettle();

    final window = tester.widget<FrameNameConflictDialog>(
      find.byType(FrameNameConflictDialog),
    );
    expect(window.targets, rowPlaceLines(s.repository.requireProject(), _b));
    expect(window.message, isNull, reason: 'the keys\' paste says none');
  });
}
