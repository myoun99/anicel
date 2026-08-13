import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../helpers/brush_canvas_fixture.dart';

void main() {
  testWidgets(
    'production host without selection shows the blank canvas, not brush input',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MainCanvasBrushHost())),
      );
      await tester.pumpAndSettle();

      // The panel (and its paper) stays visible so the canvas never goes
      // blank, but there is no editable brush view — drawing needs a frame.
      expect(find.byType(BrushCanvasPanel), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('main-canvas-brush-host-blank-canvas'),
        ),
        findsOneWidget,
      );
      expect(find.byType(InteractiveBrushEditCanvasView), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('brush-canvas-view')),
        findsNothing,
      );
    },
  );

  testWidgets('no editable frame keeps the composited underlay VISIBLE — '
      'the blank content must not paint paper over it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            // No selection: the active layer has no frame at the playhead,
            // but the other layers' composite (the underlay) must show.
            viewportUnderlayBuilder: (context, viewport, _, _) => const ColoredBox(
              key: ValueKey<String>('underlay-probe'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('underlay-probe')),
      findsOneWidget,
    );
    final blank = tester.widget(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-blank-canvas')),
    );
    expect(
      blank,
      isA<SizedBox>(),
      reason:
          'with an underlay the blank content stays transparent — an '
          'opaque paper here buried the layers below the active one',
    );
  });

  testWidgets('missing selection does not create fake editable brush state', (
    tester,
  ) async {
    const key = BrushFrameKey(
      projectId: ProjectId('project-real'),
      trackId: TrackId('track-real'),
      cutId: CutId('cut-real'),
      layerId: LayerId('layer-real'),
      frameId: FrameId('frame-real'),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MainCanvasBrushHost())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveBrushEditCanvasView), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MainCanvasBrushHost(activeFrameKey: key)),
      ),
    );
    await tester.pumpAndSettle();

    // R13-2: the view's key is STABLE ('brush-canvas-view'); the edited cel
    // is the widget's frameId, not the key.
    final view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(view.frameId, const FrameId('frame-real'));
    expect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-blank-canvas')),
      findsNothing,
    );
  });

  testWidgets(
    'explicit fixture data injection embeds reusable brush view without screen',
    (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MainCanvasBrushHost(
              activeFrameKey: frameKeys.first,
              availableFrameKeys: frameKeys,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('main-canvas-brush-host')),
        findsOneWidget,
      );
      expect(find.byType(BrushCanvasPanel), findsOneWidget);
      expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);
      expect(
        tester
            .widget<InteractiveBrushEditCanvasView>(
              find.byType(InteractiveBrushEditCanvasView),
            )
            .frameId,
        frameKeys.first.frameId,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-frame-1-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-frame-2-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('brush-frame-3-button')),
        findsNothing,
      );
      expect(find.text('Debug Reset Session'), findsNothing);
      expect(find.text('Black'), findsNothing);
      expect(find.text('Red'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('brush-workspace-screen')),
        findsNothing,
      );
    },
  );

  testWidgets('accepts a supplied non-fixture active frame key', (
    tester,
  ) async {
    const key = BrushFrameKey(
      projectId: ProjectId('project-real'),
      trackId: TrackId('track-real'),
      cutId: CutId('cut-real'),
      layerId: LayerId('layer-real'),
      frameId: FrameId('frame-real'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MainCanvasBrushHost(activeFrameKey: key)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);
    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .frameId,
      const FrameId('frame-real'),
    );
  });

  testWidgets('recreates sessions when active cut canvas size changes', (
    tester,
  ) async {
    const key = BrushFrameKey(
      projectId: ProjectId('project-real'),
      trackId: TrackId('track-real'),
      cutId: CutId('cut-real'),
      layerId: LayerId('layer-real'),
      frameId: FrameId('frame-real'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: key,
            canvasSize: CanvasSize(width: 64, height: 48),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(
      view.sessionState.canvasState.currentSurface.canvasSize,
      const CanvasSize(width: 64, height: 48),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: key,
            canvasSize: CanvasSize(width: 96, height: 72),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(
      view.sessionState.canvasState.currentSurface.canvasSize,
      const CanvasSize(width: 96, height: 72),
    );
  });

  testWidgets('updates canvas when active frame key changes', (tester) async {
    const frameA = BrushFrameKey(
      projectId: ProjectId('project-real'),
      trackId: TrackId('track-real'),
      cutId: CutId('cut-real'),
      layerId: LayerId('layer-real'),
      frameId: FrameId('frame-a'),
    );
    const frameB = BrushFrameKey(
      projectId: ProjectId('project-real'),
      trackId: TrackId('track-real'),
      cutId: CutId('cut-real'),
      layerId: LayerId('layer-real'),
      frameId: FrameId('frame-b'),
    );
    const frames = [frameA, frameB];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: frameA,
            availableFrameKeys: frames,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    InteractiveBrushEditCanvasView view() =>
        tester.widget<InteractiveBrushEditCanvasView>(
          find.byType(InteractiveBrushEditCanvasView),
        );
    expect(view().frameId, const FrameId('frame-a'));
    final elementBefore = tester.element(
      find.byType(InteractiveBrushEditCanvasView),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: frameB,
            availableFrameKeys: frames,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(view().frameId, const FrameId('frame-b'));
    // R13-2: the stable key keeps the ELEMENT alive across cel flips — the
    // view resets in place instead of remounting (the flip hitch).
    expect(
      identical(
        tester.element(find.byType(InteractiveBrushEditCanvasView)),
        elementBefore,
      ),
      isTrue,
      reason: 'cel changes must not remount the interactive view',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: frameA,
            availableFrameKeys: frames,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(view().frameId, const FrameId('frame-a'));
  });
}
