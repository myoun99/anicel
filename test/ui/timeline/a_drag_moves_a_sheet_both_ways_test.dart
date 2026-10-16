import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

import '../../helpers/named_finders.dart';

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
void main() {
  // The product's touch: a finger scrolls the sheets, and their edit
  // gestures let it go (1핑거 드로잉 off).
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    CanvasViewHold.held.value = null;
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
  /// through [rail].
  Widget timeline(
    TimelineOrientation orientation,
    LayerRailExtent rail, {
    int? rows,
  }) {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    return TimelinePanel(
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
    );
  }

  /// The conte panel: thirty tracks — or [rows] — the last of them four
  /// hundred frames long and the rest short, so the cells are mostly empty
  /// lanes; its layer area seen through [rail].
  Widget conte(LayerRailExtent rail, {int? rows}) => StoryboardPanel(
    railExtent: rail,
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
      panel: (rail, rows) =>
          timeline(TimelineOrientation.horizontal, rail, rows: rows),
      outer: 'timeline-vertical-scroll-viewport',
      inner: 'timeline-frame-scroll-viewport',
      aLayerName: find
          .namedWhere((name) => name.startsWith('timeline-layer-name-'))
          .first,
    ),
    (
      name: 'x-sheet',
      panel: (rail, rows) =>
          timeline(TimelineOrientation.vertical, rail, rows: rows),
      outer: 'xsheet-layer-horizontal-viewport',
      inner: 'xsheet-frame-vertical-viewport',
      aLayerName: find
          .namedWhere((name) => name.startsWith('xsheet-layer-name-'))
          .first,
    ),
    (
      name: 'conte panel',
      panel: (rail, rows) => conte(rail, rows: rows),
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
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: OverflowScrollers(
              minWidth: 1000,
              minHeight: 700,
              child: sheet.panel(window, rows),
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

      testWidgets('two fingers move it both ways too', (tester) async {
        await pumpSheet(tester);
        await drag(tester, fingers: 2);
        final at = standing(tester);
        expect([at.dx, at.dy], everyElement(greaterThan(0)));
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
          [for (final position in theFloor(tester)) position.pixels],
          everyElement(0),
          reason: 'F-202: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로 '
              '안새게」',
        );
      });
    });
  }
}

/// A sheet: its panel with its layer area seen through a window, the keys of
/// its outer and inner scroll views, and a layer's name on its layer area.
typedef _Sheet = ({
  String name,
  Widget Function(LayerRailExtent rail, int? rows) panel,
  String outer,
  String inner,
  Finder aLayerName,
});
