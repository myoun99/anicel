import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/canvas_viewport_pan_metrics.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

void main() {
  testWidgets('HomePage mounts production brush host in the main canvas area', (
    tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(
      find.byKey(const ValueKey<String>('main-canvas-mode-toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('main-canvas-legacy-host')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
      findsOneWidget,
    );
    expect(find.byType(MainCanvasBrushHost), findsOneWidget);
    expect(find.textContaining('Active strokes:'), findsNothing);
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);
    expect(find.text('Project Undo'), findsNothing);
    expect(find.text('Project Redo'), findsNothing);
  });

  testWidgets(
    'production brush host shows the blank canvas without active drawing frame',
    (tester) async {
      await tester.pumpWidget(const AnicelApp());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
        findsOneWidget,
      );
      expect(find.byType(MainCanvasBrushHost), findsOneWidget);
      // The panel and its paper stay visible; only brush INPUT requires a
      // selected frame. PANEL-SCOPED (R26 #31): the docked timesheet is a
      // BrushCanvasPanel too, and its ink planes are interactive views.
      expect(inMainCanvas(find.byType(BrushCanvasPanel)), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('main-canvas-brush-host-blank-canvas'),
        ),
        findsOneWidget,
      );
      expect(mainCanvasView(), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('brush-canvas-default-frame')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-canvas-frame-1')),
        findsNothing,
      );
      expect(find.text('Debug Reset Session'), findsNothing);
      expect(find.text('Black'), findsNothing);
      expect(find.text('Red'), findsNothing);
    },
  );

  testWidgets(
    'production brush host uses active editor selection when a frame exists',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _projectWithActiveFrame())),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MainCanvasBrushHost), findsOneWidget);
      expect(inMainCanvas(find.byType(BrushCanvasPanel)), findsOneWidget);
      // R13-2: the interactive view's key is stable; the edited cel is the
      // widget's layer/frame params.
      final brushView = tester.widget<InteractiveBrushEditCanvasView>(
        mainCanvasView(),
      );
      expect(brushView.layerId, const LayerId('editor-layer'));
      expect(brushView.frameId, const FrameId('editor-frame-1'));
      expect(find.text('Active Frame: Frame 1 (frame-1)'), findsNothing);
      expect(find.text('Debug Reset Session'), findsNothing);
    },
  );

  testWidgets('runtime-created production layers do not use sample ids', (
    tester,
  ) async {
    ProjectRepository? repository;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(onRepositoryCreated: (created) => repository = created),
      ),
    );
    await tester.pumpAndSettle();

    final addLayerButton = find.byKey(
      const ValueKey<String>('timeline-toolbar-add-layer-button'),
    );
    await tester.ensureVisible(addLayerButton);
    await tester.pumpAndSettle();
    await tester.tap(addLayerButton);
    await tester.pumpAndSettle();

    final project = repository!.requireProject();
    final layerIds = project.tracks
        .expand((track) => track.cuts)
        .expand((cut) => cut.layers)
        .map((layer) => layer.id.value);
    expect(layerIds, isNot(contains(startsWith('sample-'))));
    expect(layerIds, contains('default-layer-2'));
  });

  testWidgets('R2 #12: NO canvas title on screen — the project name and the '
      'layer readout are off every canvas panel', (tester) async {
    // 유저: "이거 그냥 없애자. 캔버스패널 공통적으로. 필요하면 지금처럼
    // 알약으로 등장시킬거야." The labels are still COMPUTED (the session
    // keeps them, and null_active_cut_test still pins the gap case) — what
    // is gone is the strip that spent a row of every canvas panel on them.
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _projectWithActiveFrame())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Project: Editor Project · Cut: Editor Cut · Layer: Editor Layer · Frame: Source Frame',
      ),
      findsNothing,
    );
    expect(find.textContaining('Project: '), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('canvas-editor-panel-status-strip')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-status-capsule')),
      findsNothing,
    );
  });

  testWidgets('horizontal and vertical panbars update viewport pan', (
    tester,
  ) async {
    var viewport = CanvasViewport(zoom: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              CanvasViewportHorizontalScrollbar(
                viewport: viewport,
                editorViewportSize: const Size(100, 100),
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
              SizedBox(
                height: 100,
                child: CanvasViewportVerticalScrollbar(
                  viewport: viewport,
                  editorViewportSize: const Size(100, 100),
                  canvasSize: const CanvasSize(width: 300, height: 300),
                  onViewportChanged: (next) => setState(() => viewport = next),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(
        const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
      ),
      const Offset(20, 0),
    );
    await tester.pump();
    expect(viewport.panX, isNot(0));

    await tester.drag(
      find.byKey(const ValueKey<String>('canvas-viewport-vertical-scrollbar')),
      const Offset(0, 20),
    );
    await tester.pump();
    expect(viewport.panY, isNot(0));
  });

  testWidgets('horizontal panbar thumb follows pointer delta 1:1', (
    tester,
  ) async {
    var viewport = CanvasViewport(zoom: 2);
    const trackWidth = 300.0;
    const editorViewportSize = Size(100, 100);
    const canvasSize = CanvasSize(width: 500, height: 500);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: trackWidth,
              height: 14,
              child: CanvasViewportHorizontalScrollbar(
                viewport: viewport,
                editorViewportSize: editorViewportSize,
                canvasSize: canvasSize,
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
            ),
          ),
        ),
      ),
    );

    final initialMetrics = CanvasViewportPanMetrics(
      axis: Axis.horizontal,
      viewport: viewport,
      editorViewportSize: editorViewportSize,
      canvasSize: canvasSize,
      trackExtent: trackWidth,
    );

    await tester.drag(
      find.byKey(
        const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
      ),
      const Offset(100, 0),
    );
    await tester.pump();

    final finalMetrics = CanvasViewportPanMetrics(
      axis: Axis.horizontal,
      viewport: viewport,
      editorViewportSize: editorViewportSize,
      canvasSize: canvasSize,
      trackExtent: trackWidth,
    );

    expect(
      finalMetrics.thumbStart - initialMetrics.thumbStart,
      closeTo(100, 0.001),
    );
  });

  testWidgets('vertical panbar thumb follows pointer delta 1:1', (
    tester,
  ) async {
    var viewport = CanvasViewport(zoom: 2);
    const trackHeight = 300.0;
    const editorViewportSize = Size(100, 100);
    const canvasSize = CanvasSize(width: 500, height: 500);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 14,
              height: trackHeight,
              child: CanvasViewportVerticalScrollbar(
                viewport: viewport,
                editorViewportSize: editorViewportSize,
                canvasSize: canvasSize,
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
            ),
          ),
        ),
      ),
    );

    final initialMetrics = CanvasViewportPanMetrics(
      axis: Axis.vertical,
      viewport: viewport,
      editorViewportSize: editorViewportSize,
      canvasSize: canvasSize,
      trackExtent: trackHeight,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('canvas-viewport-vertical-scrollbar')),
      const Offset(0, 100),
    );
    await tester.pump();

    final finalMetrics = CanvasViewportPanMetrics(
      axis: Axis.vertical,
      viewport: viewport,
      editorViewportSize: editorViewportSize,
      canvasSize: canvasSize,
      trackExtent: trackHeight,
    );

    expect(
      finalMetrics.thumbStart - initialMetrics.thumbStart,
      closeTo(100, 0.001),
    );
  });

  testWidgets('panbar drag clamps viewport pan to valid range', (tester) async {
    var viewport = CanvasViewport(zoom: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              CanvasViewportHorizontalScrollbar(
                viewport: viewport,
                editorViewportSize: const Size(100, 100),
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
              SizedBox(
                height: 100,
                child: CanvasViewportVerticalScrollbar(
                  viewport: viewport,
                  editorViewportSize: const Size(100, 100),
                  canvasSize: const CanvasSize(width: 300, height: 300),
                  onViewportChanged: (next) => setState(() => viewport = next),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Paper×3 runway (UI-R18 #16): content spans one canvas (600px
    // scaled) each side, so the clamps land at −1100 (right end:
    // −maxScroll 1700 + runway 600) and +600 (left end).
    await tester.drag(
      find.byKey(
        const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
      ),
      const Offset(1000, 0),
    );
    await tester.pump();
    expect(viewport.panX, -1100);

    await tester.drag(
      find.byKey(
        const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
      ),
      const Offset(-1000, 0),
    );
    await tester.pump();
    expect(viewport.panX, 600);

    await tester.drag(
      find.byKey(const ValueKey<String>('canvas-viewport-vertical-scrollbar')),
      const Offset(0, 1000),
    );
    await tester.pump();
    expect(viewport.panY, -1100);

    await tester.drag(
      find.byKey(const ValueKey<String>('canvas-viewport-vertical-scrollbar')),
      const Offset(0, -1000),
    );
    await tester.pump();
    expect(viewport.panY, 600);
  });

  testWidgets('panbar drag is ignored when there is no scroll range', (
    tester,
  ) async {
    var viewport = CanvasViewport(zoom: 0.5, panX: 25, panY: 30);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              CanvasViewportHorizontalScrollbar(
                viewport: viewport,
                editorViewportSize: const Size(300, 300),
                canvasSize: const CanvasSize(width: 100, height: 100),
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
              SizedBox(
                height: 100,
                child: CanvasViewportVerticalScrollbar(
                  viewport: viewport,
                  editorViewportSize: const Size(300, 300),
                  canvasSize: const CanvasSize(width: 100, height: 100),
                  onViewportChanged: (next) => setState(() => viewport = next),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(
        const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
      ),
      const Offset(100, 0),
    );
    await tester.pump();

    expect(viewport.panX, 25);
    expect(viewport.panY, 30);

    await tester.drag(
      find.byKey(const ValueKey<String>('canvas-viewport-vertical-scrollbar')),
      const Offset(0, 100),
    );
    await tester.pump();

    expect(viewport.panX, 25);
    expect(viewport.panY, 30);
  });

  testWidgets('viewport survives frame layer and cut selection changes', (
    tester,
  ) async {
    var activeKey = const BrushFrameKey(
      projectId: ProjectId('project'),
      trackId: TrackId('track'),
      cutId: CutId('cut-a'),
      layerId: LayerId('layer-a'),
      frameId: FrameId('frame-a'),
    );
    final viewport = CanvasViewport(zoom: 2, panX: -25, panY: -30);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              TextButton(
                onPressed: () => setState(
                  () => activeKey = const BrushFrameKey(
                    projectId: ProjectId('project'),
                    trackId: TrackId('track'),
                    cutId: CutId('cut-b'),
                    layerId: LayerId('layer-b'),
                    frameId: FrameId('frame-b'),
                  ),
                ),
                child: const Text('Switch selection'),
              ),
              Expanded(
                child: MainCanvasBrushHost(
                  activeFrameKey: activeKey,
                  availableFrameKeys: const [
                    BrushFrameKey(
                      projectId: ProjectId('project'),
                      trackId: TrackId('track'),
                      cutId: CutId('cut-a'),
                      layerId: LayerId('layer-a'),
                      frameId: FrameId('frame-a'),
                    ),
                    BrushFrameKey(
                      projectId: ProjectId('project'),
                      trackId: TrackId('track'),
                      cutId: CutId('cut-b'),
                      layerId: LayerId('layer-b'),
                      frameId: FrameId('frame-b'),
                    ),
                  ],
                  viewport: viewport,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport,
      viewport,
    );
    await tester.tap(find.text('Switch selection'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport,
      viewport,
    );
  });

  testWidgets('separate Brush Workspace route entry is retired', (
    tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(
      find.byKey(const ValueKey<String>('brush-workspace-entry')),
      findsNothing,
    );
    expect(find.text('Brush Workspace'), findsNothing);
  });
}

Project _projectWithMarkedFrame({String? name}) {
  return Project(
    id: const ProjectId('marked-project'),
    name: 'Marked Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('marked-track'),
        name: 'Track 1',
        cuts: [
          Cut(
            id: const CutId('marked-cut'),
            name: 'Marked Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: const LayerId('marked-layer'),
                name: 'Marked Layer',
                frames: [
                  Frame(
                    id: const FrameId('marked-frame'),
                    name: name,
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('marked-frame'),
                    length: 1,
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Project _projectWithActiveFrame() {
  return Project(
    id: const ProjectId('editor-project'),
    name: 'Editor Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('editor-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('editor-cut'),
            name: 'Editor Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: const LayerId('editor-layer'),
                name: 'Editor Layer',
                frames: [
                  Frame(
                    id: const FrameId('editor-frame-1'),
                    name: 'Source Frame',
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('editor-frame-1'),
                    length: 1,
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
