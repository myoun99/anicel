import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

/// 🗣️F-202 (유저 2026-09-27): 「띠가 스크롤되는거, 같은상황에서 뷰어패널
/// 스크롤바 조절할때도 밖의 다중패널 스크롤바 작동하던거같은데」 — and the
/// law it came to: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로
/// 안새게가 심플한 근본적인 규칙인거같다」.
///
/// The strip is a vertical scroller of panels (`workspace_rail.dart`'s
/// `rail-scroll-*`: the app's scroll behaviour, no framework scrollbars, hit
/// testing deferred to the panels). Inside a panel a scrollbar or a list is
/// pulled, and the pull's FIRST step goes ACROSS the inner thing's axis —
/// the jitter a hand makes — which is where the strip could take the drag on
/// its own axis. What starts inside stays inside: whatever the axis,
/// whatever the device.
void main() {
  // A claim that outlived a failed test would deafen the next one.
  tearDown(debugClearValueControlPointers);

  const devices = [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  ];

  /// The strip, with [panel] a little way down it and room to scroll.
  Future<ScrollController> inTheStrip(WidgetTester tester, Widget panel) async {
    final strip = ScrollController();
    addTearDown(strip.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: strip,
                hitTestBehavior: HitTestBehavior.deferToChild,
                child: Column(
                  children: [
                    const SizedBox(height: 100),
                    Center(child: panel),
                    const SizedBox(height: 1200),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return strip;
  }

  /// A press at [at], a first step ACROSS [axis], a pull along it in three
  /// steps, and one more step across.
  ///
  /// ⚠️The LAST step is what makes a leak visible: a drag is started by the
  /// move that wins it and does not apply that move, so a strip that won on
  /// the first step and then saw only the pull along [axis] would stay put
  /// while the inner thing never moved (measured, 09-27). The pull is split
  /// for the same reason from the other side: an inner thing that wins on
  /// the first step has to see moves AFTER it to show that it took them.
  Future<void> pull(
    WidgetTester tester,
    Offset at,
    Axis axis,
    PointerDeviceKind kind, {
    double reach = 60,
  }) async {
    final across = axis == Axis.horizontal
        ? const Offset(0, -24)
        : const Offset(-24, 0);
    final step = axis == Axis.horizontal
        ? Offset(reach / 3, 0)
        : Offset(0, reach / 3);
    final gesture = await tester.startGesture(at, kind: kind);
    await tester.pump();
    await gesture.moveBy(across);
    await tester.pump();
    for (var i = 0; i < 3; i += 1) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.moveBy(across);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('a scrollbar in a panel', () {
    /// An [AppScrollbar] over three viewports of content, its offset kept.
    Widget scrollbar(Axis axis, List<double> offsets) {
      var offset = 0.0;
      final horizontal = axis == Axis.horizontal;
      return StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: horizontal ? 300 : 16,
          height: horizontal ? 16 : 300,
          child: AppScrollbar(
            axis: axis,
            offset: offset,
            viewportExtent: 300,
            contentExtent: 900,
            thumbKey: const ValueKey<String>('thumb'),
            onOffsetChanged: (next) => setState(() {
              offset = next;
              offsets.add(next);
            }),
          ),
        ),
      );
    }

    for (final axis in Axis.values) {
      for (final kind in devices) {
        testWidgets('the ${axis.name} thumb, pulled with a ${kind.name}', (
          tester,
        ) async {
          final offsets = <double>[];
          final strip = await inTheStrip(tester, scrollbar(axis, offsets));
          final thumb = tester.getCenter(
            find.byKey(const ValueKey<String>('thumb')),
          );
          await pull(tester, thumb, axis, kind);
          expect(
            strip.offset,
            0,
            reason: 'the pull started on the thumb, so the strip gets nothing',
          );
          expect(offsets, isNotEmpty, reason: 'and the thumb took it');
        });
      }
    }

    // The lane's jump rides its own tap: the grip only takes a MOVING
    // pointer, and inside a scroller a press that never moves is no drag's.
    // (Alone in an arena the grip is handed the press at once and would
    // jump by itself — which is why this is measured inside the strip.)
    for (final axis in Axis.values) {
      testWidgets('a tap on the ${axis.name} lane jumps, inside the strip', (
        tester,
      ) async {
        final offsets = <double>[];
        await inTheStrip(tester, scrollbar(axis, offsets));
        final lane = tester.getTopLeft(find.byType(AppScrollbar));
        await tester.tapAt(
          lane +
              (axis == Axis.horizontal
                  ? const Offset(250, 8)
                  : const Offset(8, 250)),
        );
        await tester.pumpAndSettle();
        // A 100px thumb centred on 250 of a 300px lane: its start at 200 of
        // 200 to travel, the far end of 600 to scroll.
        expect(offsets, [600]);
      });
    }
  });

  group("the viewer panel's panbars", () {
    // 🗣️The report itself: 「뷰어패널 스크롤바 조절할때도 밖의 다중패널
    // 스크롤바 작동하던거같은데」. The viewer is the canvas panel with a
    // one-finger pan, mounted the way the H24 suite mounts it.
    for (final axis in Axis.values) {
      for (final kind in devices) {
        testWidgets('the ${axis.name} panbar, pulled with a ${kind.name}', (
          tester,
        ) async {
          final emitted = <CanvasViewport>[];
          final strip = await inTheStrip(
            tester,
            SizedBox(
              width: 400,
              height: 300,
              child: BrushCanvasPanel(
                coordinator: null,
                availableFrameKeys: const [],
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                canvasSize: const CanvasSize(width: 600, height: 800),
                viewport: CanvasViewport(zoom: 2),
                onViewportChanged: emitted.add,
                allowViewRotation: false,
                toolCursorsEnabled: false,
                oneFingerAction: CanvasTouchDragAction.navigate,
                contentOverride: (context, viewport) => const SizedBox.expand(),
              ),
            ),
          );
          final bar = find.byKey(
            ValueKey<String>(
              axis == Axis.horizontal
                  ? 'canvas-viewport-horizontal-scrollbar'
                  : 'canvas-viewport-vertical-scrollbar',
            ),
          );
          await pull(tester, tester.getCenter(bar), axis, kind);
          expect(
            strip.offset,
            0,
            reason: 'the pull started on the panbar, so the strip gets nothing',
          );
          expect(emitted, isNotEmpty, reason: 'and the panbar took it');
        });
      }
    }
  });

  group('a list in a panel', () {
    const listKey = ValueKey<String>('list');

    /// A list of twenty 100px tiles running [axis], in the strip, or in a
    /// scroller with nothing to scroll when [stripScrolls] is false.
    Future<({ScrollController strip, ScrollController list})> listIn(
      WidgetTester tester,
      Axis axis, {
      bool stripScrolls = true,
      VoidCallback? onTileTap,
    }) async {
      final list = ScrollController();
      addTearDown(list.dispose);
      final horizontal = axis == Axis.horizontal;
      Widget tile(int i) => SizedBox.square(
        dimension: 100,
        child: GestureDetector(onTap: onTileTap, child: Text('$i')),
      );
      final panel = SizedBox(
        key: listKey,
        width: horizontal ? 300 : 120,
        height: horizontal ? 120 : 300,
        child: ListView(
          controller: list,
          scrollDirection: axis,
          children: [for (var i = 0; i < 20; i += 1) tile(i)],
        ),
      );
      if (stripScrolls) {
        return (strip: await inTheStrip(tester, panel), list: list);
      }
      final strip = ScrollController();
      addTearDown(strip.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: SingleChildScrollView(
              controller: strip,
              child: Center(child: panel),
            ),
          ),
        ),
      );
      return (strip: strip, list: list);
    }

    Offset middleOf(WidgetTester tester) =>
        tester.getCenter(find.byKey(listKey));

    for (final axis in Axis.values) {
      for (final kind in devices) {
        testWidgets('a ${axis.name} list, pulled with a ${kind.name}', (
          tester,
        ) async {
          final h = await listIn(tester, axis);
          // Against the list's own direction, so a list that takes the pull
          // scrolls forward rather than into its start.
          await pull(tester, middleOf(tester), axis, kind, reach: -60);
          expect(
            h.strip.offset,
            0,
            reason: 'the pull started in the list, so the strip gets nothing',
          );
          // Sideways, the hold wins the first step (across, past every
          // device's slop) and all three steps along land: 60. Down the
          // strip's own way nothing takes the step across, the list's own
          // recogniser wins the first step along, and the other two land.
          expect(
            h.list.offset,
            axis == Axis.horizontal ? 60 : 40,
            reason: 'and the list took it, along its own axis only',
          );
        });
      }
    }

    testWidgets('with nothing to race, nothing is held', (tester) async {
      final h = await listIn(tester, Axis.horizontal, stripScrolls: false);
      expect(
        h.strip.position.maxScrollExtent,
        0,
        reason: '⛔fixture premise: the scroller around it has nothing to do',
      );
      // Alone in the arena, the list is handed the press the moment it
      // lands, so it follows from the first pixel. A hold beside it would
      // make it wait for its slop (18px for a finger): these three short
      // steps would land one, not three.
      final gesture = await tester.startGesture(middleOf(tester));
      for (var i = 0; i < 3; i += 1) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.list.offset, 30, reason: 'the list answers as it always has');
    });

    for (final kind in devices) {
      testWidgets('a ${kind.name} tap that wobbles is still a tap', (
        tester,
      ) async {
        var taps = 0;
        await listIn(tester, Axis.horizontal, onTileTap: () => taps += 1);
        final gesture = await tester.startGesture(
          middleOf(tester),
          kind: kind,
        );
        await gesture.moveBy(const Offset(0, 0.5));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          taps,
          1,
          reason: 'the hold waits for the slop, as a scroll does',
        );
      });
    }

    testWidgets('a flick along a held list coasts on', (tester) async {
      final h = await listIn(tester, Axis.horizontal);
      final gesture = await tester.startGesture(middleOf(tester));
      var at = Duration.zero;
      await gesture.moveBy(const Offset(0, -24), timeStamp: at);
      for (var i = 0; i < 5; i += 1) {
        at += const Duration(milliseconds: 16);
        await gesture.moveBy(const Offset(-40, 0), timeStamp: at);
      }
      await gesture.up(timeStamp: at);
      await tester.pumpAndSettle();
      expect(
        h.list.offset,
        greaterThan(200),
        reason: 'the five steps along land (200) and the flick carries on',
      );
    });

    testWidgets('a list that goes away under a held press takes nothing '
        'down with it', (tester) async {
      await listIn(tester, Axis.horizontal);
      final gesture = await tester.startGesture(middleOf(tester));
      await tester.pumpWidget(const SizedBox());
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('a squeezed panel', () {
    // The dock's two overflow scrollers are ONE surface (F-103,
    // `scrollTogether`): a panel under its floor on both axes goes whichever
    // way it is pulled. The inner of the pair is not a scroller inside the
    // outer, so nothing here holds a press against the other.
    const content = ValueKey<String>('squeezed');

    Future<Map<Axis, ScrollPosition>> squeezed(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 150,
                child: EditorPanelTabs(
                  tabs: <EditorPanelTab>[
                    EditorPanelTab(
                      id: 'squeezed',
                      label: 'Squeezed',
                      icon: Icons.circle,
                      minContentWidth: 400,
                      minContentHeight: 250,
                      builder: (context) => const SizedBox.expand(key: content),
                    ),
                  ],
                  activeTabId: 'squeezed',
                  onTabSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return {
        for (final scroller in tester.stateList<ScrollableState>(
          find.ancestor(
            of: find.byKey(content),
            matching: find.byType(Scrollable),
          ),
        ))
          scroller.widget.axis: scroller.position,
      };
    }

    for (final axis in Axis.values) {
      for (final kind in devices) {
        testWidgets('pulled ${axis.name}ly with a ${kind.name}, it goes', (
          tester,
        ) async {
          final positions = await squeezed(tester);
          expect(
            positions.values.map((position) => position.maxScrollExtent),
            everyElement(greaterThan(0)),
            reason: '⛔fixture premise: under the floor on both axes',
          );
          final step = axis == Axis.horizontal
              ? const Offset(-30, 0)
              : const Offset(0, -30);
          final gesture = await tester.startGesture(
            tester.getTopLeft(find.byType(EditorPanelTabs)) +
                const Offset(100, 100),
            kind: kind,
          );
          for (var i = 0; i < 3; i += 1) {
            await gesture.moveBy(step);
            await tester.pump();
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(positions[axis]!.pixels, greaterThan(0));
        });
      }
    }
  });

  group('the x-sheet', () {
    // The product's touch: a finger scrolls the timeline sheets, and their
    // edit gestures let it go (1핑거 드로잉 off — `AppInputSettings`).
    setUp(() => AppInput.settings.value = const AppInputSettings());
    tearDown(
      () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
    );

    ScrollController controllerOf(WidgetTester tester, String key) => tester
        .widget<SingleChildScrollView>(find.byKey(ValueKey<String>(key)))
        .controller!;

    testWidgets('pulled sideways on its frames, its layers go — the layers '
        'and the frames are ONE surface', (tester) async {
      await tester.binding.setSurfaceSize(const Size(560, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: TimelinePanel(
              layers: [
                for (var i = 0; i < 30; i += 1)
                  Layer(
                    id: LayerId('draw-$i'),
                    name: 'draw-$i',
                    kind: LayerKind.animation,
                    frames: [
                      Frame(
                        id: FrameId('draw-$i-cel'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: const {},
                  ),
              ],
              activeLayerId: const LayerId('draw-0'),
              frameCursor: cursor,
              playbackFrameCount: 400,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              orientation: TimelineOrientation.vertical,
              onOrientationChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layers = controllerOf(tester, 'xsheet-layer-horizontal-viewport');
      final frames = controllerOf(tester, 'xsheet-frame-vertical-viewport');
      expect(
        [layers.position.maxScrollExtent, frames.position.maxScrollExtent],
        everyElement(greaterThan(0)),
        reason: '⛔fixture premise: the sheet scrolls both ways',
      );

      await tester.dragFrom(
        tester.getTopLeft(
              find.byKey(
                const ValueKey<String>('xsheet-frame-vertical-viewport'),
              ),
            ) +
            const Offset(60, 60),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();

      expect(layers.offset, greaterThan(0));
    });
  });
}
