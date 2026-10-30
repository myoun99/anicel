import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_drop_verdict.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/session/tab_rail_wiring.dart';

import '../../helpers/named_finders.dart';

/// 🚨A FILE LET GO ON THE LAYER AREA IS A NEW LAYER AT THE GAP (유저
/// 2026-09-11, 미디어 배치 라운드: 「레이어 영역(가로선) → 새 레이어」). While
/// it hovers, the rail shows its OWN caret there — the line a moved row
/// draws — and a sound raises none (round 6 sends it to the SE rows).
void main() {
  Layer row(String id, {LayerKind kind = LayerKind.animation, String? ridesOn}) =>
      Layer(
        id: LayerId(id),
        name: id,
        frames: const [],
        timeline: const {},
        kind: kind,
        attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
      );

  group('the gap a new row may take', () {
    /// What every gap of [shown] says, from its first row's side on.
    List<int?> gaps(List<Layer> stack, List<Layer> shown) => [
      for (var slot = 0; slot <= shown.length; slot += 1)
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: slot),
    ];

    test('the drawing section only — never above the camera', () {
      final a = row('A');
      final b = row('B');
      final camera = row('Cam', kind: LayerKind.camera);
      final stack = [a, b, camera];
      // The rail runs the stack top-down.
      final shown = [camera, b, a];

      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 0),
        isNull,
        reason: 'above the camera is the camera section',
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 1),
        2,
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 2),
        1,
      );
      expect(
        newRowInsertionForSlot(stack: stack, displayRows: shown, slot: 3),
        0,
      );
    });

    // 🗣️F-372 (유저 2026-10-17): 「액션란에 레이어 하나도 없을때 해당
    // 빈공간에 끌면 … 아무 반응없음. 해당영역에 넣는거 가능하게」.
    test('🚨a drawing section with no row is still a place — the one gap '
        'where it stands: the rail\'s foot, the sheet\'s head', () {
      final camera = row('Cam', kind: LayerKind.camera);
      final transition = row('Tr', kind: LayerKind.transition);
      final se1 = row('S1', kind: LayerKind.se);
      final se2 = row('S2', kind: LayerKind.se);
      // A track's rows are no rows of the cut's stack.
      final rail = [camera, transition, se2, se1];
      final sheet = [se1, se2, transition, camera];

      expect(gaps([camera], rail), [null, null, null, null, 0]);
      expect(gaps([camera], sheet), [0, null, null, null, null]);
      expect(
        gaps(const [], [transition, se2, se1]),
        [null, null, null, 0],
        reason: 'a cut with no row of its own',
      );
      expect(
        gaps(const [], [se2, se1]),
        [null, null, null],
        reason: 'one section cannot say which way the list runs',
      );
      expect(gaps(const [], const []), [null], reason: 'nor can no row');
    });

    // 🗣️F-372 ② (검증 2026-10-23): a picture held on the rail's line
    // between the cut's Direction row and the track's SE rows raised the
    // caret, and let go there it became ACTION's top row — under them.
    test('🚨beside a track\'s rows a line is a gap only on the side the row '
        'is drawn: under the SE rows, never over them', () {
      final a = row('A');
      final b = row('B');
      final direction = row('D1', kind: LayerKind.instruction);
      final camera = row('Cam', kind: LayerKind.camera);
      final stack = [a, b, direction, camera];
      // The film the timeline composes: the cut's rows and the track's.
      final film = [
        ...stack,
        row('Tr', kind: LayerKind.transition),
        row('S1', kind: LayerKind.se),
        row('S2', kind: LayerKind.se),
      ];
      final rail = horizontalLayerDisplayOrder(film);
      expect(
        [for (final shown in rail) shown.name],
        ['Cam', 'Tr', 'D1', 'S2', 'S1', 'B', 'A'],
        reason: 'CONTROL: the SE rows stand between the camera and ACTION',
      );

      expect(gaps(stack, rail), [null, null, null, null, null, 2, 1, 0]);
      expect(
        gaps(stack, xsheetLayerDisplayOrder(film)),
        [0, 1, 2, null, null, null, null, null],
        reason: 'the sheet runs the film the other way: A B S1 S2 D1 Tr Cam',
      );
    });

    test('never between a base and its rider', () {
      final base = row('Base');
      final rider = row('Rider', ridesOn: 'Base');

      expect(
        newRowInsertionForSlot(
          stack: [base, rider],
          displayRows: [rider, base],
          slot: 1,
        ),
        isNull,
      );
    });
  });

  EditorSessionManager twoRows() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('gap-project'),
        name: 'Gap Project',
        createdAt: DateTime.utc(2026, 9, 12),
        tracks: [
          Track(
            id: const TrackId('gap-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('gap-cut'),
                name: 'Gap Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [row('A'), row('B')],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  const png = r'C:\art\bg.png';
  const dragSourceKey = ValueKey<String>('test-media-drag-source');

  /// [session]'s timeline under a picture's drag source, with the chip's
  /// answer heard in [verdict] when one is given.
  Future<void> pumpUnderAPicture(
    WidgetTester tester,
    EditorSessionManager session, {
    TimelineOrientation orientation = TimelineOrientation.horizontal,
    ValueNotifier<bool?>? verdict,
    void Function(List<Layer> layers, int slot, String path)? onPlace,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final body = Column(
      children: [
        SizedBox(
          height: 40,
          child: Draggable<MediaAssetDragData>(
            data: const MediaAssetDragData(path: png, name: 'bg.png'),
            // The pool row's own anchor: a target reads the pointer.
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: const SizedBox(width: 8, height: 8),
            child: Container(
              key: dragSourceKey,
              width: 40,
              height: 40,
              color: const Color(0xFF888888),
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              rail: TabRailWiring.of(session),
              orientation: orientation,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 48,
              onPixelsPerFrameChanged: (_) {},
              rulerView: FrameRulerView.frames,
              onRulerViewChanged: (_) {},
              onPlaceMediaAssetBetweenLayers: onPlace ?? (_, _, _) {},
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: verdict == null
              ? body
              : MediaDropVerdictScope(verdict: verdict, child: body),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the caret and the spot', () {
    testWidgets('a picture raises the placement caret at a legal gap; a '
        'sound raises none', (tester) async {
      final s = twoRows();
      final shown = [row('B'), row('A')];

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'bg.png');
      expect(
        s.layerRowDragVerbs.inFlight.value?.subject,
        const MediaPlacementSubject(),
      );
      expect(s.layerRowDragVerbs.inFlight.value?.caretSlot, 1);

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'door.wav');
      expect(s.layerRowDragVerbs.inFlight.value, isNull);

      s.layerRowDragVerbs.showPlacementCaret(shown, 1, 'bg.png');
      s.layerRowDragVerbs.showPlacementCaret(shown, 5, 'bg.png');
      expect(
        s.layerRowDragVerbs.inFlight.value,
        isNull,
        reason: 'a gap that names no place takes the line away',
      );
    });

    testWidgets('clearing the placement caret leaves a row drag\'s alone', (
      tester,
    ) async {
      final s = twoRows();
      const moving = LayerRowDragState(
        subject: LayerRowSubject(LayerId('A')),
        caretSlot: 0,
        legal: true,
      );
      s.layerRowDragVerbs.inFlight.value = moving;

      s.layerRowDragVerbs.clearPlacementCaret();

      expect(s.layerRowDragVerbs.inFlight.value, same(moving));
    });

    testWidgets('the spot: a new layer at that gap for a picture, the SE '
        'rule for a sound', (tester) async {
      final s = twoRows();
      final shown = [row('B'), row('A')];

      expect(s.layerSlotSpotFor(shown, 1, 'bg.png'), const LayerSlotSpot(1));
      expect(s.layerSlotSpotFor(shown, 0, 'bg.png'), const LayerSlotSpot(2));
      expect(
        s.layerSlotSpotFor(shown, 1, 'door.wav'),
        const AboveActiveLayerSpot(),
      );
    });
  });

  testWidgets('a picture held over the layer area raises the rail\'s own '
      'caret at the gap under the pointer — and letting go reports that gap '
      'and takes the caret away', (tester) async {
    (List<LayerId>, int, String)? placed;
    final s = twoRows();
    await pumpUnderAPicture(
      tester,
      s,
      onPlace: (layers, slot, path) =>
          placed = ([for (final layer in layers) layer.id], slot, path),
    );

    // Just inside A's rail row: the nearest gap is its top edge, between B
    // above it and A.
    const a = LayerId('A');
    final railRowA = find.named('timeline-rail-row-$a-row');
    expect(railRowA, findsOneWidget);
    final at = tester.getTopLeft(railRowA) + const Offset(24, 3);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-A')),
      findsOneWidget,
      reason: 'the line a moved row draws, on A\'s top edge',
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('timeline-layer-placement-entrance'),
        ),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
      reason: 'the caret is the answer — the entrance lights no border',
    );

    // A's bottom edge is the strip's end: the trailing gap, drawn under A.
    await gesture.moveTo(
      tester.getBottomLeft(railRowA) + const Offset(24, -3),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-after-A')),
      findsOneWidget,
    );
    await gesture.moveTo(at);
    await tester.pump();

    await gesture.up();
    await tester.pumpAndSettle();

    final (layers, slot, path) = placed!;
    expect(path, png);
    expect(layers[slot], a);
    expect(layers[slot - 1], const LayerId('B'));
    expect(s.layerRowDragVerbs.inFlight.value, isNull);
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-A')),
      findsNothing,
    );
  });

  // 🗣️F-372 (유저 2026-10-17): 「액션란에 레이어 하나도 없을때 해당 빈공간에
  // 끌면 금지마크도 안떠서 가능한건가싶은데 이미지 그립한거 드롭해도 아무
  // 반응없음. 해당영역에 넣는거 가능하게」.
  testWidgets('🚨with no ACTION row, a picture let go in the room under the '
      'rail\'s rows — where ACTION stands — says yes, raises the caret there '
      'and is a new layer at the foot of the stack', (tester) async {
    final verdict = ValueNotifier<bool?>(null);
    addTearDown(verdict.dispose);
    (List<Layer>, int, String)? placed;
    final base = createDefaultProject();
    final s = EditorSessionManager(
      initialProject: base.copyWith(
        tracks: [
          for (final track in base.tracks)
            track.copyWith(
              cuts: [
                for (final cut in track.cuts)
                  cut.copyWith(
                    layers: [
                      for (final layer in cut.layers)
                        if (timelineSectionForLayerKind(layer.kind) !=
                            TimelineSection.drawing)
                          layer,
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
    addTearDown(s.dispose);
    expect(s.requireActiveCut.layers, isNotEmpty, reason: 'CONTROL: a camera');
    await pumpUnderAPicture(
      tester,
      s,
      verdict: verdict,
      onPlace: (layers, slot, path) => placed = (layers, slot, path),
    );

    final foot = tester
        .getRect(
          find.namedWhere((name) => name.startsWith('timeline-rail-row-')).last,
        )
        .bottom;
    final rail = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-placement-entrance')),
    );
    final room = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-placement-room')),
    );
    expect(
      (rail.bottom, room.left, room.top, room.right),
      (foot, rail.left, foot, rail.right),
      reason: '⛔D43-2: the rows stop where they end — the room under them '
          'is an entrance of its own, the rail\'s width',
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Right under the last row and well below it: anywhere in the room is
    // past the rows, the foot.
    final carets = <int?>[];
    for (final below in [2.0, 120.0]) {
      await gesture.moveTo(Offset(rail.left + 40, foot + below));
      await tester.pump();
      expect(verdict.value, isTrue, reason: 'the chip says yes $below under');
      carets.add(s.layerRowDragVerbs.inFlight.value?.caretSlot);
    }

    await gesture.up();
    await tester.pumpAndSettle();

    final (layers, slot, path) = placed!;
    expect(path, png);
    expect(slot, layers.length, reason: 'the gap under the last row');
    expect(carets, [slot, slot], reason: 'the caret stood where it lands');
    expect(s.layerSlotSpotFor(layers, slot, png), const LayerSlotSpot(0));
  });

  // 🗣️F-372 ② (검증 2026-10-23, 실제 마우스): 「카메라 · SE 사이(Direction 1
  // 과 S2 의 경계)에서 칩에 금지 표시가 없고 캐럿이 선다 … 놓으면 배치 창이
  // 뜨고 ACTION 맨 위에 새 레이어가 생긴다」 — with ACTION holding a row.
  testWidgets('🚨the line between the Direction row and the track\'s SE rows '
      'takes no picture: the chip says no, no caret stands, and letting go '
      'there does nothing — ACTION\'s top is the line under the SE rows', (
    tester,
  ) async {
    final verdict = ValueNotifier<bool?>(null);
    addTearDown(verdict.dispose);
    var placed = 0;
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await pumpUnderAPicture(
      tester,
      s,
      verdict: verdict,
      onPlace: (_, _, _) => placed += 1,
    );

    Rect railRowOf(Layer layer) =>
        tester.getRect(find.named('timeline-rail-row-${layer.id}-row'));
    final direction = railRowOf(
      s.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.instruction,
      ),
    );
    final seRows = [
      for (final layer in s.activeTrack.seLayers) railRowOf(layer),
    ].reduce((a, b) => a.expandToInclude(b));
    expect(
      (direction.bottom, s.requireActiveCut.layers.first.kind),
      (seRows.top, LayerKind.animation),
      reason: 'CONTROL: the SE rows stand right under the Direction row, '
          'and ACTION holds a row',
    );

    // Above and below the line, as the four points were; then just under
    // the SE rows.
    final answers = <(bool?, int?)>[];
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (final y in [
      for (final off in [-6.0, -2.0, 2.0, 6.0]) seRows.top + off,
      seRows.bottom + 2,
    ]) {
      await gesture.moveTo(Offset(direction.left + 40, y));
      await tester.pump();
      answers.add((
        verdict.value,
        s.layerRowDragVerbs.inFlight.value?.caretSlot,
      ));
    }
    final underTheSeRows = answers.removeLast();
    expect(answers, everyElement((false, null)));
    expect(underTheSeRows.$1, isTrue, reason: 'CONTROL: ACTION\'s top');

    await gesture.moveTo(Offset(direction.left + 40, seRows.top + 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placed, 0, reason: 'impossible means nothing happens');
  });

  testWidgets('a body its rows overfill has no room under them — the rows '
      'are all the layer area there is', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('full-project'),
        name: 'Full Project',
        createdAt: DateTime.utc(2026, 10, 17),
        tracks: [
          Track(
            id: const TrackId('full-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('full-cut'),
                name: 'Full Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  for (var index = 0; index < 40; index += 1) row('L$index'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
            session: s,
            rail: TabRailWiring.of(s),
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: 48,
            onPixelsPerFrameChanged: (_) {},
            rulerView: FrameRulerView.frames,
            onRulerViewChanged: (_) {},
            onPlaceMediaAssetBetweenLayers: (_, _, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rows = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-placement-entrance')),
    );
    final body = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
    );
    expect(rows.height, greaterThan(body.height), reason: 'CONTROL');
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-placement-room')),
      findsNothing,
    );
  });

  testWidgets('a picture that wanders off the layer area takes its caret '
      'with it', (tester) async {
    final s = twoRows();
    await pumpUnderAPicture(tester, s);

    final railRowA = find.named('timeline-rail-row-${const LayerId('A')}-row');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getTopLeft(railRowA) + const Offset(24, 3));
    await tester.pump();
    expect(s.layerRowDragVerbs.inFlight.value, isNotNull);

    await gesture.moveTo(tester.getCenter(find.byKey(dragSourceKey)));
    await tester.pump();

    expect(s.layerRowDragVerbs.inFlight.value, isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the sheet\'s header strip is the same entrance turned on its '
      'side — the gap runs along x', (tester) async {
    (List<LayerId>, int, String)? placed;
    final s = twoRows();
    await pumpUnderAPicture(
      tester,
      s,
      orientation: TimelineOrientation.vertical,
      onPlace: (layers, slot, path) =>
          placed = ([for (final layer in layers) layer.id], slot, path),
    );

    final entrance = find.byKey(
      const ValueKey<String>('xsheet-layer-placement-entrance'),
    );
    expect(entrance, findsOneWidget);
    // The sheet lists the stack raw, left to right: A, then B — so one
    // column in is the edge between them.
    final strip = tester.getRect(entrance);
    final at = Offset(strip.left + timelineLayerRowHeight + 2, strip.center.dy);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-B')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    final (layers, slot, path) = placed!;
    expect(path, png);
    expect(layers[slot], const LayerId('B'));
    expect(layers[slot - 1], const LayerId('A'));
  });
}
