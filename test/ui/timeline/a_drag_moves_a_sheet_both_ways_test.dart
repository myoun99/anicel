import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️F-351 (유저 2026-10-12): 「스페이스바로 타임라인쪽 조작하면 가로/세로
/// 스크롤 통합해서 캔버스 조작하듯이 팬 되는데, 법 통일해서 터치로 해당영역
/// 조작시에도 가로/세로 같이 하도록」.
///
/// A sheet is one surface scrolled two ways, and a drag on it moves it both
/// ways at once — each axis by its own part of the hand's travel, as Space
/// moves it — where each axis used to take a drag of its own and the one
/// the hand moved along first took all of it.
///
/// 🗣️And its layer area pans itself (유저 2026-10-16): 「레이어 영역을 잡아도
/// 프레임쪽이 팬 작동되는데 레이어쪽을 잡으면 레이어영역이 팬 작동하도록」.
///
/// 🗣️And two fingers zoom it (F-506, 유저 2026-10-29): 「타임라인 프레임영역.
/// 두손가락 터치로 타임라인줌변경도 가능하게」 — as the canvas's own setting
/// for two fingers, 「내비게이트」, pans and zooms the canvas.
void main() {
  /// The heads of the range selects the timeline's and the x-sheet's cells
  /// made — their edit drag.
  final selects = <int>[];

  // The product's touch: a finger scrolls the sheets, and their edit
  // gestures let it go (1핑거 드로잉 off).
  setUp(() {
    AppInput.settings.value = const AppInputSettings();
    selects.clear();
  });
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    CanvasViewHold.held.value = null;
    CanvasTouchContacts.reset();
  });

  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  /// The timeline or the x-sheet: sixty rows — or [rows] — four hundred
  /// frames, more of both than a wide panel shows; its layer area seen
  /// through [rail], its frames at [zoom], which its panel writes, and its
  /// cells range-selected into [selects].
  Widget timeline(
    TimelineOrientation orientation,
    LayerRailExtent rail,
    ValueNotifier<double> zoom, {
    int? rows,
  }) {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(selection.dispose);
    return TimelinePanel(
      rangeHooks: TimelineFrameRangeHooks(
        selection: selection,
        onSelectUpdate:
            (
              layerId,
              anchorIndex,
              headIndex, {
              headLayerId,
              spanRows = const [],
            }) => selects.add(headIndex),
        onClear: () {},
        move: TimelineRangeMoveCallbacks(
          holds: (_) => false,
          onBegin: (_) => false,
          onUpdate: ({required frameDelta, targetLayerId}) {},
          onEnd: () {},
          onCancel: () {},
        ),
      ),
      timelineRailExtent: rail,
      xsheetRailExtent: rail,
      layers: [for (var i = 0; i < (rows ?? 60); i += 1) drawing('draw-$i')],
      activeLayerId: const LayerId('draw-0'),
      frameCursor: cursor,
      playbackFrameCount: 400,
      exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      onAddLayer: () {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
      orientation: orientation,
      onOrientationChanged: (_) {},
      pixelsPerFrame: zoom.value,
      onPixelsPerFrameChanged: (value) => zoom.value = value,
    );
  }

  /// The conte panel: thirty tracks — or [rows] — the last of them four
  /// hundred frames long and the rest short, so the cells are mostly empty
  /// lanes; its layer area seen through [rail], its frames at [zoom], which
  /// its host writes.
  Widget conte(
    LayerRailExtent rail,
    ValueNotifier<double> zoom, {
    int? rows,
  }) => StoryboardPanel(
    railExtent: rail,
    pixelsPerFrame: zoom.value,
    onPixelsPerFrameChanged: (value) => zoom.value = value,
    project: Project(
      id: const ProjectId('a-drag-moves-a-sheet'),
      name: 'a drag moves a sheet',
      createdAt: DateTime.utc(2026, 10, 14),
      tracks: [
        for (var i = 0; i < (rows ?? 30); i += 1)
          Track(
            id: TrackId('track-$i'),
            name: 'V${i + 1}',
            cuts: [
              Cut(
                id: CutId('cut-$i'),
                name: 'cut-$i',
                duration: i == (rows ?? 30) - 1 ? 400 : 12,
                canvasSize: const CanvasSize(width: 1280, height: 720),
                layers: [drawing('draw-$i')],
              ),
            ],
          ),
      ],
    ),
    activeCutId: const CutId('cut-0'),
  );

  /// Every sheet the app scrolls two ways.
  final sheets = <_Sheet>[
    (
      name: 'timeline',
      panel: (rail, rows, zoom) =>
          timeline(TimelineOrientation.horizontal, rail, zoom, rows: rows),
      outer: 'timeline-vertical-scroll-viewport',
      inner: 'timeline-frame-scroll-viewport',
      aLayerName: find
          .namedWhere((name) => name.startsWith('timeline-layer-name-'))
          .first,
    ),
    (
      name: 'x-sheet',
      panel: (rail, rows, zoom) =>
          timeline(TimelineOrientation.vertical, rail, zoom, rows: rows),
      outer: 'xsheet-layer-horizontal-viewport',
      inner: 'xsheet-frame-vertical-viewport',
      aLayerName: find
          .namedWhere((name) => name.startsWith('xsheet-layer-name-'))
          .first,
    ),
    (
      name: 'conte panel',
      panel: (rail, rows, zoom) => conte(rail, zoom, rows: rows),
      outer: 'storyboard-vertical-viewport',
      inner: 'storyboard-timeline-horizontal-viewport',
      aLayerName: find
          .byWidgetPredicate(
            (widget) => switch (widget.key) {
              ValueKey<String>(:final value) => value.startsWith(
                'storyboard-track-label-track-',
              ),
              _ => false,
            },
          )
          .first,
    ),
  ];

  for (final sheet in sheets) {
    /// The zoom the sheet's frames are laid out at — the app's opening
    /// zoom when it is pumped — and its panel's writes.
    late ValueNotifier<double> zoom;

    /// The sheet's panel squeezed into its floor ([OverflowScrollers]), the
    /// floor scrolling both ways — so a pull the sheet does not take has
    /// somewhere else to go.
    ///
    /// ⚠️Unsqueezed, nothing else on the screen asks for a pull: once the
    /// cells' taps let go, the sheet's drag is all that is left and wins by
    /// default. What decides who takes a pull — the slop, each axis's own —
    /// and what stops a coast under a press went unasked, and four mutants
    /// lived (F-351, 2026-10-14).
    Future<void> pumpSheet(
      WidgetTester tester, {
      LayerRailExtent? rail,
      int? rows,
    }) async {
      // Wide enough for the cells beside the rail to be a panel's worth.
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final window = rail ?? LayerRailExtent();
      if (rail == null) {
        addTearDown(window.dispose);
      }
      zoom = ValueNotifier(TimelineZoomLimits.referencePixelsPerFrame);
      addTearDown(zoom.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: OverflowScrollers(
              minWidth: 1000,
              minHeight: 700,
              child: ValueListenableBuilder(
                valueListenable: zoom,
                builder: (context, _, _) => sheet.panel(window, rows, zoom),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ScrollPosition positionOf(WidgetTester tester, String key) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    /// Where the sheet's two axes stand, horizontal first.
    Offset standing(WidgetTester tester) {
      final positions = [
        positionOf(tester, sheet.outer),
        positionOf(tester, sheet.inner),
      ];
      double along(Axis axis) =>
          positions.firstWhere((position) => position.axis == axis).pixels;
      return Offset(along(Axis.horizontal), along(Axis.vertical));
    }

    /// Where the scrollers around the sheet stand — the floor's.
    List<ScrollPosition> theFloor(WidgetTester tester) => [
      for (final scroller in tester.stateList<ScrollableState>(
        find.ancestor(
          of: find.byKey(ValueKey<String>(sheet.outer)),
          matching: find.byType(Scrollable),
        ),
      ))
        scroller.position,
    ];

    /// A point on the sheet's cells: the middle of what shows of its inner
    /// scroll view.
    Offset onTheCells(WidgetTester tester) => tester
        .getRect(find.byKey(ValueKey<String>(sheet.inner)))
        .intersect(tester.getRect(find.byKey(ValueKey<String>(sheet.outer))))
        .intersect(tester.getRect(find.byType(OverflowScrollers)))
        .center;

    /// [fingers] land together [from] the cells — or where it says — and
    /// travel ten steps of [step].
    Future<void> drag(
      WidgetTester tester, {
      Offset step = const Offset(-20, -15),
      int fingers = 1,
      PointerDeviceKind kind = PointerDeviceKind.touch,
      Offset? from,
    }) async {
      final at = from ?? onTheCells(tester);
      final gestures = [
        for (var finger = 0; finger < fingers; finger += 1)
          await tester.startGesture(
            at + Offset(finger * 30.0, 0),
            kind: kind,
            pointer: 10 + finger,
          ),
      ];
      for (var i = 0; i < 10; i += 1) {
        for (final gesture in gestures) {
          await gesture.moveBy(step);
        }
        await tester.pump();
      }
      for (final gesture in gestures) {
        await gesture.up();
      }
      await tester.pumpAndSettle();
    }

    /// The nine steps after the first: the first is the one the drag starts
    /// on — where the finger stood once the drag was known.
    Offset travelOf(Offset step) => -step * 9;

    group('the ${sheet.name}', () {
      for (final (first, step) in const [
        ('sideways', Offset(-20, -15)),
        ('upwards', Offset(-15, -20)),
      ]) {
        testWidgets('🎯a finger pulled on the slant moves it both ways at '
            'once — each axis by its own part of the pull, from the step it '
            'crossed the slop on ($first first)', (tester) async {
          await pumpSheet(tester);
          expect(
            [
              positionOf(tester, sheet.outer).maxScrollExtent,
              positionOf(tester, sheet.inner).maxScrollExtent,
            ],
            everyElement(greaterThan(200)),
            reason: '⛔fixture premise: the sheet scrolls both ways',
          );
          expect(
            [for (final position in theFloor(tester)) position.maxScrollExtent],
            [greaterThan(0), greaterThan(0)],
            reason: '⛔fixture premise: so does the floor, and nothing else '
                'is around the sheet',
          );

          await drag(tester, step: step);

          expect(standing(tester).dx, closeTo(travelOf(step).dx, 0.5));
          expect(standing(tester).dy, closeTo(travelOf(step).dy, 0.5));
          expect(
            [for (final position in theFloor(tester)) position.pixels],
            everyElement(0),
            reason: 'F-202: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로 '
                '안새게」',
          );
        });
      }

      testWidgets('…and still once the window is on a screen of another '
          'density — its axes are made anew there, as drag-less as before', (
        tester,
      ) async {
        await pumpSheet(tester);
        tester.view.devicePixelRatio += 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpAndSettle();

        await drag(tester);

        final travel = travelOf(const Offset(-20, -15));
        expect(standing(tester).dx, closeTo(travel.dx, 0.5));
        expect(standing(tester).dy, closeTo(travel.dy, 0.5));
      });

      testWidgets('a press on it while it coasts stops it where it is', (
        tester,
      ) async {
        await pumpSheet(tester);
        // A point on the screen: the cells under it move, it does not.
        final cells = onTheCells(tester);
        await tester.flingFrom(cells, const Offset(-160, -120), 2400);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final coasting = standing(tester);
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          [standing(tester).dx, standing(tester).dy],
          [greaterThan(coasting.dx), greaterThan(coasting.dy)],
          reason: '⛔premise: it coasts both ways',
        );

        final press = await tester.startGesture(cells);
        await tester.pump();
        final caught = standing(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(standing(tester), caught);
        await press.up();
        await tester.pumpAndSettle();
      });

      testWidgets('two fingers move it both ways too — and, going together, '
          'zoom it not at all', (tester) async {
        await pumpSheet(tester);
        await drag(tester, fingers: 2);
        final at = standing(tester);
        expect([at.dx, at.dy], everyElement(greaterThan(0)));
        expect(zoom.value, TimelineZoomLimits.referencePixelsPerFrame);
      });

      testWidgets('so does a trackpad — the sheet\'s axes take no drag of '
          'their own, so this is the one that has to', (tester) async {
        await pumpSheet(tester);
        await drag(tester, kind: PointerDeviceKind.trackpad);
        final at = standing(tester);
        expect([at.dx, at.dy], everyElement(greaterThan(0)));
      });

      testWidgets('a flick on the slant coasts on both ways', (tester) async {
        await pumpSheet(tester);
        await tester.flingFrom(
          onTheCells(tester),
          const Offset(-160, -120),
          2400,
        );
        final released = standing(tester);
        await tester.pumpAndSettle();
        final rested = standing(tester);
        expect(rested.dx, greaterThan(released.dx));
        expect(rested.dy, greaterThan(released.dy));
      });

      testWidgets('⛔one finger set to 「없음」 on the canvas moves it neither '
          'way (R26-rest-Q2)', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchDragOneFinger: CanvasTouchDragAction.none,
        );
        await pumpSheet(tester);
        await drag(tester);
        expect(standing(tester), Offset.zero);
      });

      /// The layer area's window, through which its layers show.
      Finder layerAreaWindow() => find
          .ancestor(
            of: sheet.aLayerName,
            matching: find.byType(LayerRailWindow),
          )
          .first;

      /// The sheet with its layer area's window narrowed under the area's
      /// natural extent, so the window has somewhere to be pushed.
      Future<LayerRailExtent> pumpNarrowed(WidgetTester tester) async {
        final rail = LayerRailExtent();
        addTearDown(rail.dispose);
        await pumpSheet(tester, rail: rail);
        rail.value =
            extentAlong(
              tester.widget<LayerRailWindow>(layerAreaWindow()).axis,
              tester.getSize(layerAreaWindow()),
            ) -
            40;
        await tester.pumpAndSettle();
        return rail;
      }

      Future<void> holdTheView(WidgetTester tester) async {
        CanvasViewHold.held.value = ViewHold.pan;
        await tester.pump();
      }

      for (final (hand, kind, space) in const [
        ('a finger', PointerDeviceKind.touch, false),
        ('a trackpad', PointerDeviceKind.trackpad, false),
        ('Space\'s hand', PointerDeviceKind.mouse, true),
      ]) {
        testWidgets('🚨$hand pulled on the layer area moves the layer area — '
            'its layers and its own window — and leaves the frames where '
            'they are', (tester) async {
          final rail = await pumpNarrowed(tester);
          if (space) {
            await holdTheView(tester);
          }

          // A layer's name: on the layer area, and no control's.
          await drag(
            tester,
            from: tester.getCenter(sheet.aLayerName),
            kind: kind,
          );

          expect(
            positionOf(tester, sheet.inner).pixels,
            0,
            reason: '「레이어쪽을 잡으면 레이어영역이 팬」 — the frames stay',
          );
          expect(
            positionOf(tester, sheet.outer).pixels,
            greaterThan(0),
            reason: 'the layers go with the hand',
          );
          expect(
            rail.offset.value,
            greaterThan(0),
            reason: 'and so does the layer area\'s own window',
          );
        });
      }

      for (final (hand, kind, space) in const [
        ('a finger', PointerDeviceKind.touch, false),
        ('Space\'s hand', PointerDeviceKind.mouse, true),
      ]) {
        testWidgets('$hand pulled on the layer area while the sheet coasts '
            'stops it — the frames too — and then moves the layer area: what '
            'a coasting sheet shows is out of the hit test until the press '
            'stops it (PEN-9)', (tester) async {
          final rail = await pumpNarrowed(tester);
          await tester.flingFrom(
            onTheCells(tester),
            const Offset(-160, -120),
            2400,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          if (space) {
            await holdTheView(tester);
          }

          // The middle of what shows of the layer area — its layers have
          // moved on under any one name.
          final press = await tester.startGesture(
            tester
                .getRect(layerAreaWindow())
                .intersect(tester.getRect(find.byKey(ValueKey(sheet.outer))))
                .intersect(tester.getRect(find.byType(OverflowScrollers)))
                .center,
            kind: kind,
          );
          await tester.pump();
          final caught = positionOf(tester, sheet.inner).pixels;
          for (var i = 0; i < 10; i += 1) {
            await press.moveBy(const Offset(-20, -15));
            await tester.pump();
          }
          await press.up();
          await tester.pumpAndSettle();

          expect(
            positionOf(tester, sheet.inner).pixels,
            caught,
            reason: 'the press stopped the frames, and the pull left them',
          );
          expect(rail.offset.value, greaterThan(0));
        });
      }

      testWidgets('⛔a pull on the layer area where only the frames could '
          'move goes nowhere — not out to the scroller around the sheet '
          '(F-202)', (tester) async {
        await pumpSheet(tester, rows: 3);
        expect(
          [
            positionOf(tester, sheet.outer).maxScrollExtent,
            positionOf(tester, sheet.inner).maxScrollExtent,
          ],
          [0, greaterThan(200)],
          reason: '⛔fixture premise: the layers fit, the frames do not',
        );

        await drag(tester, from: tester.getCenter(sheet.aLayerName));

        expect(standing(tester), Offset.zero);
        expect(
          positionOf(tester, sheet.inner).activity,
          isA<IdleScrollActivity>(),
          reason: 'the press held the frames, and letting go lets them go',
        );
        expect(
          [for (final position in theFloor(tester)) position.pixels],
          everyElement(0),
          reason: 'F-202: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로 '
              '안새게」',
        );
      });

      // 🗣️F-447-Q1 (유저 2026-10-23): 「그 영역 자신을 — 팬(F-351)과 같은
      // 법」 — a wheel moves the layer area it turns over as a pull there
      // does: its window along the window, its layers the other way.
      // ↩️F-159 (09-18) took every notch over the x-sheet's headers for its
      // layers, the timeline's way; F-447 asked again (「x시트의 레이어영역의
      // 휠조작이 작동안함 … 프레임 영역이랑 법 통일」).

      /// One notch of a mouse wheel at [at], turned with Shift held where
      /// [shift] says — which turns it to the other axis, as a scroll view
      /// reads it.
      Future<void> wheel(
        WidgetTester tester,
        Offset at, {
        required bool shift,
      }) async {
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(at));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
      }

      /// Whether a notch along the layer area's window is turned with Shift:
      /// the wheel's own notch goes down.
      bool shiftAlongTheWindow(WidgetTester tester) =>
          tester.widget<LayerRailWindow>(layerAreaWindow()).axis ==
          Axis.horizontal;

      testWidgets('🚨a wheel over the layer area, along its window, pushes '
          'the window — and moves neither its layers nor the frames', (
        tester,
      ) async {
        final rail = await pumpNarrowed(tester);

        await wheel(
          tester,
          tester.getCenter(sheet.aLayerName),
          shift: shiftAlongTheWindow(tester),
        );

        expect(rail.offset.value, greaterThan(0), reason: '「그 영역 자신을」');
        expect(standing(tester), Offset.zero);
        expect(
          [for (final position in theFloor(tester)) position.pixels],
          everyElement(0),
        );
      });

      testWidgets('…and across its window the wheel is its layers\' — the '
          'notch that moves them over the cells', (tester) async {
        final rail = await pumpNarrowed(tester);

        await wheel(
          tester,
          tester.getCenter(sheet.aLayerName),
          shift: !shiftAlongTheWindow(tester),
        );

        expect(rail.offset.value, 0);
        expect(positionOf(tester, sheet.outer).pixels, greaterThan(0));
        expect(positionOf(tester, sheet.inner).pixels, 0);
      });

      testWidgets('⛔Shift turns a mouse\'s wheel alone — a trackpad\'s '
          'notch goes the way it goes, as the scroll views read it', (
        tester,
      ) async {
        final rail = await pumpNarrowed(tester);
        final windowGoesDown = !shiftAlongTheWindow(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final pad = TestPointer(1, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(
          pad.hover(tester.getCenter(sheet.aLayerName)),
        );
        await tester.sendEventToBinding(pad.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

        expect(
          [rail.offset.value > 0, positionOf(tester, sheet.outer).pixels > 0],
          [windowGoesDown, !windowGoesDown],
          reason: 'a notch down: the window where it slides down, else the '
              'layers',
        );
      });

      // ↩️F-159's listener took every notch over the x-sheet's headers and
      // moved the layers by its downward part — a sideways one moved them
      // by nothing, and nothing else had it.
      testWidgets('⛔a notch that comes sideways — a tilting wheel\'s — goes '
          'the way it comes, no Shift held', (tester) async {
        final rail = await pumpNarrowed(tester);
        final windowGoesAcross = shiftAlongTheWindow(tester);

        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(sheet.aLayerName)),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(120, 0)));
        await tester.pumpAndSettle();

        expect(
          [rail.offset.value > 0, positionOf(tester, sheet.outer).pixels > 0],
          [windowGoesAcross, !windowGoesAcross],
          reason: 'a notch across: the window where it slides across, else '
              'the layers',
        );
      });

      testWidgets('⛔where its window has nowhere to go, a notch along it '
          'moves nothing — not out to the scroller around the sheet', (
        tester,
      ) async {
        await pumpSheet(tester);

        await wheel(
          tester,
          tester.getCenter(sheet.aLayerName),
          shift: shiftAlongTheWindow(tester),
        );

        expect(standing(tester), Offset.zero);
        expect(
          [for (final position in theFloor(tester)) position.pixels],
          everyElement(0),
          reason: 'F-202 — as a pull there',
        );
      });

      testWidgets('⛔a wheel over the cells leaves the layer area\'s window '
          'where it stands, either way it is turned', (tester) async {
        final rail = await pumpNarrowed(tester);

        for (final shift in [false, true]) {
          await wheel(tester, onTheCells(tester), shift: shift);
        }

        expect(rail.offset.value, 0);
        expect(
          [standing(tester).dx, standing(tester).dy],
          everyElement(greaterThan(0)),
          reason: '⛔전제: the cells took both notches',
        );
      });

      // 🗣️F-506: two fingers on the frames do what 「내비게이트」 does on the
      // canvas — their spread zooms, their middle pans.

      /// Two fingers land [apart] across [at] — the cells' middle unless it
      /// says — each [by] further from the other in ten steps, and are let
      /// go; the zoom they leave, against the one they found. The first is
      /// a [first] — a finger unless it says.
      Future<double> pinch(
        WidgetTester tester, {
        Offset? at,
        double apart = 80,
        double by = 20,
        PointerDeviceKind first = PointerDeviceKind.touch,
      }) async {
        final found = zoom.value;
        final middle = at ?? onTheCells(tester);
        final fingers = [
          await tester.startGesture(
            middle - Offset(apart / 2, 0),
            kind: first,
            pointer: 20,
          ),
          await tester.startGesture(
            middle + Offset(apart / 2, 0),
            kind: PointerDeviceKind.touch,
            pointer: 21,
          ),
        ];
        for (var i = 0; i < 10; i += 1) {
          await fingers[0].moveBy(Offset(-by / 10, 0));
          await fingers[1].moveBy(Offset(by / 10, 0));
          await tester.pump();
        }
        for (final finger in fingers) {
          await finger.up();
        }
        await tester.pumpAndSettle();
        return zoom.value / found;
      }

      testWidgets('🎯two fingers spreading on its cells zoom its frames in, '
          'and closing zoom them out — by how far they spread (F-506)', (
        tester,
      ) async {
        await pumpSheet(tester);

        expect(await pinch(tester, by: 20), closeTo(1.5, 0.005));
        expect(await pinch(tester, by: -20), closeTo(0.5, 0.005));
      });

      testWidgets('two fingers let go coast on neither way — as the canvas\'s '
          '「내비게이트」 does not', (tester) async {
        await pumpSheet(tester);
        final fingers = [
          for (final (pointer, x) in const [(20, -40.0), (21, 40.0)])
            await tester.startGesture(
              onTheCells(tester) + Offset(x, 0),
              kind: PointerDeviceKind.touch,
              pointer: pointer,
            ),
        ];
        for (var i = 0; i < 5; i += 1) {
          for (final finger in fingers) {
            await finger.moveBy(const Offset(-40, -30));
          }
          await tester.pump(const Duration(milliseconds: 8));
        }
        for (final finger in fingers) {
          await finger.up();
        }
        final released = standing(tester);
        await tester.pumpAndSettle();

        expect(
          [released.dx, released.dy],
          everyElement(greaterThan(0)),
          reason: '⛔premise: the fingers moved it',
        );
        expect(standing(tester), released);
      });

      testWidgets('a finger lifted mid-pinch leaves the other moving it from '
          'where it stands', (tester) async {
        await pumpSheet(tester);
        final cells = onTheCells(tester);
        final kept = await tester.startGesture(
          cells - const Offset(40, 0),
          kind: PointerDeviceKind.touch,
          pointer: 20,
        );
        final lifted = await tester.startGesture(
          cells + const Offset(40, 0),
          kind: PointerDeviceKind.touch,
          pointer: 21,
        );
        await tester.pump();
        await lifted.up();
        await tester.pump();
        final from = standing(tester);

        for (var i = 0; i < 5; i += 1) {
          await kept.moveBy(const Offset(-10, -8));
          await tester.pump();
        }
        await kept.up();
        await tester.pumpAndSettle();

        expect(standing(tester) - from, const Offset(50, 40));
      });

      testWidgets('⛔two fingers on its layer area zoom nothing — they pull '
          'it as one finger does', (tester) async {
        await pumpSheet(tester);

        expect(
          await pinch(
            tester,
            at: tester.getCenter(sheet.aLayerName),
            apart: 8,
            by: 4,
          ),
          1,
        );
      });

      testWidgets('⛔two fingers set on the canvas to anything but '
          '「내비게이트」 zoom nothing (R26 #34)', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          touchDragTwoFingers: CanvasTouchDragAction.flip,
        );
        await pumpSheet(tester);

        expect(await pinch(tester), 1);
      });

      testWidgets('⛔two fingers landing on one point zoom nothing — there is '
          'no spread to zoom by', (tester) async {
        await pumpSheet(tester);

        expect(await pinch(tester, apart: 0), 1);
      });

      testWidgets('fingers closing onto one point zoom it out no further '
          "than the project's rate lets any zoom (F-491)", (tester) async {
        await pumpSheet(tester);
        await pinch(tester, apart: 160, by: -80);

        expect(
          zoom.value,
          TimelineZoomLimits.minPixelsPerFrameAt(
            ProjectFrameRate.fps24.countingBase,
          ),
        );
      });

      testWidgets("⛔a pen and a finger zoom nothing — a pinch is fingers'", (
        tester,
      ) async {
        await pumpSheet(tester);

        expect(await pinch(tester, first: PointerDeviceKind.stylus), 1);
      });

      testWidgets('a second finger landing on a pull takes the sheet from it '
          '— let go, it coasts on neither way', (tester) async {
        await pumpSheet(tester);
        final cells = onTheCells(tester);
        final pulling = await tester.startGesture(
          cells - const Offset(40, 0),
          kind: PointerDeviceKind.touch,
          pointer: 20,
        );
        for (var i = 0; i < 5; i += 1) {
          await pulling.moveBy(const Offset(-40, -30));
          await tester.pump(const Duration(milliseconds: 8));
        }
        final joining = await tester.startGesture(
          cells + const Offset(40, 0),
          kind: PointerDeviceKind.touch,
          pointer: 21,
        );
        await joining.up();
        final released = standing(tester);
        await pulling.up();
        await tester.pumpAndSettle();

        expect(
          [released.dx, released.dy],
          everyElement(greaterThan(0)),
          reason: '⛔premise: the first finger pulled it',
        );
        expect(standing(tester), released);
      });

      testWidgets('a finger landing on a pinch before the sheet is built '
          'again zooms on from where the pinch had got, not from the build', (
        tester,
      ) async {
        AppInput.settings.value = const AppInputSettings(
          touchDragThreeFingers: CanvasTouchDragAction.navigate,
        );
        await pumpSheet(tester);
        final cells = onTheCells(tester);
        final fingers = [
          for (final (pointer, x) in const [(20, -40.0), (21, 40.0)])
            await tester.startGesture(
              cells + Offset(x, 0),
              kind: PointerDeviceKind.touch,
              pointer: pointer,
            ),
        ];
        await tester.pump();

        // One frame: the two spread half as far again, a third lands
        // between them and stirs.
        await fingers[0].moveBy(const Offset(-20, 0));
        await fingers[1].moveBy(const Offset(20, 0));
        fingers.add(
          await tester.startGesture(
            cells,
            kind: PointerDeviceKind.touch,
            pointer: 22,
          ),
        );
        await fingers[2].moveBy(Offset.zero);
        for (final finger in fingers) {
          await finger.up();
        }
        await tester.pumpAndSettle();

        expect(
          zoom.value / TimelineZoomLimits.referencePixelsPerFrame,
          closeTo(1.5, 0.005),
        );
      });

      testWidgets('⛔a third finger stops the zoom where three are set to '
          'anything but 「내비게이트」 — 「브러시 크기」, unless set (R26 #34)', (
        tester,
      ) async {
        await pumpSheet(tester);
        final cells = onTheCells(tester);
        final fingers = [
          for (final (pointer, at) in const [
            (20, Offset(-40, 0)),
            (21, Offset(40, 0)),
            (22, Offset(0, 40)),
          ])
            await tester.startGesture(
              cells + at,
              kind: PointerDeviceKind.touch,
              pointer: pointer,
            ),
        ];
        for (var i = 0; i < 10; i += 1) {
          await fingers[0].moveBy(const Offset(-2, 0));
          await fingers[1].moveBy(const Offset(2, 0));
          await tester.pump();
        }
        for (final finger in fingers) {
          await finger.up();
        }
        await tester.pumpAndSettle();

        expect(zoom.value, TimelineZoomLimits.referencePixelsPerFrame);
      });

      group('with one finger the drawing hand (결정 10)', () {
        setUp(
          () => AppInput.settings.value = const AppInputSettings(
            touchDragOneFinger: CanvasTouchDragAction.draw,
          ),
        );

        testWidgets('two fingers landing together still zoom — the second '
            'takes the first from the edit drag that had not started '
            '(PEN-12 #4)', (tester) async {
          await pumpSheet(tester);

          expect(await pinch(tester, by: 20), closeTo(1.5, 0.005));
          expect(selects, isEmpty, reason: 'and nothing was selected');
        });

        // The conte panel's cells select through the very range drag the
        // timeline's do (`TimelineFrameRangeGestureLayer`) — on a cut, of
        // which its fixture lays few where a hand lands.
        if (sheet.name != 'conte panel') {
          testWidgets('⛔…but an edit drag under way keeps its finger, as a '
              'committed stroke does', (tester) async {
            await pumpSheet(tester);
            final cells = onTheCells(tester);
            final editing = await tester.startGesture(
              cells - const Offset(40, 0),
              kind: PointerDeviceKind.touch,
              pointer: 20,
            );
            for (var i = 0; i < 4; i += 1) {
              await editing.moveBy(const Offset(-10, 0));
              await tester.pump();
            }
            final second = await tester.startGesture(
              cells + const Offset(40, 0),
              kind: PointerDeviceKind.touch,
              pointer: 21,
            );
            for (var i = 0; i < 10; i += 1) {
              await editing.moveBy(const Offset(-4, 0));
              await second.moveBy(const Offset(4, 0));
              await tester.pump();
            }
            await second.up();
            await editing.up();
            await tester.pumpAndSettle();

            expect(
              selects,
              isNotEmpty,
              reason: '⛔premise: the first finger was selecting',
            );
            expect(zoom.value, TimelineZoomLimits.referencePixelsPerFrame);
          });
        }
      });

      testWidgets('🚨a wheel turned while a finger is on the glass moves it '
          'not at all — Windows sends a pinch again as a wheel (wheel law)', (
        tester,
      ) async {
        await pumpSheet(tester);
        final finger = TestPointer(30, PointerDeviceKind.touch);
        CanvasTouchContacts.noteAppWide(finger.down(Offset.zero));

        await wheel(tester, onTheCells(tester), shift: false);
        expect(standing(tester), Offset.zero);

        CanvasTouchContacts.noteAppWide(finger.up());
        await wheel(tester, onTheCells(tester), shift: false);
        expect(
          standing(tester),
          isNot(Offset.zero),
          reason: '⛔premise: with the finger lifted, the notch moves it',
        );
      });
    });
  }

  testWidgets("the conte tab hands its sheet's pinch to the zoom the "
      'workspace keeps (F-506)', (tester) async {
    final written = <double>[];
    await pumpStoryboardHost(
      tester,
      createDefaultProject(),
      onPixelsPerFrameChanged: written.add,
    );
    final frames = tester
        .getRect(
          find.byKey(
            const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
          ),
        )
        .intersect(
          tester.getRect(
            find.byKey(const ValueKey<String>('storyboard-vertical-viewport')),
          ),
        )
        .center;
    final fingers = [
      for (final (pointer, x) in const [(20, -40.0), (21, 40.0)])
        await tester.startGesture(
          frames + Offset(x, 0),
          kind: PointerDeviceKind.touch,
          pointer: pointer,
        ),
    ];
    for (var i = 0; i < 10; i += 1) {
      await fingers[0].moveBy(const Offset(-2, 0));
      await fingers[1].moveBy(const Offset(2, 0));
      await tester.pump();
    }
    for (final finger in fingers) {
      await finger.up();
    }
    await tester.pumpAndSettle();

    expect(
      written.lastOrNull,
      greaterThan(PanelViewMemory.defaultStoryboardPixelsPerFrame),
    );
  });
}

/// A sheet: its panel with its layer area seen through a window, the keys of
/// its outer and inner scroll views, and a layer's name on its layer area.
typedef _Sheet = ({
  String name,
  Widget Function(
    LayerRailExtent rail,
    int? rows,
    ValueNotifier<double> zoom,
  )
  panel,
  String outer,
  String inner,
  Finder aLayerName,
});
