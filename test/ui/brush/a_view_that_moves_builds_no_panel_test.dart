import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/canvas_stage.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool_layer.dart';

/// a-view-change-rebuilds-the-whole-canvas-panel (2026-11-20): every move
/// of the view — a pan's step, an owner's write, the room a docked panel
/// stands in changing — built the whole canvas panel again: its shell and
/// pill, the deck's gates, the tool's entrance. What is drawn through the
/// view builds for it, and nothing else does.
void main() {
  // The wheel pans only when it is mapped to (I-15).
  setUp(() {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      canvasWheelClick: const CanvasPointerMapping(
        action: CanvasPointerAction.pan,
      ),
    );
  });
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// What is drawn through the view, with every view it was built with.
  final drawn = <String, List<CanvasViewport>>{};

  /// Every stage the content stood on ([CanvasStage]).
  final stoodOn = <Rect?>[];

  /// A docked panel in a box [room] tall — the same panel widget at every
  /// height, so whatever builds it again is its own doing — its view kept
  /// in [view].
  Future<void> pumpDocked(
    WidgetTester tester, {
    required ValueListenable<double> room,
    required ValueNotifier<CanvasViewport?> view,
  }) async {
    drawn.clear();
    stoodOn.clear();
    Widget through(String what, CanvasViewport viewport) {
      (drawn[what] ??= []).add(viewport);
      return SizedBox.expand(key: ValueKey<String>(what));
    }

    final panel = BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: BrushEditCacheInvalidationSink(),
      canvasSize: const CanvasSize(width: 300, height: 300),
      viewportController: view,
      contentOverride: (context, viewport) => Builder(
        builder: (context) {
          stoodOn.add(CanvasStage.maybeOf(context));
          return through('content', viewport);
        },
      ),
      viewportUnderlayBuilder: (context, viewport, painter, rows) =>
          through('underlay', viewport),
      viewportOverlayBuilder: (context, viewport) =>
          through('overlay', viewport),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: room,
              builder: (context, height, panel) =>
                  SizedBox(width: 600, height: height, child: panel),
              child: panel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The elements [act] and the frames after it built again, by the type of
  /// their widget.
  Future<List<Type>> builtBy(
    WidgetTester tester,
    Future<void> Function() act,
  ) async {
    final built = <Type>[];
    debugOnRebuildDirtyWidget = (element, _) =>
        built.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await act();
    debugOnRebuildDirtyWidget = null;
    return built;
  }

  /// A middle-button drag over the canvas, [steps] moves of [step].
  Future<void> drag(
    WidgetTester tester, {
    required Offset step,
    int steps = 4,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('canvas-viewport-gesture-layer')),
      ),
      buttons: kTertiaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < steps; i += 1) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  CanvasViewport barShows(WidgetTester tester) => tester
      .widget<CanvasViewportVerticalScrollbar>(
        find.byType(CanvasViewportVerticalScrollbar),
      )
      .viewport;

  testWidgets('a pan builds no panel — what is drawn through the view, and '
      'the bars, follow every step', (tester) async {
    final room = ValueNotifier<double>(400);
    final view = ValueNotifier<CanvasViewport?>(CanvasViewport());
    addTearDown(room.dispose);
    addTearDown(view.dispose);
    await pumpDocked(tester, room: room, view: view);
    final before = drawn['content']!.last;

    final built = await builtBy(
      tester,
      () => drag(tester, step: const Offset(0, 8)),
    );

    final now = drawn['content']!.last;
    expect(now.panY, greaterThan(before.panY), reason: 'premise: it panned');
    expect(built, isNot(contains(BrushCanvasPanel)));
    for (final what in ['underlay', 'overlay']) {
      expect(drawn[what]!.last, now, reason: '$what stands at the view');
    }
    expect(barShows(tester), now);
  });

  testWidgets("an owner's write builds no panel, and a pan after it starts "
      'where the owner put the view', (tester) async {
    final room = ValueNotifier<double>(400);
    final view = ValueNotifier<CanvasViewport?>(CanvasViewport());
    addTearDown(room.dispose);
    addTearDown(view.dispose);
    await pumpDocked(tester, room: room, view: view);
    final before = drawn['content']!.last;

    final built = await builtBy(tester, () async {
      view.value = view.value!.translated(dx: 3000, dy: 0);
      await tester.pump();
    });

    final written = drawn['content']!.last;
    expect(written.panX, greaterThan(before.panX + 100));
    expect(written.panY, before.panY);
    expect(built, isNot(contains(BrushCanvasPanel)));
    for (final what in ['underlay', 'overlay']) {
      expect(drawn[what]!.last, written, reason: '$what stands at the view');
    }
    expect(barShows(tester), written);

    await drag(tester, step: const Offset(0, 8));

    final panned = drawn['content']!.last;
    expect(panned.panY, greaterThan(written.panY), reason: 'premise');
    expect(panned.panX, written.panX);
  });

  testWidgets("a docked panel's room changing builds no panel and none of "
      'its gates — what it draws stands in the new room at once, and its bars '
      'after the frame', (tester) async {
    final room = ValueNotifier<double>(400);
    final view = ValueNotifier<CanvasViewport?>(CanvasViewport());
    addTearDown(room.dispose);
    addTearDown(view.dispose);
    await pumpDocked(tester, room: room, view: view);
    final tall = stoodOn.last!.height;
    Size barsRoom() => tester
        .widget<CanvasViewportVerticalScrollbar>(
          find.byType(CanvasViewportVerticalScrollbar),
        )
        .editorViewportSize;
    final barsTall = barsRoom().height;

    final built = await builtBy(tester, () async {
      room.value = 300;
      await tester.pump();
      expect(stoodOn.last!.height, tall - 100, reason: 'in the same frame');
      await tester.pump();
    });

    expect(barsRoom().height, barsTall - 100);
    expect(built, isNot(contains(BrushCanvasPanel)));
    expect(built, isNot(contains(ViewHoldGate)));
  });

  /// A panel standing [tool] over a selection, its view kept in [view] —
  /// what is laid through the view by the host is in [laid].
  Future<void> pumpStanding(
    WidgetTester tester,
    CanvasTool tool, {
    required ValueNotifier<CanvasViewport?> view,
    required Map<String, CanvasViewport> laid,
  }) async {
    final brush = ValueNotifier(BrushToolState.defaults.copyWith(tool: tool));
    addTearDown(brush.dispose);
    final selection = CanvasSelectionCommands()
      ..setRegion(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 10, top: 10, right: 50, bottom: 50),
        ),
      );
    addTearDown(selection.dispose);
    Widget lay(String what, CanvasViewport viewport) {
      laid[what] = viewport;
      return const SizedBox.expand();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            canvasSize: const CanvasSize(width: 300, height: 300),
            viewportController: view,
            brushToolState: brush,
            selectionCommands: selection,
            contentOverride: (context, viewport) => lay('content', viewport),
            viewportOverlayBuilder: (context, viewport) =>
                lay('overlay', viewport),
            viewportControlsBuilder: (context, viewport) =>
                lay('controls', viewport),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  T paintedBy<T extends CustomPainter>(
    WidgetTester tester, [
    bool Function(T painter)? which,
  ]) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<T>()
      .where(which ?? (_) => true)
      .single;

  for (final tool in [CanvasTool.brush, CanvasTool.select, CanvasTool.text]) {
    testWidgets('with the ${tool.name} in hand, all that stands on the canvas '
        'is laid again through the view as it moves', (tester) async {
      final view = ValueNotifier<CanvasViewport?>(CanvasViewport());
      addTearDown(view.dispose);
      final laid = <String, CanvasViewport>{};
      await pumpStanding(tester, tool, view: view, laid: laid);
      final outline = find.byKey(
        const ValueKey<String>('brush-cursor-overlay'),
      );
      Object? outlineLook() => tool == CanvasTool.brush
          ? tester.widget<ToolCursorSprite>(outline).look.key
          : null;
      if (tool == CanvasTool.brush) {
        final look = tester.widget<ToolCursorSprite>(outline).look;
        view.value = CanvasViewport(panX: 40, panY: 20);
        await tester.pump();
        expect(
          identical(tester.widget<ToolCursorSprite>(outline).look, look),
          isTrue,
          reason: 'a pan moves no outline',
        );
      }
      final outlineBefore = outlineLook();
      final before = laid['content'];

      view.value = CanvasViewport(zoom: 3, panX: 40, panY: 20);
      await tester.pump();

      final now = laid['content']!;
      expect(now, isNot(before), reason: 'premise: the view moved');
      final standing = <String, CanvasViewport>{
        'overlay': laid['overlay']!,
        'controls': laid['controls']!,
        'stage planes': paintedBy<StagePlanesPainter>(tester).viewport,
        'line ants': paintedBy<SelectionAntsPainter>(
          tester,
          (ants) => ants.committedRegion == null,
        ).viewport,
        if (tool == CanvasTool.brush)
          'idle ants': paintedBy<SelectionAntsPainter>(
            tester,
            (ants) => ants.committedRegion != null,
          ).viewport,
        if (tool == CanvasTool.select)
          'selection layer': tester
              .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer))
              .viewport,
        if (tool == CanvasTool.text)
          'text layer': tester
              .widget<CelTextToolLayer>(find.byType(CelTextToolLayer))
              .stage
              .viewport,
      };
      for (final MapEntry(key: what, value: viewport) in standing.entries) {
        expect(viewport, now, reason: what);
      }
      if (tool == CanvasTool.brush) {
        expect(outlineLook(), isNot(outlineBefore), reason: 'the outline');
      }
    });
  }
}
