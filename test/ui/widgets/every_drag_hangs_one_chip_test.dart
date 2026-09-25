import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show TimelineRowDragHooks;
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/drag_chip.dart';

/// I-39 (유저 2026-09-17): 「무언가를 드래그할때 커서에 생기는 그립ui,
/// 공용화가 안되있는거같음. 패널탭띠 … 풀에서 드래그하는거랑 ui가 미묘한게
/// 다른게 보여서 … 우선 레이어 선택범위로 선택/드래그할때 사용 … 레이어는
/// 여러개 선택해서 이동하기도하니 그립ui 여러개 대응하도록 개편」.
///
/// Driven the way a hand does it, in the whole app: the chip is ONE widget
/// for every drag that does not show its subject live, hung the same way —
/// its top-left on the pointer — and a layer drag names every row it
/// carries.
void main() {
  const pooled = 'C:/art/bg.png';

  Project project() => Project(
    id: const ProjectId('chip-project'),
    name: 'Chip Project',
    createdAt: DateTime.utc(2026, 9, 24),
    mediaAssets: [
      MediaAsset(path: pooled, name: 'bg', kind: MediaAssetKind.image),
    ],
    tracks: [
      Track(
        id: const TrackId('chip-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('chip-cut'),
            name: 'Chip Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              // Model order, bottom → top: the rail draws Camera, C, B, A.
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('b'), name: 'B', frames: const []),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
              // A row that cannot be moved, only lifted (F-16-Q1).
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project())));
    await tester.pumpAndSettle();
    // Room for the rail's rows, as the row drag's own suite makes it.
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// A rail row where a hand takes it: its name. ⛔Not the row's centre — a
  /// drawing row's centre is its fill-reference button since the opacity
  /// column widened (text-scale-rail-opac, 유저 2026-09-25), and a drag that
  /// starts on a control is the control's.
  Finder railRow(String id) =>
      find.byKey(ValueKey<String>('timeline-layer-name-$id'));

  List<String> chipLabels(WidgetTester tester) => [
    for (final item in tester.widget<DragChip>(find.byType(DragChip)).items)
      item.label,
  ];

  /// B and A as one row selection: the first drag SELECTS (⑨), one row down
  /// from B, sideways enough to clear the slop.
  Future<void> selectBAndA(WidgetTester tester) async {
    await tester.ensureVisible(railRow('a'));
    await tester.pumpAndSettle();
    final pitch = tester.getCenter(railRow('a')).dy -
        tester.getCenter(railRow('b')).dy;
    await tester.dragFrom(
      tester.getCenter(railRow('b')),
      Offset(30, pitch),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a picked-up layer selection hangs one chip per layer it '
      'carries at the pointer, follows the pointer, and goes with the '
      'release', (tester) async {
    final session = await pumpApp(tester);
    await selectBAndA(tester);
    expect(
      [
        for (final id in ['a', 'b', 'c'])
          if (session.rowIsSelected(LayerRowAddress(LayerId(id)))) id,
      ],
      ['a', 'b'],
      reason: 'premise: B and A are the selection',
    );
    expect(find.byType(DragChip), findsNothing);

    final grab = tester.getCenter(railRow('a'));
    final gesture = await tester.startGesture(
      grab,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -12));
    await tester.pump();
    expect(
      chipLabels(tester),
      ['B', 'A'],
      reason: '「그립ui 여러개」 — every row the move carries, as the rail '
          'draws them',
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('drag-chips'))),
      grab + const Offset(0, -12),
      reason: 'hung where every drag hangs its chip: top-left on the pointer',
    );

    // 📏「하는동안 패널 리빌드 해버린다거나」: a step that moves the pointer
    // and not the caret rebuilds the chip's place, and no panel.
    final rebuilt = <Type>{};
    debugOnRebuildDirtyWidget = (element, _) =>
        rebuilt.add(element.widget.runtimeType);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(
      rebuilt,
      contains(ValueListenableBuilder<Offset>),
      reason: 'premise: the step was measured — the chip moved',
    );
    expect(
      rebuilt.intersection({
        HomePage,
        EditorWorkspace,
        TimelineTabHost,
        TimelinePanel,
        LayerTimelineGrid,
      }),
      isEmpty,
      reason: 'the chip rides a notifier of its own; the panel stays put',
    );

    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('drag-chips'))),
      grab + const Offset(40, -32),
      reason: 'it follows the pointer',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(DragChip), findsNothing, reason: 'put down with it');
  });

  testWidgets('a row pressed OUTSIDE the selection carries itself alone — '
      'and a drag that only selects carries nothing', (tester) async {
    await pumpApp(tester);
    await selectBAndA(tester);

    // C is outside the selection: this drag SELECTS, so nothing is in hand.
    final gesture = await tester.startGesture(
      tester.getCenter(railRow('c')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(find.byType(DragChip), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();

    // Now C alone is selected; picked up, it names itself and no other.
    final move = await tester.startGesture(
      tester.getCenter(railRow('c')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await move.moveBy(const Offset(0, 12));
    await tester.pump();
    expect(chipLabels(tester), ['C']);
    await move.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a pool file, a panel tab and a layer row wear the SAME chip, '
      'hung the same way', (tester) async {
    await pumpApp(tester);

    Future<void> expectChipAtPointer(
      Finder source,
      Offset nudge,
      String what,
    ) async {
      await tester.ensureVisible(source);
      await tester.pumpAndSettle();
      final start = tester.getCenter(source);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(nudge);
      await tester.pump();
      expect(find.byType(DragChip), findsOneWidget, reason: '$what: the chip');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('drag-chips'))),
        start + nudge,
        reason: '$what: its top-left on the pointer',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // The pool ships closed, one rail button away.
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 3)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectChipAtPointer(
      find.byKey(const ValueKey<String>('media-asset-row-$pooled')),
      const Offset(-40, 0),
      'the pool file',
    );

    final tab = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value == 'panel-tab-media';
        })
        .first;
    await expectChipAtPointer(
      find.descendant(
        of: tab,
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('panel-grip-');
        }),
      ),
      const Offset(30, 0),
      'the panel tab',
    );

    // The row drag's MOVE starts inside a selection: select C first.
    await tester.ensureVisible(railRow('c'));
    await tester.pumpAndSettle();
    await tester.dragFrom(tester.getCenter(railRow('c')), const Offset(30, 0));
    await tester.pumpAndSettle();
    await expectChipAtPointer(railRow('c'), const Offset(0, 12), 'the row');
  });

  /// Picks [handle] up with a mouse — after [select]ing it, where the
  /// surface's first drag selects — and hands back the chip it hangs.
  Future<List<DragChipItem>> pickUp(
    WidgetTester tester,
    Finder handle, {
    required Offset nudge,
    Offset? select,
  }) async {
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    if (select != null) {
      await tester.dragFrom(tester.getCenter(handle), select);
      await tester.pumpAndSettle();
    }
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(nudge);
    await tester.pump();
    final items = find.byType(DragChip).evaluate().isEmpty
        ? const <DragChipItem>[]
        : tester.widget<DragChip>(find.byType(DragChip)).items;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(DragChip), findsNothing, reason: 'put down with it');
    return items;
  }

  testWidgets('a row that cannot move, held inside the selection, lifts and '
      'shows what it holds all the same (F-16-Q1: 「통일감」)', (tester) async {
    await pumpApp(tester);

    final held = await pickUp(
      tester,
      railRow('cam'),
      select: const Offset(30, 0),
      nudge: const Offset(0, 12),
    );
    expect([for (final item in held) item.label], ['Camera']);
  });

  testWidgets('a row taken away mid-drag takes its chip with it', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    await tester.ensureVisible(railRow('c'));
    await tester.pumpAndSettle();
    await tester.dragFrom(tester.getCenter(railRow('c')), const Offset(30, 0));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(railRow('c')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump();
    expect(find.byType(DragChip), findsOneWidget, reason: 'premise');

    session.selectLayer(const LayerId('c'));
    session.layerVerbs.deleteActiveLayer();
    await tester.pump();
    await tester.pump();
    expect(railRow('c'), findsNothing, reason: 'premise: the row is gone');
    expect(
      find.byType(DragChip),
      findsNothing,
      reason: 'nothing is left hanging at the pointer',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the timeline\'s other rows wear it too — an fx header by the '
      'effect glyph, a sheet column by its layer', (tester) async {
    final session = await pumpApp(tester);
    session.selectLayer(const LayerId('b'));
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.values.first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-lane-toggle-b')),
    );
    await tester.pumpAndSettle();
    final effectId = session.requireActiveCut.layers
        .firstWhere((layer) => layer.id == const LayerId('b'))
        .effects
        .single
        .id;

    final header = await pickUp(
      tester,
      // By its label, like a layer row by its name ([railRow]): the header
      // wears the layer row's trailing skeleton, and its centre is the
      // group's Reset since the opacity column widened.
      find
          .descendant(
            of: find.byKey(
              ValueKey<String>(
                'timeline-lane-label-b-fx-group:${effectId.value}',
              ),
            ),
            matching: find.byType(Text),
          )
          .first,
      select: const Offset(30, 0),
      nudge: const Offset(0, 12),
    );
    expect(
      [for (final item in header) item.icon],
      [Icons.auto_fix_high_outlined],
      reason: 'an effect travels alone, under the glyph effects wear',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final column = await pickUp(
      tester,
      find.byKey(const ValueKey<String>('xsheet-layer-name-a')),
      // The sheet runs the other way, so its select nudge does too.
      select: const Offset(0, 30),
      nudge: const Offset(12, 0),
    );
    expect([for (final item in column) item.label], ['A']);
  });

  testWidgets('the storyboard\'s rows wear it too — an S row by its layer, a '
      'V row by its name, a V row\'s fx header by the effect glyph', (
    tester,
  ) async {
    const trackA = TrackId('track-a');
    Cut cut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      canvasSize: const CanvasSize(width: 1280, height: 720),
      layers: [
        Layer(id: LayerId('$id-layer'), name: 'A', frames: const []),
      ],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('storyboard-chip-project'),
        name: 'Storyboard Chips',
        createdAt: DateTime.utc(2026, 9, 24),
        tracks: [
          Track(
            id: trackA,
            name: 'Video',
            effects: [
              LayerEffect.defaults(
                id: const EffectId('fx-a'),
                kind: EffectKind.values.first,
              ),
            ],
            seLayers: [
              Layer(
                id: const LayerId('s1'),
                name: 'S1',
                kind: LayerKind.se,
                frames: const [],
              ),
            ],
            cuts: [cut('cut-a')],
          ),
          // A second track, or the V rows have no order to change.
          Track(
            id: const TrackId('track-b'),
            name: 'Video',
            cuts: [cut('cut-b')],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    final expandedTracks = <String>{};
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => StoryboardPanel(
              project: session.repository.requireProject(),
              activeCutId: const CutId('cut-a'),
              pixelsPerFrame: 12,
              projectFrameRate: ProjectFrameRate.fps24,
              audioPeaksFor: (_) => null,
              expandedSeAudioRows: const <String>{},
              expandedTransformTracks: expandedTracks,
              onToggleTrackLane: (track) => setState(() {
                if (!expandedTracks.add(track.id.value)) {
                  expandedTracks.remove(track.id.value);
                }
              }),
              expandedTransformGroups: const <String>{},
              poseDisplaySize: const CanvasSize(width: 640, height: 360),
              // The session's own hooks, as the host wires them — with no
              // row selection here, a press moves at once.
              rowDragHooks: TimelineRowDragHooks(
                drag: session.layerRowDragVerbs.inFlight,
                onBegin: session.layerRowDragVerbs.beginLayerRowDrag,
                onUpdate: session.layerRowDragVerbs.updateLayerRowDrag,
                onRowTarget: session.layerRowDragVerbs.updateLayerRowDropOnRow,
                onTrackUpdate: session.layerRowDragVerbs.updateTrackRowDrag,
                onEffectUpdate: session.layerRowDragVerbs.updateEffectRowDrag,
                onEnd: session.layerRowDragVerbs.endLayerRowDrag,
                onCancel: session.layerRowDragVerbs.cancelLayerRowDrag,
                rowsActedOnBy: session.rowSelectionVerbs.rowsActedOnBy,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sRow = await pickUp(
      tester,
      find.byKey(const ValueKey<String>('storyboard-se-label-track-a-1')),
      nudge: const Offset(0, 12),
    );
    expect([for (final item in sRow) item.label], ['S1']);

    final vRow = await pickUp(
      tester,
      find.byKey(const ValueKey<String>('storyboard-track-label-row-track-a')),
      nudge: const Offset(0, 12),
    );
    expect([for (final item in vRow) item.label], ['V1']);

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-track-lane-toggle-track-a')),
    );
    await tester.pumpAndSettle();
    final fxHeader = await pickUp(
      tester,
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-label-v-track:track-a-fx-group:fx-a',
        ),
      ),
      nudge: const Offset(0, 12),
    );
    expect(
      [for (final item in fxHeader) item.icon],
      [Icons.auto_fix_high_outlined],
    );
  });
}
