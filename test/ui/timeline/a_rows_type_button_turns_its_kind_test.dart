import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-613 (유저 2026-11-19): 「레이어영역의 레이어의 아이콘 누르면 변경가능한
/// 대상 뜨고 변경가능하게. 우선 액션란의 이미지-애니메이션-콘티 이 세가지
/// 타입」 — the row's TYPE BUTTON opens the kinds it turns between, and a
/// pick turns it as the rail's buttons act: the selected rows when pressed
/// among them, in one step.
void main() {
  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    List<String> cels = const [],
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [
      for (final cel in cels)
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final (at, cel) in cels.indexed)
        at * 2: TimelineExposure.drawing(FrameId(cel), length: 2),
    },
  );

  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<Layer> layers, {
    TimelineOrientation orientation = TimelineOrientation.horizontal,
  }) => pumpTimelineHost(
    tester,
    Project(
      id: const ProjectId('p'),
      name: 'p',
      createdAt: DateTime.utc(2026, 11, 19),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: 'c',
              duration: 8,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: layers,
            ),
          ],
        ),
      ],
    ),
    orientation: orientation,
  );

  /// The layer [id], in whichever cut holds it.
  Layer layerOf(EditorSessionManager session, String id) => [
    for (final track in session.repository.requireProject().tracks)
      for (final cut in track.cuts) ...cut.layers,
  ].firstWhere((layer) => layer.id == LayerId(id));

  LayerKind kindOf(EditorSessionManager session, String id) =>
      layerOf(session, id).kind;

  Future<void> openList(WidgetTester tester, String id) async {
    final button = find.named('timeline-layer-type-button-$id');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Finder itemFinder(String id, LayerKind kind) =>
      find.byKey(ValueKey<String>('timeline-layer-kind-${kind.name}-$id'));

  PopupMenuItem<PanelFlyoutItem> item(
    WidgetTester tester,
    String id,
    LayerKind kind,
  ) => tester.widget(itemFinder(id, kind));

  Future<void> pick(WidgetTester tester, String id, LayerKind kind) async {
    await openList(tester, id);
    await tester.tap(itemFinder(id, kind));
    await tester.pumpAndSettle();
  }

  testWidgets('a picture row\'s type button opens the three kinds, its own '
      'the current one, and leaves the selection where it was', (
    tester,
  ) async {
    final session = await open(tester, [
      row('b', cels: ['b1']),
      row('a', cels: ['a1']),
    ]);
    session.rowSelection.value = [const LayerRowAddress(LayerId('b'))];
    await tester.pump();

    await openList(tester, 'a');

    for (final kind in const [
      LayerKind.image,
      LayerKind.animation,
      LayerKind.storyboard,
    ]) {
      expect(
        item(tester, 'a', kind).value!.selected,
        kind == LayerKind.animation,
        reason: '$kind',
      );
      expect(item(tester, 'a', kind).enabled, isTrue, reason: '$kind');
    }
    expect(
      session.rowSelection.value,
      [const LayerRowAddress(LayerId('b'))],
      reason: 'the press is the list\'s — it selects nothing',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(kindOf(session, 'a'), LayerKind.animation);
  });

  testWidgets('a pick turns the row, and one undo turns it back', (
    tester,
  ) async {
    final session = await open(tester, [
      row('a', cels: ['a1']),
    ]);
    final steps = session.historyManager.undoCount;

    await pick(tester, 'a', LayerKind.animation);
    expect(
      session.historyManager.undoCount,
      steps,
      reason: 'the kind it is: nothing to do, no step to undo',
    );

    await pick(tester, 'a', LayerKind.image);
    expect(kindOf(session, 'a'), LayerKind.image);
    expect(session.historyManager.undoCount, steps + 1);

    await openList(tester, 'a');
    expect(
      item(tester, 'a', LayerKind.image).value!.selected,
      isTrue,
      reason: 'the list reads the row as it is now',
    );
    await tester.tap(itemFinder('a', LayerKind.storyboard));
    await tester.pumpAndSettle();
    expect(kindOf(session, 'a'), LayerKind.storyboard);

    session.undo();
    await tester.pumpAndSettle();
    expect(kindOf(session, 'a'), LayerKind.image);
    session.undo();
    await tester.pumpAndSettle();
    expect(kindOf(session, 'a'), LayerKind.animation);
  });

  testWidgets('a kind the row cannot take is shown and shut — the cut\'s '
      'second conte, an image of two cels', (tester) async {
    final session = await open(tester, [
      row('conte', kind: LayerKind.storyboard, cels: ['k1']),
      row('two', cels: ['t1', 't2']),
    ]);

    await openList(tester, 'two');
    expect(item(tester, 'two', LayerKind.image).enabled, isFalse);
    expect(item(tester, 'two', LayerKind.storyboard).enabled, isFalse);
    expect(item(tester, 'two', LayerKind.animation).enabled, isTrue);

    await tester.tap(itemFinder('two', LayerKind.image), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(kindOf(session, 'two'), LayerKind.animation);
  });

  testWidgets('pressed among the selected rows, a pick turns each that can '
      'take it in ONE step; pressed outside them, only its own', (
    tester,
  ) async {
    final session = await open(tester, [
      row('c', cels: ['c1']),
      row('two', cels: ['t1', 't2']),
      row('b', cels: ['b1']),
      row('a', cels: ['a1']),
    ]);
    session.rowSelection.value = const [
      LayerRowAddress(LayerId('a')),
      LayerRowAddress(LayerId('b')),
      LayerRowAddress(LayerId('two')),
    ];
    await tester.pump();
    final steps = session.historyManager.undoCount;

    await pick(tester, 'a', LayerKind.image);
    expect(
      [for (final id in const ['a', 'b', 'two', 'c']) kindOf(session, id)],
      [
        LayerKind.image,
        LayerKind.image,
        LayerKind.animation,
        LayerKind.animation,
      ],
      reason: 'a row that cannot hold the kind stays as it was',
    );
    expect(session.historyManager.undoCount, steps + 1);

    session.undo();
    await tester.pumpAndSettle();
    expect(
      [for (final id in const ['a', 'b']) kindOf(session, id)],
      [LayerKind.animation, LayerKind.animation],
    );

    session.rowSelection.value = const [
      LayerRowAddress(LayerId('a')),
      LayerRowAddress(LayerId('b')),
    ];
    await tester.pump();
    await pick(tester, 'c', LayerKind.image);
    expect(
      [for (final id in const ['a', 'b', 'c']) kindOf(session, id)],
      [LayerKind.animation, LayerKind.animation, LayerKind.image],
    );
  });

  testWidgets('the x-sheet\'s column head opens the same list and picks the '
      'same way', (tester) async {
    final session = await open(
      tester,
      [
        row('a', cels: ['a1']),
      ],
      orientation: TimelineOrientation.vertical,
    );
    final head = find.named('xsheet-layer-type-button-a');
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
    final image = find.byKey(
      const ValueKey<String>('xsheet-layer-kind-image-a'),
    );
    expect(image, findsOneWidget);
    await tester.tap(image);
    await tester.pumpAndSettle();
    expect(kindOf(session, 'a'), LayerKind.image);
  });

  testWidgets('a row of another kind keeps the press it had: it opens no '
      'list', (tester) async {
    await open(tester, [
      row('a', cels: ['a1']),
      row('f', kind: LayerKind.folder),
    ]);

    await openList(tester, 'f');
    for (final kind in LayerKind.values) {
      expect(itemFinder('f', kind), findsNothing, reason: '$kind');
    }
  });

  testWidgets('the conte rail\'s row counts the selection for its kind list '
      'as its eye counts it', (tester) async {
    final session = await pumpStoryboardHost(
      tester,
      Project(
        id: const ProjectId('p'),
        name: 'p',
        createdAt: DateTime.utc(2026, 11, 19),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: 'c',
                duration: 8,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  row('a', cels: ['a1']),
                  row('conte', kind: LayerKind.storyboard, cels: ['k1']),
                ],
              ),
            ],
          ),
        ],
      ),
      surface: const Size(1600, 900),
      pixelsPerFrame: 12,
    );
    // The timeline's rows, the conte among them: whether a press on the
    // conte rail's row is a press inside them is the rail's own law — the
    // list keeps the one its eye keeps.
    void selectBoth() => session.rowSelection.value = const [
      LayerRowAddress(LayerId('conte')),
      LayerRowAddress(LayerId('a')),
    ];
    selectBoth();
    await tester.pump();
    final eye = find.named('storyboard-layer-visibility-conte');
    await tester.ensureVisible(eye);
    await tester.pumpAndSettle();
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(layerOf(session, 'conte').isVisible, isFalse, reason: '⛔premise');
    final eyeReachedTheOther = !layerOf(session, 'a').isVisible;

    selectBoth();
    await tester.pump();
    await tester.tap(find.named('storyboard-layer-type-button-conte'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-layer-kind-image-conte')),
    );
    await tester.pumpAndSettle();
    expect(kindOf(session, 'conte'), LayerKind.image);
    expect(
      kindOf(session, 'a') == LayerKind.image,
      eyeReachedTheOther,
      reason: 'the list reached the other row as the eye did',
    );
  });

  // cut-1 holds the track's conte and cut-2 none: stood in cut-2, the
  // rail's conte row still holds cut-1's, and a pick is written THERE.
  for (final standing in const ['cut-1', 'cut-2']) {
    testWidgets('the conte rail\'s conte row opens the same list, asked of '
        'the conte it holds in hand — stood in $standing', (tester) async {
      final session = await pumpStoryboardHost(
        tester,
        conteTrackProject(),
        surface: const Size(1600, 900),
        pixelsPerFrame: 12,
      );
      session.selectCut(CutId(standing));
      await tester.pumpAndSettle();
      expect(session.activeCutId, CutId(standing), reason: '⛔premise');
      const conte = 'cut-1-conte';
      Finder conteItem(LayerKind kind) => find.byKey(
        ValueKey<String>('storyboard-layer-kind-${kind.name}-$conte'),
      );
      // The row of the track's seat ([trackConteRowId]) wears the conte it
      // holds in hand — its type button is named by the conte.
      final head = find.named('storyboard-layer-type-button-$conte');
      await tester.ensureVisible(head);
      await tester.pumpAndSettle();
      await tester.tap(head);
      await tester.pumpAndSettle();

      PopupMenuItem<PanelFlyoutItem> at(LayerKind kind) =>
          tester.widget(conteItem(kind));
      expect(at(LayerKind.storyboard).value!.selected, isTrue);
      expect(
        at(LayerKind.animation).enabled,
        isTrue,
        reason: "the row is the track's seat, no layer — the list asks of the "
            'conte it holds',
      );
      expect(
        at(LayerKind.image).enabled,
        isFalse,
        reason: 'three panels are three cels',
      );

      await tester.tap(conteItem(LayerKind.animation));
      await tester.pumpAndSettle();
      expect(kindOf(session, conte), LayerKind.animation);
    });
  }
}
