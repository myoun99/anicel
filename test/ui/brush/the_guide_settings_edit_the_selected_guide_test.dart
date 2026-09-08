import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// What the guide TOOL's entry in the tool SETTINGS panel decides — the
/// half of `guide_panels.dart` that edits a guide rather than lists one.
/// It was unexecuted before this file (the audit's coverage pass,
/// 2026-09-08).
///
/// The laws here are the ones a user would notice were they wrong: which
/// guide the knobs belong to, that the copy count steps in pairs while
/// mirroring, that the snap switch 유저 struck out on 2026-09-01 is still
/// gone, and that a perspective can never be edited down to no vanishing
/// point at all.
void main() {
  final strings = AppText.strings;

  GuideAxis axis({double angleDegrees = 0}) =>
      GuideAxis(origin: CanvasPoint(x: 50, y: 50), angleDegrees: angleDegrees);

  DrawingGuide symmetryGuide(
    String id, {
    int lineCount = 2,
    bool lineSymmetry = true,
  }) => DrawingGuide(
    id: GuideId(id),
    name: id,
    shape: SymmetryShape(
      axis: axis(angleDegrees: 90),
      lineCount: lineCount,
      lineSymmetry: lineSymmetry,
    ),
  );

  DrawingGuide perspectiveGuide(
    String id, {
    required List<VanishingPoint> points,
  }) => DrawingGuide(
    id: GuideId(id),
    name: id,
    shape: PerspectiveShape(vanishingPoints: points, eyeLevel: axis()),
  );

  VanishingPoint at(double x, double y) =>
      VanishingPointAt(CanvasPoint(x: x, y: y));

  SymmetryShape symmetryOf(CutGuides cut, String id) =>
      cut.guideFor(GuideId(id))!.shape as SymmetryShape;

  PerspectiveShape perspectiveOf(CutGuides cut, String id) =>
      cut.guideFor(GuideId(id))!.shape as PerspectiveShape;

  /// Mounts the settings panel over [guides] with [selected] picked, and
  /// records what it commits.
  Future<void> pumpSettings(
    WidgetTester tester,
    CutGuides guides,
    GuideId? selected,
    void Function(CutGuides) onCommitted,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuideSettings(
          guides: guides,
          selectedGuideId: selected,
          onGuidesCommitted: onCommitted,
        ),
      ),
    ),
  );

  group('whose knobs these are', () {
    testWidgets('nothing selected → the prompt, and no guide\'s knobs', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        CutGuides(guides: [symmetryGuide('s1')]),
        null,
        (_) {},
      );

      expect(
        find.byKey(const ValueKey<String>('guide-settings-none')),
        findsOneWidget,
      );
      expect(find.text(strings.guideSelectPrompt), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('guide-line-count')),
        findsNothing,
      );
    });

    testWidgets('🚨an id whose guide is GONE falls back to the prompt rather '
        'than editing whichever guide is nearest', (tester) async {
      await pumpSettings(
        tester,
        CutGuides(guides: [symmetryGuide('s1')]),
        const GuideId('deleted-last-round'),
        (_) {},
      );

      expect(
        find.byKey(const ValueKey<String>('guide-settings-none')),
        findsOneWidget,
      );
    });

    testWidgets('🚨the switch edits the SELECTED guide, and leaves the '
        'others exactly as they were', (tester) async {
      CutGuides? committed;
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            symmetryGuide('s1', lineCount: 4),
            symmetryGuide('s2', lineCount: 6),
          ],
        ),
        const GuideId('s2'),
        (next) => committed = next,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('guide-line-symmetry')),
      );
      await tester.pump();

      final next = committed!;
      expect(symmetryOf(next, 's2').lineSymmetry, isFalse);
      expect(symmetryOf(next, 's1').lineSymmetry, isTrue);
      expect(symmetryOf(next, 's1').lineCount, 4);
    });
  });

  group('the copy count', () {
    FieldSlider countSlider(WidgetTester tester) => tester.widget<FieldSlider>(
      find.byKey(const ValueKey<String>('guide-line-count')),
    );

    testWidgets('🚨mirrored copies come in PAIRS, so the count steps by two '
        'while line symmetry is on and by one when it is off', (tester) async {
      await pumpSettings(
        tester,
        CutGuides(guides: [symmetryGuide('s1', lineSymmetry: true)]),
        const GuideId('s1'),
        (_) {},
      );
      final mirrored = countSlider(tester).divisions;

      await pumpSettings(
        tester,
        CutGuides(
          guides: [symmetryGuide('s1', lineCount: 3, lineSymmetry: false)],
        ),
        const GuideId('s1'),
        (_) {},
      );
      final rotated = countSlider(tester).divisions;

      expect(rotated, maxSymmetryLineCount - 2);
      expect(mirrored, (maxSymmetryLineCount - 2) ~/ 2);
    });

    testWidgets('🚨the bar cannot be dragged outside the counts a '
        'SymmetryShape will accept — it throws below 2 and above the max', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        CutGuides(guides: [symmetryGuide('s1')]),
        const GuideId('s1'),
        (_) {},
      );

      expect(countSlider(tester).min, 2);
      expect(countSlider(tester).max, maxSymmetryLineCount.toDouble());
    });

    testWidgets('🚨dragged to either end the bar hands the model a count it '
        'ACCEPTS — a SymmetryShape throws outside 2…max, so the range is '
        'the guard and not a suggestion', (tester) async {
      Future<int> dragTo(double fraction) async {
        CutGuides? committed;
        await pumpSettings(
          tester,
          CutGuides(
            guides: [symmetryGuide('s1', lineCount: 9, lineSymmetry: false)],
          ),
          const GuideId('s1'),
          (next) => committed = next,
        );
        final bar = find.byKey(const ValueKey<String>('guide-line-count'));
        final width = tester.getSize(bar).width;
        await tester.drag(bar, Offset(width * fraction, 0));
        await tester.pump();
        return symmetryOf(committed!, 's1').lineCount;
      }

      expect(await dragTo(-1), 2);
      expect(await dragTo(1), maxSymmetryLineCount);
    });
  });

  group('the perspective panel', () {
    testWidgets('🚨carries the eye-level pair and NOT a second snap switch '
        '(유저 2026-09-01: 「퍼스자의 툴설정에 있는 스냅버튼, 이거 중복되니까 '
        '삭제. 퍼스자 이름 왼쪽에 이미 존재」)', (tester) async {
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [at(-100, 50), at(900, 50)]),
          ],
        ),
        const GuideId('p1'),
        (_) {},
      );

      // The whole SET, not a count: a snap switch that came back under a
      // new key would slip past `findsNWidgets`.
      expect(
        tester
            .widgetList<SettingsSwitchRow>(find.byType(SettingsSwitchRow))
            .map((row) => row.tileKey)
            .toSet(),
        {
          const ValueKey<String>('guide-eye-level-visible'),
          const ValueKey<String>('guide-constrain-eye-level'),
        },
      );
    });

    testWidgets('🚨its two switches write the eye level\'s own facts, each '
        'to its own field', (tester) async {
      Future<PerspectiveShape> toggle(String key) async {
        CutGuides? committed;
        await pumpSettings(
          tester,
          CutGuides(
            guides: [
              perspectiveGuide('p1', points: [at(-100, 50), at(900, 50)]),
            ],
          ),
          const GuideId('p1'),
          (next) => committed = next,
        );
        await tester.tap(find.byKey(ValueKey<String>(key)));
        await tester.pump();
        return perspectiveOf(committed!, 'p1');
      }

      final hiddenEyeLevel = await toggle('guide-eye-level-visible');
      expect(hiddenEyeLevel.eyeLevelVisible, isFalse);
      expect(
        hiddenEyeLevel.constrainToEyeLevel,
        isTrue,
        reason:
            'drawing the horizon and holding the points on it are two '
            'questions — 유저 kept both switches',
      );

      final freedPoints = await toggle('guide-constrain-eye-level');
      expect(freedPoints.constrainToEyeLevel, isFalse);
      expect(freedPoints.eyeLevelVisible, isTrue);
    });

    testWidgets('🚨"make vertical" states the direction EXACTLY, on that '
        'point alone', (tester) async {
      CutGuides? committed;
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [at(-100, 50), at(900, 50)]),
          ],
        ),
        const GuideId('p1'),
        (next) => committed = next,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('guide-vanishing-point-1')),
          matching: find.byKey(const ValueKey<String>('guide-make-vertical')),
        ),
      );
      await tester.pump();

      final points = perspectiveOf(committed!, 'p1').vanishingPoints;
      expect(points, hasLength(2));
      expect(points[1], VanishingPointTowards(dx: 0, dy: 1));
      expect(
        points.first,
        at(-100, 50),
        reason: 'the point the user did not press is untouched',
      );
    });

    testWidgets('🚨the LAST vanishing point cannot be removed — a '
        'perspective guide with none of them is not a guide', (tester) async {
      CutGuides? committed;
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [at(-100, 50)]),
          ],
        ),
        const GuideId('p1'),
        (next) => committed = next,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('guide-vanishing-point-0')),
          matching: find.byKey(const ValueKey<String>('guide-remove')),
        ),
      );
      await tester.pump();

      expect(committed, isNull);
    });

    testWidgets('with two points, removing one leaves the other', (
      tester,
    ) async {
      CutGuides? committed;
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [at(-100, 50), at(900, 50)]),
          ],
        ),
        const GuideId('p1'),
        (next) => committed = next,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('guide-vanishing-point-0')),
          matching: find.byKey(const ValueKey<String>('guide-remove')),
        ),
      );
      await tester.pump();

      expect(perspectiveOf(committed!, 'p1').vanishingPoints, [at(900, 50)]);
    });

    testWidgets('🚨a third point is offered only while there is room for '
        'one, and it starts as the VERTICAL family', (tester) async {
      CutGuides? committed;
      final addButton = find.byKey(
        const ValueKey<String>('guide-add-vanishing-point'),
      );

      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [at(-100, 50), at(900, 50)]),
          ],
        ),
        const GuideId('p1'),
        (next) => committed = next,
      );
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pump();

      final points = perspectiveOf(committed!, 'p1').vanishingPoints;
      expect(points, hasLength(3));
      expect(points.last, VanishingPointTowards(dx: 0, dy: 1));

      await pumpSettings(
        tester,
        CutGuides(guides: [committed!.guides.single]),
        const GuideId('p1'),
        (_) {},
      );
      expect(
        addButton,
        findsNothing,
        reason: 'a PerspectiveShape refuses a fourth',
      );
    });
  });

  group('what a vanishing point row says', () {
    Future<String> subtitleFor(
      WidgetTester tester,
      VanishingPoint point,
    ) async {
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide('p1', points: [point]),
          ],
        ),
        const GuideId('p1'),
        (_) {},
      );
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('guide-vanishing-point-0')),
      );
      return (tile.subtitle! as Text).data!;
    }

    testWidgets('🚨a point on the paper reads its position ROUNDED, not '
        'truncated — a point at 1234.6 is nearer 1235', (tester) async {
      expect(await subtitleFor(tester, at(1234.6, -7.4)), '1235, -7');
    });

    testWidgets('a point at infinity says so instead of dividing by zero', (
      tester,
    ) async {
      expect(
        await subtitleFor(tester, VanishingPointTowards(dx: 0, dy: 1)),
        strings.guideVanishingPointAtInfinity,
      );
    });

    testWidgets('🚨two drawn lines that meet past the reach of a double read '
        'as parallel too — the row asks for a POSITION and gets none, which '
        'is the second arm of that condition', (tester) async {
      final degenerate = VanishingPointFromLines(
        GuideLine(
          a: CanvasPoint(x: 0, y: 0),
          b: CanvasPoint(x: 1e200, y: 1e200),
        ),
        GuideLine(a: CanvasPoint(x: 0, y: 1), b: CanvasPoint(x: 1e200, y: 0)),
      );
      // Not `w == 0`: the cross product overflows, so the homogeneous point
      // is (-∞, -∞, -∞) and only `position` (∞/∞ = NaN) can tell.
      expect(degenerate.resolve().isInfinite, isFalse);

      expect(
        await subtitleFor(tester, degenerate),
        strings.guideVanishingPointAtInfinity,
      );
    });
  });
}
