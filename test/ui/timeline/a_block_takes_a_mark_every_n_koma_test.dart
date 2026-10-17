import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/run_edge_fixtures.dart';

/// 🗣️I-58 (유저 2026-10-01): 「중간나누기 마크 자동추가. 대상은 중간나누기
/// 마크가 적용가능한 행의 선택된블록들or현재 인덱스 블록, 각자 현재 블록
/// 안에서 블록이 끝날때까지, n코마마다 중간나누기 마크 추가 … 3적고
/// 확인누르면 현재 블록에서 헤더부터 시작해서 3코마마다 점 찍음. 즉
/// 1--------- 이렇게있으면, 1--.--.--.」
void main() {
  const idA = LayerId('every-a');
  const idB = LayerId('every-b');
  const idC = LayerId('every-c');

  Frame cel(String id, int duration) =>
      Frame(id: FrameId(id), duration: duration, strokes: const []);

  /// A: ONE block ten frames long — the user's `1---------`. B: a block of
  /// four, a block of six that holds, and the hold's ghost to the cut's
  /// end. C: a single frame.
  Project project() => Project(
    id: const ProjectId('mark-every'),
    name: 'Every',
    createdAt: DateTime.utc(2026, 10, 18),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: '1',
            duration: 16,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: idA,
                name: 'A',
                kind: LayerKind.animation,
                frames: [cel('a1', 10)],
                timeline: {
                  0: const TimelineExposure.drawing(
                    FrameId('a1'),
                    length: 10,
                  ),
                },
              ),
              Layer(
                id: idB,
                name: 'B',
                kind: LayerKind.animation,
                frames: [cel('b1', 4), cel('b2', 6)],
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('b1'), length: 4),
                  4: const TimelineExposure.drawing(
                    FrameId('b2'),
                    length: 6,
                    endEdge: holdMark,
                  ),
                  10: const TimelineExposure.drawing(
                    FrameId('b2'),
                    length: 6,
                    ghostOf: endHoldGhost,
                  ),
                },
              ),
              Layer(
                id: idC,
                name: 'C',
                kind: LayerKind.animation,
                frames: [cel('c1', 1)],
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('c1'), length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager rig() {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    return session;
  }

  /// The marks of [id]'s entry at [start], as offsets from its head.
  List<int> marksAt(EditorSessionManager session, LayerId id, int start) {
    final layer = session.layers.firstWhere((l) => l.id == id);
    return [...?layer.timeline[start]?.breakdownOffsets]..sort();
  }

  void sweep(
    EditorSessionManager session,
    List<LayerId> ids, {
    required int from,
    required int toExclusive,
  }) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: ids.first,
      startIndex: from,
      endIndexExclusive: toExclusive,
      layerIds: ids,
    );
  }

  void standOn(EditorSessionManager session, LayerId id, int frame) {
    session.selectLayer(id);
    session.selectFrameIndex(frame);
    session.clearFrameRangeSelection();
  }

  test('the fixture holds what the pins below read (presence first)', () {
    final session = rig();
    final b = session.layers.firstWhere((l) => l.id == idB);
    expect(b.timeline[10]?.ghost, isTrue, reason: 'the hold\'s ghost');
    expect(b.timeline[10]?.length, 6);
    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('「1--------- 이렇게있으면, 1--.--.--.」: 3 dots the block under the '
      'playhead from its HEAD, wherever in it the playhead stands', () {
    final session = rig();
    standOn(session, idA, 7);

    expect(session.layerMarks.canMarkEvery, isTrue);
    session.layerMarks.markEvery(3);

    expect(marksAt(session, idA, 0), [3, 6, 9]);
    expect(
      [marksAt(session, idB, 0), marksAt(session, idB, 4)],
      everyElement(isEmpty),
      reason: 'no band: the block under the playhead, and only it',
    );
  });

  test('it ADDS: a mark the block already carries stays', () {
    final session = rig();
    standOn(session, idA, 4);
    session.layerMarks.toggleMarkAtCurrentFrame();
    expect(marksAt(session, idA, 0), [4], reason: 'premise');

    session.layerMarks.markEvery(3);

    expect(marksAt(session, idA, 0), [3, 4, 6, 9]);
  });

  test('「선택된블록들」: every block the band takes, each from its OWN head',
      () {
    final session = rig();
    standOn(session, idA, 0);
    sweep(session, [idA, idB], from: 0, toExclusive: 10);

    session.layerMarks.markEvery(3);

    expect(marksAt(session, idA, 0), [3, 6, 9]);
    expect(marksAt(session, idB, 0), [3]);
    expect(
      marksAt(session, idB, 4),
      [3],
      reason: 'frame 7, three past ITS head — not frames 6 and 9, three '
          'apart from where the band starts',
    );
  });

  test('one press is ONE undo', () {
    final session = rig();
    sweep(session, [idA, idB], from: 0, toExclusive: 10);
    session.layerMarks.markEvery(3);
    expect(marksAt(session, idB, 4), [3], reason: 'premise');

    session.undo();

    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('a band that takes no block is a NO-OP, never a redirect onto the '
      'active row', () {
    final session = rig();
    standOn(session, idA, 5);
    // Inside B's first block, past its head: no block STARTS in the band.
    sweep(session, [idB], from: 1, toExclusive: 3);

    expect(session.layerMarks.canMarkEvery, isFalse);
    session.layerMarks.markEvery(3);
    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('nothing to dot stays dark and lands no undo step: a hold\'s ghost '
      'is no block, a single frame has no cell past its head', () {
    final session = rig();
    standOn(session, idB, 12);
    expect(session.layerMarks.canMarkEvery, isFalse, reason: 'the ghost');

    standOn(session, idC, 0);
    expect(session.layerMarks.canMarkEvery, isFalse, reason: 'one frame');

    standOn(session, idA, 0);
    final undoBefore = session.canUndo;
    session.layerMarks.markEvery(10);
    expect(marksAt(session, idA, 0), isEmpty, reason: '10 is past the end');
    expect(session.canUndo, undoBefore);
  });

  // 🗣️I-58-Q1 (유저 2026-10-18): 「토글은 지금 자리, 새 버튼만 ● 오른쪽」.
  testWidgets('the button stands right after the ●, and its window takes '
      'the count the way every count of frames is typed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    final pill = find.descendant(
      of: find.byType(TimelineActionToolbar),
      matching: find.byKey(
        const ValueKey<String>('timeline-toolbar-frame-group'),
      ),
    );
    final order = [
      for (final button in tester.widgetList<AppIconButton>(
        find.descendant(of: pill, matching: find.byType(AppIconButton)),
      ))
        button.keyValue,
    ];
    expect(
      order.indexOf('mark-every-button'),
      order.indexOf('toggle-mark-button') + 1,
      reason: '● 바로 오른쪽 — and the toggle keeps its place before the ●: '
          '$order',
    );
    expect(
      order.indexOf('auto-frame-toggle-button'),
      order.indexOf('toggle-mark-button') - 1,
    );

    standOn(session, idA, 7);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: pill,
        matching: find.byWidgetPredicate(
          (w) => w is AppIconButton && w.keyValue == 'mark-every-button',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final window = find.byKey(const ValueKey<String>('mark-every-dialog'));
    expect(window, findsOneWidget);
    expect(
      find.descendant(
        of: window,
        matching: find.text('Auto-add In-between Marks'),
      ),
      findsOneWidget,
      reason: 'the window is called what its button is',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mark-every-field')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey<String>('mark-every-apply')));
    await tester.pumpAndSettle();

    expect(window, findsNothing);
    expect(marksAt(session, idA, 0), [3, 6, 9]);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
