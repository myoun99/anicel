import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// The interactive canvas STAYS MOUNTED as the playhead crosses "no cel ↔
/// cel". It used to be swapped for a blank box whenever the frame under
/// the playhead had nothing on it, so every flip step that touched a block
/// built the whole editing view and tore it down again — measured at
/// 35–40% of the crossing step's excess cost, on top of the panel remount
/// #861 removed.
///
/// The frame's emptiness travels as a FLAG now ([BrushCanvasPanel.celEditable]
/// → [InteractiveBrushEditCanvasView.editable]), and the view stands down
/// in place: no pointers, no painting.
///
/// ⚠️ Two oracles, and both are needed. "The view is mounted" alone would
/// pass against a view that happily draws the cel the playhead has left
/// and accepts strokes onto it.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  final mainPanel = find.byKey(
    const ValueKey<String>('main-canvas-brush-host'),
  );
  final canvasView = find.byKey(const ValueKey<String>('brush-canvas-view'));

  Future<EditorWorkspace> openApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));
  }

  bool hasCel(WidgetTester tester) =>
      tester
          .widget<MainCanvasBrushHost>(
            find.ancestor(
              of: mainPanel,
              matching: find.byType(MainCanvasBrushHost),
            ),
          )
          .resolvedActiveFrameKey !=
      null;

  testWidgets('crossing "no cel <-> cel" never rebuilds the interactive '
      'canvas', (tester) async {
    final session = (await openApp(tester)).session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(hasCel(tester), isTrue);
    expect(canvasView, findsOneWidget);
    final mounted = tester.element(canvasView);

    for (final frame in [4, 0, 5, 0, 6]) {
      session.selectFrameIndex(frame);
      await tester.pumpAndSettle();
      expect(
        canvasView,
        findsOneWidget,
        reason: 'frame $frame: the view is mounted whether or not a cel is '
            'under the playhead',
      );
      expect(
        identical(tester.element(canvasView), mounted),
        isTrue,
        reason: 'frame $frame: and it is the SAME view, never rebuilt',
      );
    }
    // The walk really did cross: the last frame has no cel.
    expect(hasCel(tester), isFalse);

    session.prerenderScheduler.cancel();
  });

  testWidgets('on an empty frame the mounted view stands down — no cel '
      'painted, no pointers taken', (tester) async {
    final session = (await openApp(tester)).session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    InteractiveBrushEditCanvasView view() =>
        tester.widget<InteractiveBrushEditCanvasView>(canvasView);

    expect(view().editable, isTrue, reason: 'a cel is under the playhead');

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(hasCel(tester), isFalse);
    expect(
      view().editable,
      isFalse,
      reason: 'the frame is empty, so the view stands down',
    );
    // The State is alive but NOTHING under it is built: no listener (so
    // the subtree leaves hit testing, exactly as an absent widget did and
    // the shell's refusal notice still sees the press) and no canvas (so
    // the cel the playhead has left is not painted).
    // Scoped to THIS view: the conte, timesheet and envelope sheets mount
    // interactive views of their own, and theirs are still live.
    expect(
      find.descendant(
        of: canvasView,
        matching: find.byKey(
          const ValueKey<String>(
            'interactive-brush-edit-canvas-view-listener',
          ),
        ),
      ),
      findsNothing,
      reason: 'the standing-down view takes no pointers',
    );
    expect(
      find.descendant(
        of: canvasView,
        matching: find.byKey(
          const ValueKey<String>('interactive-brush-edit-canvas-clip'),
        ),
      ),
      findsNothing,
      reason: 'and paints no cel',
    );

    session.prerenderScheduler.cancel();
  });

  testWidgets('a paint press on an empty frame is still REFUSED, and lands '
      'no stroke', (tester) async {
    // A pen draws on this surface; the refusal notice is the shell's.
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    final session = (await openApp(tester)).session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    final drawnBefore = session.activeCutOrNull!.layers
        .firstWhere((layer) => layer.id == layerId)
        .timeline
        .length;

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(hasCel(tester), isFalse);

    final press = await tester.startGesture(
      tester.getCenter(canvasView),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();

    expect(
      session.activeCutOrNull!.layers
          .firstWhere((layer) => layer.id == layerId)
          .timeline
          .length,
      drawnBefore,
      reason: 'the empty frame took no ink — the view refused the pointer',
    );

    session.prerenderScheduler.cancel();
  });

  // The main canvas runs MERGED (`paintsContent: false` — the composite
  // tree paints the active layer), so its tests can say nothing about what
  // a CONTENT-PAINTING mount does when it stands down. Every other surface
  // that mounts this view paints its own content, so the rule is asked
  // here directly, or a mutant walks through it.
  testWidgets('a content-painting view draws NOTHING when it is not '
      'editable', (tester) async {
    Future<void> pumpView({required bool editable}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveBrushEditCanvasView(
            key: const ValueKey<String>('brush-canvas-view'),
            sessionState: BrushEditSessionState(
              canvasState: CanvasSurfaceState(
                currentSurface: BitmapSurface(
                  canvasSize: const CanvasSize(width: 64, height: 64),
                  tileSize: 2,
                ),
              ),
              materializationHistoryState:
                  BrushBitmapMaterializationHistoryState(),
            ),
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: BrushEditCanvasInputSettings(),
            onSourceStrokeCommitted: (_) {},
            editable: editable,
          ),
        ),
      ),
    );

    final painted = find.byKey(
      const ValueKey<String>('interactive-brush-edit-canvas-clip'),
    );

    await pumpView(editable: true);
    expect(painted, findsOneWidget, reason: 'editable: it paints its cel');

    await pumpView(editable: false);
    expect(
      painted,
      findsNothing,
      reason: 'not editable: the session still points at the cel the '
          'playhead has LEFT, so painting it would show the wrong drawing',
    );
  });
}
