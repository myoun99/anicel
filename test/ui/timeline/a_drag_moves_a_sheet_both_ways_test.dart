import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🗣️F-351 (유저 2026-10-12): 「스페이스바로 타임라인쪽 조작하면 가로/세로
/// 스크롤 통합해서 캔버스 조작하듯이 팬 되는데, 법 통일해서 터치로 해당영역
/// 조작시에도 가로/세로 같이 하도록」.
///
/// A sheet is one surface scrolled two ways, and a drag on it moves it both
/// ways at once — each axis by its own part of the hand's travel, as Space
/// moves it — where each axis used to take a drag of its own and the one
/// the hand moved along first took all of it.
void main() {
  // The product's touch: a finger scrolls the sheets, and their edit
  // gestures let it go (1핑거 드로잉 off).
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(
    () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
  );

  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  /// The timeline or the x-sheet: sixty rows, four hundred frames — more of
  /// both than a wide panel shows.
  Widget timeline(TimelineOrientation orientation) {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    return TimelinePanel(
      layers: [for (var i = 0; i < 60; i += 1) drawing('draw-$i')],
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

  /// Every sheet the app scrolls two ways.
  final sheets = <_Sheet>[
    (
      name: 'timeline',
      panel: () => timeline(TimelineOrientation.horizontal),
      outer: 'timeline-vertical-scroll-viewport',
      inner: 'timeline-frame-scroll-viewport',
    ),
    (
      name: 'x-sheet',
      panel: () => timeline(TimelineOrientation.vertical),
      outer: 'xsheet-layer-horizontal-viewport',
      inner: 'xsheet-frame-vertical-viewport',
    ),
  ];

  for (final sheet in sheets) {
    Future<void> pumpSheet(WidgetTester tester) async {
      // Wide enough for the cells beside the rail to be a panel's worth.
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(body: sheet.panel()),
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

    /// A point on the sheet's cells: the middle of what shows of its inner
    /// scroll view.
    Offset onTheCells(WidgetTester tester) => tester
        .getRect(find.byKey(ValueKey<String>(sheet.inner)))
        .intersect(tester.getRect(find.byKey(ValueKey<String>(sheet.outer))))
        .center;

    /// [fingers] land together on the cells and travel ten steps of [step].
    Future<void> drag(
      WidgetTester tester, {
      Offset step = const Offset(-20, -15),
      int fingers = 1,
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      final from = onTheCells(tester);
      final gestures = [
        for (var finger = 0; finger < fingers; finger += 1)
          await tester.startGesture(
            from + Offset(finger * 30.0, 0),
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

          await drag(tester, step: step);

          expect(standing(tester).dx, closeTo(travelOf(step).dx, 0.5));
          expect(standing(tester).dy, closeTo(travelOf(step).dy, 0.5));
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
    });
  }
}

/// A sheet: its panel, and the keys of its outer and inner scroll views.
typedef _Sheet = ({
  String name,
  Widget Function() panel,
  String outer,
  String inner,
});
