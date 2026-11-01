import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_content_translation.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import '../../helpers/named_finders.dart';

/// F-544's panels (유저 2026-11-02): 「뭐 이런 ui개편같은거 다른 도구설정쪽
/// 참고해서 그대로 재사용하면서 법 통일」 — the tool library's bar and swatch,
/// the eye level as a group of its own, and a point's numbers and density on
/// the point's own lane.
void main() {
  const s = GuideId('s1');
  const p = GuideId('p1');
  const paper = CanvasSize(width: 800, height: 600);

  DrawingGuide symmetryGuide() => DrawingGuide(
    id: s,
    name: '대칭',
    shape: SymmetryShape(
      axis: GuideAxis(origin: CanvasPoint(x: 50, y: 60), angleDegrees: 90),
    ),
  );

  DrawingGuide perspectiveGuide({bool constrained = false}) => DrawingGuide(
    id: p,
    name: '퍼스',
    shape: PerspectiveShape(
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 100, y: 200), angleDegrees: 0),
      constrainToEyeLevel: constrained,
      vanishingPoints: [
        VanishingPointAt(CanvasPoint(x: -100, y: 200), lineDensity: 24),
        VanishingPointAt(CanvasPoint(x: 900, y: 200)),
      ],
    ),
  );

  PerspectiveShape shapeOf(CutGuides cut) =>
      cut.guideFor(p)!.shape as PerspectiveShape;

  Finder boxOf(String key) => find.byKey(ValueKey<String>(key));

  DragValueLabel box(WidgetTester tester, String key) =>
      tester.widget<DragValueLabel>(
        find.byWidgetPredicate(
          (widget) => widget is DragValueLabel && widget.keyValue == key,
        ),
      );

  Future<void> pumpSettings(
    WidgetTester tester,
    CutGuides guides,
    GuideId selected, {
    void Function(CutGuides)? onCommitted,
    void Function(CutGuides)? onPreview,
    ValueNotifier<CutGuides?>? inFlight,
  }) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuideSettings(
            guides: guides,
            selectedGuideId: selected,
            canvasSize: paper,
            onGuidesCommitted: onCommitted ?? (_) {},
            onGuidesPreview: onPreview ?? (_) {},
            guidesInFlight: inFlight,
            onGuideRasterized: null,
          ),
        ),
      ),
    );
  }

  Future<void> pumpLibrary(
    WidgetTester tester,
    CutGuides guides, {
    void Function(CutGuides)? onCommitted,
    void Function(CutGuides)? onPreview,
    double width = 340,
  }) async {
    tester.view.physicalSize = Size(width, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuideLibraryList(
            guides: guides,
            canvasSize: paper,
            selectedGuideId: null,
            onGuidesCommitted: onCommitted ?? (_) {},
            onGuidesPreview: onPreview ?? (_) {},
            onGuideSelected: (_) {},
          ),
        ),
      ),
    );
  }

  group('the tool library\'s row', () {
    final cut = CutGuides(guides: [symmetryGuide(), perspectiveGuide()]);

    for (final id in ['s1', 'p1']) {
      testWidgets('🗣️$id: the bar stands left of the eye, the rename left '
          'of the bar', (tester) async {
        await pumpLibrary(tester, cut);
        final bar = find.named('guide-opacity-$id');
        final eye = find.named('guide-visible-$id');
        final rename = find.byKey(ValueKey<String>('guide-rename-$id'));
        expect(bar, findsOneWidget);
        expect(
          tester.getTopRight(bar).dx,
          lessThanOrEqualTo(tester.getTopLeft(eye).dx),
        );
        expect(
          tester.getTopRight(rename).dx,
          lessThanOrEqualTo(tester.getTopLeft(bar).dx),
        );
      });
    }

    testWidgets('🚨a narrow panel squeezes the name and the bar, and the row '
        'holds together', (tester) async {
      for (final width in const [180.0, 240.0, 320.0]) {
        await pumpLibrary(tester, cut, width: width);
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
      final name = tester.getSize(find.text('대칭'));
      expect(name.width, greaterThan(20), reason: 'at 320 it is read');
    });

    testWidgets('🚨the bar: every sample shown, the release written — one '
        'drag, one undo', (tester) async {
      final previews = <CutGuides>[];
      final commits = <CutGuides>[];
      await pumpLibrary(
        tester,
        cut,
        onPreview: previews.add,
        onCommitted: commits.add,
      );
      final bar = tester.widget<FieldSlider>(find.named('guide-opacity-s1'));
      expect(bar.value, 1);

      bar.onChanged!(0.4);
      bar.onChanged!(0.3);
      expect(previews.last.guideFor(s)!.opacity, 0.3);
      expect(commits, isEmpty);

      bar.onChangeEnd!(0.3);
      expect(commits.single.guideFor(s)!.opacity, 0.3);
      expect(commits.single.guideFor(p)!.opacity, 1);
    });

    testWidgets('🚨the swatch is the app\'s own, on the app\'s colour until '
        'the guide names one', (tester) async {
      await pumpLibrary(tester, cut);
      final context = tester.element(find.byType(GuideLibraryList));
      final swatch = tester.widget<ColorSwatchButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColorSwatchButton &&
              widget.keyValue == 'guide-color-s1',
        ),
      );
      expect(swatch.color, guideColorOf(context).toARGB32());
    });

    testWidgets('🚨a guide that names a colour shows it on its swatch', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        CutGuides(guides: [symmetryGuide().copyWith(color: 0xFF112233)]),
      );
      expect(
        tester
            .widget<ColorSwatchButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is ColorSwatchButton &&
                    widget.keyValue == 'guide-color-s1',
              ),
            )
            .color,
        0xFF112233,
      );
    });

    testWidgets('🚨the wheel: every colour shown, the one it rests on '
        'written once the window closes', (tester) async {
      final previews = <CutGuides>[];
      final commits = <CutGuides>[];
      await pumpLibrary(
        tester,
        cut,
        onPreview: previews.add,
        onCommitted: commits.add,
      );
      ColorSwatchButton swatch() => tester.widget<ColorSwatchButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColorSwatchButton &&
              widget.keyValue == 'guide-color-p1',
        ),
      );

      swatch().onChanged(0xFF112233);
      swatch().onChanged(0xFF445566);
      await tester.pump();
      expect(previews.last.guideFor(p)!.color, 0xFF445566);
      expect(commits, isEmpty);
      expect(swatch().color, 0xFF445566, reason: 'the face follows the pick');

      swatch().onSettled!();
      expect(commits.single.guideFor(p)!.color, 0xFF445566);
      expect(commits.single.guideFor(s)!.color, isNull);

      swatch().onSettled!();
      expect(commits, hasLength(1), reason: 'no pick, nothing to write');
    });
  });

  group('🗣️the eye level is a group: 표시, 색, 위치', () {
    final cut = CutGuides(guides: [perspectiveGuide()]);

    testWidgets('it stands under its own head, its eye the app\'s own', (
      tester,
    ) async {
      await pumpSettings(tester, cut, p);
      expect(find.text(AppText.strings.guideEyeLevel), findsOneWidget);
      expect(
        tester
            .widget<LayerVisibilityToggleButton>(
              find.byType(LayerVisibilityToggleButton),
            )
            .isVisible,
        isTrue,
      );
    });

    testWidgets('🚨its colour wears the guide\'s until it names its own, one '
        'pick one write', (tester) async {
      CutGuides? shown;
      CutGuides? written;
      final worn = CutGuides(
        guides: [perspectiveGuide().copyWith(color: 0xFF112233)],
      );
      await pumpSettings(
        tester,
        worn,
        p,
        onPreview: (next) => shown = next,
        onCommitted: (next) => written = next,
      );
      ColorSwatchButton swatch() => tester.widget<ColorSwatchButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColorSwatchButton &&
              widget.keyValue == 'guide-eye-level-color',
        ),
      );
      expect(swatch().color, 0xFF112233);

      swatch().onChanged(0xFF445566);
      expect(shapeOf(shown!).eyeLevelColor, 0xFF445566);
      expect(written, isNull);
      swatch().onSettled!();
      expect(shapeOf(written!).eyeLevelColor, 0xFF445566);
      expect(written!.guideFor(p)!.color, 0xFF112233);
    });

    testWidgets('🚨an eye level that names a colour shows its own', (
      tester,
    ) async {
      final plain = perspectiveGuide();
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            plain.copyWith(
              color: 0xFF112233,
              shape: (plain.shape as PerspectiveShape).copyWith(
                eyeLevelColor: 0xFF445566,
              ),
            ),
          ],
        ),
        p,
      );
      expect(
        tester
            .widget<ColorSwatchButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is ColorSwatchButton &&
                    widget.keyValue == 'guide-eye-level-color',
              ),
            )
            .color,
        0xFF445566,
      );
    });

    testWidgets('🚨its eye writes the fact it shows', (tester) async {
      CutGuides? written;
      await pumpSettings(
        tester,
        cut,
        p,
        onCommitted: (next) => written = next,
      );
      await tester.tap(find.named('guide-eye-level-visible'));
      await tester.pump();
      expect(shapeOf(written!).eyeLevelVisible, isFalse);
    });

    testWidgets('🚨its 위치 is the transform\'s box: X and Y, typed and '
        'scrubbed', (tester) async {
      await pumpSettings(tester, cut, p);
      expect(box(tester, 'guide-eye-level-x').name, 'X');
      expect(box(tester, 'guide-eye-level-y').name, 'Y');
      expect(box(tester, 'guide-eye-level-x').text, columnValueText(100));
      expect(box(tester, 'guide-eye-level-y').text, columnValueText(200));
    });

    testWidgets('🚨a number moves it as its handle would: held points come '
        'along (`movedEyeLevel`)', (tester) async {
      CutGuides? written;
      final held = CutGuides(guides: [perspectiveGuide(constrained: true)]);
      await pumpSettings(
        tester,
        held,
        p,
        onCommitted: (next) => written = next,
      );

      box(tester, 'guide-eye-level-y').onEditSubmit!('260');
      final shape = shapeOf(written!);
      expect(shape.eyeLevel.origin, CanvasPoint(x: 100, y: 260));
      expect(
        (shape.vanishingPoints[0] as VanishingPointAt).point,
        CanvasPoint(x: -100, y: 260),
      );
      expect(shape.vanishingPoints[0].lineDensity, 24);
    });
  });

  group('🗣️a vanishing point\'s lane: its numbers and its bar', () {
    final cut = CutGuides(guides: [perspectiveGuide()]);

    testWidgets('🚨each point has a bar of its own, and it writes that point '
        'alone', (tester) async {
      CutGuides? shown;
      CutGuides? written;
      await pumpSettings(
        tester,
        cut,
        p,
        onPreview: (next) => shown = next,
        onCommitted: (next) => written = next,
      );
      FieldSlider bar(int index) => tester.widget<FieldSlider>(
        boxOf('guide-vanishing-point-$index-density'),
      );
      expect(bar(0).value, 24);
      expect(bar(1).value, 12);
      expect(find.byKey(const ValueKey('guide-line-density')), findsNothing);

      bar(1).onChanged!(100);
      expect(shapeOf(shown!).vanishingPoints[1].lineDensity, 100);
      expect(shapeOf(shown!).vanishingPoints[0].lineDensity, 24);
      expect(written, isNull);

      bar(1).onChangeEnd!(192);
      expect(shapeOf(written!).vanishingPoints[1].lineDensity, 192);
      expect(shapeOf(written!).vanishingPoints[0].lineDensity, 24);
    });

    testWidgets('🚨its number obeys the eye level as its handle does', (
      tester,
    ) async {
      CutGuides? written;
      await pumpSettings(
        tester,
        CutGuides(guides: [perspectiveGuide(constrained: true)]),
        p,
        onCommitted: (next) => written = next,
      );
      box(tester, 'guide-vanishing-point-0-y').onEditSubmit!('999');
      expect(
        (shapeOf(written!).vanishingPoints[0] as VanishingPointAt).point,
        CanvasPoint(x: -100, y: 200),
        reason: 'held on a level eye level, a Y goes nowhere',
      );

      box(tester, 'guide-vanishing-point-0-x').onEditSubmit!('-300');
      final moved = shapeOf(written!).vanishingPoints[0];
      expect((moved as VanishingPointAt).point.x, -300);
      expect(moved.lineDensity, 24, reason: 'a move leaves its density');
    });

    testWidgets('🚨a scrub shows every step and writes once, the number '
        'following the guides in flight', (tester) async {
      final inFlight = ValueNotifier<CutGuides?>(null);
      addTearDown(inFlight.dispose);
      final commits = <CutGuides>[];
      await pumpSettings(
        tester,
        cut,
        p,
        inFlight: inFlight,
        onPreview: (next) => inFlight.value = next,
        onCommitted: (next) {
          inFlight.value = null;
          commits.add(next);
        },
      );
      const key = 'guide-vanishing-point-1-x';

      box(tester, key).onDragDelta(10);
      box(tester, key).onDragDelta(5);
      await tester.pump();
      expect(box(tester, key).text, columnValueText(915));
      expect(commits, isEmpty);

      box(tester, key).onOperationEnd!();
      expect(
        (shapeOf(commits.single).vanishingPoints[1] as VanishingPointAt).point,
        CanvasPoint(x: 915, y: 200),
      );
    });

    testWidgets('🚨a canvas handle\'s drag moves the numbers too', (
      tester,
    ) async {
      final inFlight = ValueNotifier<CutGuides?>(null);
      addTearDown(inFlight.dispose);
      await pumpSettings(tester, cut, p, inFlight: inFlight);
      expect(box(tester, 'guide-vanishing-point-0-x').text, columnValueText(-100));

      inFlight.value = dragGuideHandle(
        cut,
        GuideHandle(
          guideId: p,
          kind: GuideHandleKind.vanishingPoint,
          position: CanvasPoint(x: -40, y: 200),
          vanishingPointIndex: 0,
        ),
        CanvasPoint(x: -40, y: 200),
      );
      await tester.pump();
      expect(box(tester, 'guide-vanishing-point-0-x').text, columnValueText(-40));
    });

    testWidgets('🚨a family at infinity has its angle and no X or Y', (
      tester,
    ) async {
      final plain = perspectiveGuide();
      final family = (plain.shape as PerspectiveShape).withVanishingPoint(
        0,
        VanishingPointTowards(dx: 0, dy: 1),
      );
      await pumpSettings(
        tester,
        CutGuides(guides: [plain.copyWith(shape: family)]),
        p,
      );
      expect(boxOf('guide-vanishing-point-0-angle'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DragValueLabel &&
              widget.keyValue == 'guide-vanishing-point-0-x',
        ),
        findsNothing,
      );
      expect(boxOf('guide-vanishing-point-0-density'), findsOneWidget);
    });
  });

  group('🗣️a symmetry\'s middle has the same numbers', () {
    testWidgets('its 위치 reads and writes the axis\'s origin', (tester) async {
      CutGuides? written;
      await pumpSettings(
        tester,
        CutGuides(guides: [symmetryGuide()]),
        s,
        onCommitted: (next) => written = next,
      );
      expect(box(tester, 'guide-origin-x').text, columnValueText(50));

      box(tester, 'guide-origin-x').onEditSubmit!('75');
      expect(
        (written!.guideFor(s)!.shape as SymmetryShape).axis.origin,
        CanvasPoint(x: 75, y: 60),
      );
    });
  });

  group('🚨a point keeps its density through everything that remakes it', () {
    final shape = perspectiveGuide(constrained: true).shape as PerspectiveShape;

    test('a handle\'s drag', () {
      final dragged = dragGuideHandle(
        CutGuides(guides: [perspectiveGuide()]),
        GuideHandle(
          guideId: p,
          kind: GuideHandleKind.vanishingPoint,
          position: CanvasPoint(x: 0, y: 0),
          vanishingPointIndex: 0,
        ),
        CanvasPoint(x: 0, y: 0),
      );
      expect(shapeOf(dragged).vanishingPoints[0].lineDensity, 24);
    });

    test('the 「평행」 pill, both ways', () {
      final family = shape.withVanishingPoint(
        0,
        toggledParallel(shape, shape.vanishingPoints[0], reach: 300)!,
      );
      expect(family.vanishingPoints[0], isA<VanishingPointTowards>());
      expect(family.vanishingPoints[0].lineDensity, 24);

      final back = family.withVanishingPoint(
        0,
        toggledParallel(family, family.vanishingPoints[0], reach: 300)!,
      );
      expect(back.vanishingPoints[0], isA<VanishingPointAt>());
      expect(back.vanishingPoints[0].lineDensity, 24);
    });

    test('the eye level carrying it', () {
      final carried = movedEyeLevel(
        shape,
        shape.eyeLevel.copyWith(origin: CanvasPoint(x: 100, y: 300)),
      );
      expect(carried.vanishingPoints[0].lineDensity, 24);
    });

    test('a canvas resize moving the cut\'s content', () {
      final moved = translateCutGuides(
        CutGuides(guides: [perspectiveGuide()]),
        10,
        20,
      );
      expect(shapeOf(moved).vanishingPoints[0].lineDensity, 24);
    });
  });
}
