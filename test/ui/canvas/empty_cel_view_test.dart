import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

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

    session.playbackRig.prerenderScheduler.cancel();
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
    // The State is alive and so is its listener — but TRANSLUCENT, which
    // leaves hit testing exactly as the absent widget did: what is under
    // this view in the panel's Stack still receives, and the shell's
    // refusal notice still sees the press.
    //
    // ⚠️It used to be built at all only when editable, and asserted here as
    // `findsNothing`. That is what made I-10's second half impossible: a
    // listener that appears only AFTER the cel exists cannot be in the hit
    // path of the press that created it, so the block appeared and the
    // stroke never started (유저: 「자동생성은 되는데 선이 안그려지고있음」).
    // The invariant that actually mattered was 「takes nothing away from
    // what is underneath」, and that is what is asserted now.
    // Scoped to THIS view: the conte, timesheet and envelope sheets mount
    // interactive views of their own, and theirs are still live.
    expect(
      tester
          .widget<Listener>(
            find.descendant(
              of: canvasView,
              matching: find.byKey(
                const ValueKey<String>(
                  'interactive-brush-edit-canvas-view-listener',
                ),
              ),
            ),
          )
          .behavior,
      HitTestBehavior.translucent,
      reason: 'the standing-down view stands in nobody\u0027s way',
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

    session.playbackRig.prerenderScheduler.cancel();
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
      // 🚨NOT `getCenter(canvasView)`. The canvas is the app's FLOOR — laid
      // out full-bleed with the panels lying on top — so the centre of its
      // BOX is under the always-open timeline, and a press aimed there
      // never reaches the drawing view at all. 🧪Measured: with a probe in
      // `_handlePointerDown`, a press at that point produced NOTHING even
      // on a frame that HAS a cel and draws fine by hand.
      //
      // ⛔That is what made the refusal below vacuous: it asserted no ink
      // from a press the canvas never heard, so it would have passed
      // against a canvas that inked everything. `visibleCanvasPoint` is the
      // helper that exists for exactly this, and its own doc names the trap.
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    // 🚨R26 #35's whole point, and it had never once been measured: the
    // refusal SPEAKS. It could not be, because the press was aimed at the
    // centre of the canvas BOX — under the timeline — so nothing ever
    // reached the canvas and 「no ink」 was true of a press that never
    // happened.
    // ⚠️Pumped by hand rather than settled: the notice is transient, and
    // `pumpAndSettle` would wait for it to expire and then find nothing.
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.text(AppText.strings.noticeNoFrameHere),
      findsOneWidget,
      reason: 'the shell says WHY nothing happened',
    );
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

    session.playbackRig.prerenderScheduler.cancel();
  });

  // 🚨I-10's SECOND HALF, and the report that reopened it (F-61, 유저:
  // 「그릴때 자동생성은 되는데 **선이 안그려지고있음**」) against what was
  // asked for: 「빈 칸에서 펜다운하면 블록이 자동생성되고 **그대로 스트로크
  // 그려지기시작**」.
  //
  // ⚠️TWO oracles on ONE press, and both are needed: the block alone was
  // already true when the bug was reported, and ink alone could come from a
  // cel that existed beforehand.
  testWidgets('with the toggle ON one press makes the block AND draws into '
      'it', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
      autoCreateFrameOnDraw: true,
    );
    final session = (await openApp(tester)).session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    Layer layer() => session.activeCutOrNull!.layers.firstWhere(
      (candidate) => candidate.id == layerId,
    );
    final drawnBefore = layer().timeline.length;

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    // ★The premise, and it is the whole setup: there is no cel here, and
    // there IS a coordinator (frame 0 was drawn on), so the interactive
    // view is mounted and standing down — the case the fix is about.
    expect(hasCel(tester), isFalse);
    expect(
      session.layerContentBoundsAt(layer(), 4),
      isNull,
      reason: 'nothing is on this frame yet',
    );

    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    await press.moveBy(const Offset(30, 20));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();

    expect(
      layer().timeline.length,
      drawnBefore + 1,
      reason: '「빈 칸에서 펜다운하면 블록이 자동생성되고」',
    );
    expect(
      session.layerContentBoundsAt(layer(), 4),
      isNotNull,
      reason: '「그대로 스트로크 그려지기시작」 — the half that was missing',
    );

    session.playbackRig.prerenderScheduler.cancel();
  });

  // 「답은 추천대로」 = merged: one press on an empty cel is ONE undo, and
  // both halves go back together.
  testWidgets('and the block and the stroke undo as one', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
      autoCreateFrameOnDraw: true,
    );
    final session = (await openApp(tester)).session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    Layer layer() => session.activeCutOrNull!.layers.firstWhere(
      (candidate) => candidate.id == layerId,
    );
    final drawnBefore = layer().timeline.length;

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();

    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    expect(layer().timeline.length, drawnBefore + 1);

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(
      layer().timeline.length,
      drawnBefore,
      reason: '⛔ONE undo takes the ink AND the block it was drawn into',
    );

    session.playbackRig.prerenderScheduler.cancel();
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
