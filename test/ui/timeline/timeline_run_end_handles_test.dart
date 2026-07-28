import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_run_edit.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';

import 'timeline_cell_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// UI-R9 #10: the run-edge cluster — the accent [+] add chip, the N/H/R
/// property tag + flyout, and the GHOST display.
///
/// The cluster is PAINTED (R28 #4 tier 2): its identity, geometry and hit
/// rects come off the row's chrome model, and every gesture below starts
/// from the rect the row itself hit-tests.
void main() {
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Layer plainLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      6: const TimelineExposure.drawing(FrameId('f2'), length: 2),
    },
  );

  /// Block [0,2) with an END REPEAT edge filling ghosts to cut frame 6.
  Layer repeatedLayer() => rederiveRunBehaviors(
    Layer(
      id: const LayerId('layer-r'),
      name: 'R',
      frames: [Frame(id: const FrameId('rf'), duration: 1, strokes: const [])],
      timeline: {0: const TimelineExposure.drawing(FrameId('rf'), length: 2)},
      runBehaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('rf'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.repeat,
        ),
      ],
    ),
    cutFrameCount: 6,
  );

  Widget harness({
    required List<Layer> layers,
    required TimelineRunEditCallbacks runEdit,
    ValueNotifier<TimelineDragPreview?>? dragPreview,
  }) {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    return MaterialApp(
      home: Scaffold(
        body: LayerTimelineGrid(
          layers: layers,
          activeLayerId: layers.first.id,
          frameCursor: cursor,
          playbackFrameCount: 24,
          exposureStateForLayer: stateFor,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          runEdit: runEdit,
          dragPreview: dragPreview,
          // Classic geometry: drags below assume 48px cells.
          metrics: const TimelineGridMetrics(
            frameCellWidth: 48,
            layerRowHeight: 52,
          ),
        ),
      ),
    );
  }

  TimelineRunEditCallbacks recordingCallbacks({
    List<int>? addCounts,
    void Function(LayerId, int, bool)? onAddBegin,
    List<(LayerId, int, TimelineRunEdgeSide, TimelineRunEdgeMode?)>?
    modeSelections,
  }) {
    return TimelineRunEditCallbacks(
      onAddBegin: (layerId, blockStartIndex, {required atEnd}) {
        onAddBegin?.call(layerId, blockStartIndex, atEnd);
        return true;
      },
      onAddUpdate: (count) => addCounts?.add(count),
      onAddEnd: () {},
      onAddCancel: () {},
      onEdgeModeSelected:
          (layerId, blockStartIndex, side, mode, {scopeToSelection = false}) =>
              modeSelections?.add((layerId, blockStartIndex, side, mode)),
    );
  }

  testWidgets('[+] mounts at a free run end and before a run with space; '
      'dragging [+] reports frame counts', (tester) async {
    final addCounts = <int>[];
    final begins = <(LayerId, int, bool)>[];
    await tester.pumpWidget(
      harness(
        layers: [plainLayer()],
        runEdit: recordingCallbacks(
          addCounts: addCounts,
          onAddBegin: (layerId, start, atEnd) =>
              begins.add((layerId, start, atEnd)),
        ),
      ),
    );

    // Target ids carry the run ANCHOR frameId, never an index (UI-R9 A1).
    final ids = timelineRowChromeIds(tester, 'layer-a');
    expect(ids, contains('run-add-end-layer-a-f1'));
    // The second run (frame 6) has free space before it too.
    expect(ids, contains('run-add-start-layer-a-f2'));

    await tester.dragFrom(
      timelineRowChromeCenter(tester, 'layer-a', 'run-add-end-layer-a-f1'),
      const Offset(96, 0),
      kind: PointerDeviceKind.mouse,
    );
    expect(begins.single, (const LayerId('layer-a'), 0, true));
    expect(addCounts, isNotEmpty);
    expect(addCounts.last, 2);
  });

  testWidgets('start-side [+] keeps accumulating across preview steps '
      '(UI-R9 A1 regression: the prepend preview shifts the run start, and '
      'an index-keyed/preview-mounted handle remounted mid-gesture, '
      'committing one frame)', (tester) async {
    final layer = plainLayer();
    final dragPreview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(dragPreview.dispose);
    final addCounts = <int>[];
    var ends = 0;
    final callbacks = TimelineRunEditCallbacks(
      onAddBegin: (_, _, {required atEnd}) => true,
      onAddUpdate: (count) {
        addCounts.add(count);
        // The session's feedback loop: every step republishes a preview
        // layer whose run start has shifted LEFT by the count.
        final previewed = count == 0
            ? null
            : layerWithNewFramesAtRunEdge(
                layer,
                blockStartIndex: 6,
                atEnd: false,
                count: count,
                frameIdAt: (ordinal) => FrameId('new-$ordinal'),
              );
        dragPreview.value = previewed == null
            ? null
            : ExposureEdgeDragPreview(previewLayer: previewed.layer);
      },
      onAddEnd: () {
        ends += 1;
        dragPreview.value = null;
      },
      onAddCancel: () => dragPreview.value = null,
      onEdgeModeSelected: (_, _, _, _, {scopeToSelection = false}) {},
    );
    await tester.pumpWidget(
      harness(layers: [layer], runEdit: callbacks, dragPreview: dragPreview),
    );

    final gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', 'run-add-start-layer-a-f2'),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(-48, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(addCounts.last, 3);
    expect(ends, 1);
  });

  testWidgets('the edge tag is ALWAYS visible (UI-R10 #1) and opens the '
      'N/H/R flyout on pointer-down; picking Hold reports the selection', (
    tester,
  ) async {
    final modeSelections =
        <(LayerId, int, TimelineRunEdgeSide, TimelineRunEdgeMode?)>[];
    await tester.pumpWidget(
      harness(
        layers: [plainLayer()],
        runEdit: recordingCallbacks(modeSelections: modeSelections),
      ),
    );

    const tagId = 'run-edge-tag-layer-a-f1-end';
    final ids = timelineRowChromeIds(tester, 'layer-a');
    expect(
      ids,
      contains(tagId),
      reason: 'the tag shows without hover, N state included',
    );
    // Start tags mirror on the second run.
    expect(ids, contains('run-edge-tag-layer-a-f2-start'));

    // The flyout opens on POINTER DOWN (UI-R10 #2) — before any tap-up.
    final gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', tagId),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('run-edge-mode-none')),
      findsOneWidget,
      reason: 'menu is up while the pointer is still down',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('run-edge-mode-hold')));
    await tester.pumpAndSettle();

    expect(modeSelections.single, (
      const LayerId('layer-a'),
      0,
      TimelineRunEdgeSide.end,
      TimelineRunEdgeMode.hold,
    ));
  });

  testWidgets('the flyout lists "Repeat selection" only when the live '
      'selection can scope the edge, and picking it reports the scope '
      '(UI-R19 #2)', (tester) async {
    final scoped = <bool>[];
    var canScope = false;
    final callbacks = TimelineRunEditCallbacks(
      onAddBegin: (_, _, {required atEnd}) => true,
      onAddUpdate: (_) {},
      onAddEnd: () {},
      onAddCancel: () {},
      onEdgeModeSelected:
          (layerId, blockStartIndex, side, mode, {scopeToSelection = false}) =>
              scoped.add(scopeToSelection),
      canScopeToSelection: (_, _, _) => canScope,
    );
    await tester.pumpWidget(
      harness(layers: [plainLayer()], runEdit: callbacks),
    );

    const tagId = 'run-edge-tag-layer-a-f1-end';
    const selectionEntry = ValueKey<String>('run-edge-mode-repeat-selection');

    // No scopable selection: the entry stays out.
    var gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', tagId),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(find.byKey(selectionEntry), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('run-edge-mode-none')));
    await tester.pumpAndSettle();

    // A scopable selection: the entry shows; picking it scopes.
    canScope = true;
    gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', tagId),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(find.byKey(selectionEntry), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(selectionEntry));
    await tester.pumpAndSettle();

    expect(scoped, [false, true]);
  });

  testWidgets('a repeat edge keeps its cluster ON the authored run edge '
      '(UI-R10 #3), ghosts notwithstanding', (tester) async {
    final modeSelections =
        <(LayerId, int, TimelineRunEdgeSide, TimelineRunEdgeMode?)>[];
    await tester.pumpWidget(
      harness(
        layers: [repeatedLayer()],
        runEdit: recordingCallbacks(modeSelections: modeSelections),
      ),
    );

    const tagId = 'run-edge-tag-layer-r-rf-end';
    final ids = timelineRowChromeIds(tester, 'layer-r');
    expect(ids, contains(tagId));

    // The [+] chip stays too: ghost coverage never blocks authored adds.
    expect(ids, contains('run-add-end-layer-r-rf'));
    // Both sit at the run end (frame 2), NOT after the ghost tail (6).
    final edgeLeft = timelineCellGlobalRect(tester, 'layer-r', 2).left;
    expect(
      (timelineRowChromeGlobalRect(
                tester,
                'layer-r',
                'run-add-end-layer-r-rf',
              ).left -
              edgeLeft)
          .abs(),
      lessThan(4),
      reason: 'cluster hugs the authored edge at frame 2',
    );

    await tester.tapAt(timelineRowChromeCenter(tester, 'layer-r', tagId));
    await tester.pumpAndSettle();
    // Selecting None clears the edge.
    await tester.tap(find.byKey(const ValueKey<String>('run-edge-mode-none')));
    await tester.pumpAndSettle();

    expect(modeSelections.single, (
      const LayerId('layer-r'),
      0,
      TimelineRunEdgeSide.end,
      null,
    ));
  });

  testWidgets('ghosts render TEXT-ONLY (UI-R10 #11): repeat ghosts print '
      'cel names on plain cells, hold ghosts string ㅡ dashes', (tester) async {
    final holdLayer = rederiveRunBehaviors(
      Layer(
        id: const LayerId('layer-h'),
        name: 'H',
        frames: [
          Frame(id: const FrameId('hf'), duration: 1, strokes: const []),
        ],
        timeline: {0: const TimelineExposure.drawing(FrameId('hf'), length: 2)},
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('hf'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      ),
      cutFrameCount: 6,
    );
    await tester.pumpWidget(
      harness(
        layers: [repeatedLayer(), holdLayer],
        runEdit: recordingCallbacks(),
      ),
    );

    // Repeat ghosts: name glyph at ghost block starts, nothing between,
    // and NO block chrome (no radius — the cell paints as empty paper).
    // UI-R14 #3 rolled the timeline back to plain ghost frames — the
    // SHEET alone carries the repeat-word convention.
    expect(timelineCellModel(tester, 'layer-r', 2).glyph, '○');
    expect(timelineCellModel(tester, 'layer-r', 3).glyph, '');
    expect(timelineCellModel(tester, 'layer-r', 4).glyph, '○');
    expect(
      timelineCellDecoration(tester, 'layer-r', 2).borderRadius,
      isNull,
      reason: 'ghost cells carry no block visual',
    );

    // Hold ghosts: ㅡ dashes through the whole span.
    for (var frame = 2; frame < 6; frame += 1) {
      expect(
        timelineCellModel(tester, 'layer-h', frame).glyph,
        'ㅡ',
        reason: 'frame $frame',
      );
      expect(timelineCellModel(tester, 'layer-h', frame).ghost, isTrue);
    }
    expect(timelineCellDecoration(tester, 'layer-h', 2).borderRadius, isNull);
  });

  testWidgets('a selection-scoped repeat pattern draws its span outline '
      '(UI-R10 #5)', (tester) async {
    final patterned = rederiveRunBehaviors(
      Layer(
        id: const LayerId('layer-p'),
        name: 'P',
        frames: [
          Frame(id: const FrameId('p1'), duration: 1, strokes: const []),
          Frame(id: const FrameId('p2'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('p1'), length: 1),
          1: const TimelineExposure.drawing(FrameId('p2'), length: 1),
        },
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('p2'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.repeat,
            patternAnchorFrameId: FrameId('p2'),
          ),
        ],
      ),
      cutFrameCount: 6,
    );
    await tester.pumpWidget(
      harness(layers: [patterned], runEdit: recordingCallbacks()),
    );

    final spans = timelineRowChromePatternSpans(tester, 'layer-p');
    expect(spans, hasLength(1));
    // The span wraps the pattern block [1,2) only (48px harness cells).
    expect(spans.single.width, 48);
    expect(spans.single.left, 48);
  });

  testWidgets('ghost cells dim and ghost blocks carry no edge grips', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [repeatedLayer()],
            activeLayerId: const LayerId('layer-r'),
            frameCursor: cursor,
            playbackFrameCount: 24,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            commaDrag: TimelineCommaDragCallbacks(
              onBegin: (_, _, _) => true,
              onUpdate: (_) {},
              onEnd: () {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    bool ghostAt(int index) =>
        timelineCellModel(tester, 'layer-r', index).ghost;
    expect(ghostAt(0), isFalse);
    expect(ghostAt(1), isFalse);
    expect(ghostAt(2), isTrue);
    expect(ghostAt(3), isTrue);
    expect(ghostAt(4), isTrue);
    expect(ghostAt(6), isFalse, reason: 'the tail stops at cut frame 6');

    // Grips: only the SOURCE block's two — the ghost blocks carry none.
    expect(timelineRowChromeIds(tester, 'layer-r'), [
      'block-edge-grip-start-layer-r-0',
      'block-edge-grip-end-layer-r-0',
    ]);
  });

  testWidgets('PEN-12 #6: with touch-timeline-scroll ON, a clean finger '
      'TAP on [+] still adds one cel', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final addCounts = <int>[];
    final begins = <(LayerId, int, bool)>[];
    await tester.pumpWidget(
      harness(
        layers: [plainLayer()],
        runEdit: recordingCallbacks(
          addCounts: addCounts,
          onAddBegin: (layerId, start, atEnd) =>
              begins.add((layerId, start, atEnd)),
        ),
      ),
    );

    await tester.tapAt(
      timelineRowChromeCenter(tester, 'layer-a', 'run-add-end-layer-a-f1'),
    );
    await tester.pumpAndSettle();
    expect(begins.single, (const LayerId('layer-a'), 0, true));
    expect(addCounts.last, 1, reason: 'a tap adds exactly one cel');
  });

  testWidgets('PEN-12 #3: a drag STARTING on the run property tag never '
      'scrolls the timeline', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    await tester.pumpWidget(
      harness(layers: [plainLayer()], runEdit: recordingCallbacks()),
    );

    List<double> scrollOffsets() => tester
        .stateList<ScrollableState>(
          find.byType(Scrollable, skipOffstage: false),
        )
        .map((state) => state.position.pixels)
        .toList();
    final before = scrollOffsets();

    const tagId = 'run-edge-tag-layer-a-f1-end';
    expect(timelineRowChromeIds(tester, 'layer-a'), contains(tagId));
    final gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', tagId),
      kind: PointerDeviceKind.touch,
    );
    for (var step = 0; step < 5; step += 1) {
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The press legitimately opened the mode flyout (its own scrollable
    // joins the tree) — dismiss it before comparing the GRID's offsets.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      scrollOffsets(),
      before,
      reason: 'the tag press owns the drag — the scroll must stay put',
    );
  });
}
