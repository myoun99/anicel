import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/brush/tool_setting_rows.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

import '../../helpers/boolean_dot_probe.dart';

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

  /// The paper the panel stands its guides over: a family at infinity comes
  /// back 1.5 × its width — 1200 — from the eye level's handle.
  const paper = CanvasSize(width: 800, height: 600);

  /// Mounts the settings panel over [guides] with [selected] picked, and
  /// records what it commits — and, given them, what it shows while a bar
  /// moves and what it hands to be rasterized.
  Future<void> pumpSettings(
    WidgetTester tester,
    CutGuides guides,
    GuideId? selected,
    void Function(CutGuides) onCommitted, {
    void Function(CutGuides)? onPreview,
    ValueChanged<DrawingGuide>? onRasterized,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuideSettings(
          guides: guides,
          selectedGuideId: selected,
          canvasSize: paper,
          onGuidesCommitted: onCommitted,
          onGuidesPreview: onPreview ?? (_) {},
          onGuideRasterized: onRasterized,
        ),
      ),
    ),
  );

  /// The 「평행」 pill in the row of the point at [index].
  Finder parallelPillOf(int index) => find.descendant(
    of: find.byKey(ValueKey<String>('guide-vanishing-point-$index')),
    matching: find.byKey(const ValueKey<String>('guide-parallel')),
  );

  /// [point] as a point on the plane, near enough to ([x], [y]).
  void expectStandsAt(VanishingPoint point, double x, double y) {
    expect(point, isA<VanishingPointAt>());
    final at = (point as VanishingPointAt).point;
    expect(at.x, closeTo(x, 1e-9));
    expect(at.y, closeTo(y, 1e-9));
  }

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
      expect(find.text(strings.noGuideSelected), findsOneWidget);
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

      await tester.pressRingIn(
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
        await tester.pressRingIn(find.byKey(ValueKey<String>(key)));
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

    testWidgets('🚨「평행」 turns a point on the paper into the family running '
        'the way it lay from the eye level\'s handle — on that point alone', (
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

      await tester.tap(parallelPillOf(1));
      await tester.pump();

      final points = perspectiveOf(committed!, 'p1').vanishingPoints;
      // vanishing-point-types-Q2: 「점이 있던 쪽 그대로」 — a point right of
      // the handle at (50, 50) is the family running right.
      expect(points[1], VanishingPointTowards(dx: 1, dy: 0));
      expect(
        points.first,
        at(-100, 50),
        reason: 'the point the user did not press is untouched',
      );
    });

    testWidgets('🚨「평행」 pressed off brings a family back the way it ran, '
        'as far out as a new guide\'s points — onto the eye level while the '
        'guide holds its points there', (tester) async {
      Future<VanishingPoint> back({required bool held}) async {
        CutGuides? committed;
        await pumpSettings(
          tester,
          CutGuides(
            guides: [
              DrawingGuide(
                id: const GuideId('p1'),
                name: 'p1',
                shape: PerspectiveShape(
                  vanishingPoints: [VanishingPointTowards(dx: 3, dy: 4)],
                  eyeLevel: axis(),
                  constrainToEyeLevel: held,
                ),
              ),
            ],
          ),
          const GuideId('p1'),
          (next) => committed = next,
        );
        await tester.tap(parallelPillOf(0));
        await tester.pump();
        return perspectiveOf(committed!, 'p1').vanishingPoints.single;
      }

      // (0.6, 0.8) × 1200 from the handle at (50, 50).
      expectStandsAt(await back(held: false), 50 + 720, 50 + 960);
      // Held to the level eye level, it lands where a drag there would.
      expectStandsAt(await back(held: true), 50 + 720, 50);
    });

    testWidgets('the pill is lit while the point is at infinity, and '
        'refused where the point names no way to turn', (tester) async {
      final degenerate = VanishingPointFromLines(
        GuideLine(
          a: CanvasPoint(x: 0, y: 0),
          b: CanvasPoint(x: 1e200, y: 1e200),
        ),
        GuideLine(a: CanvasPoint(x: 0, y: 1), b: CanvasPoint(x: 1e200, y: 0)),
      );
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide(
              'p1',
              points: [
                at(900, 50),
                VanishingPointTowards(dx: 0, dy: 1),
                degenerate,
              ],
            ),
          ],
        ),
        const GuideId('p1'),
        (_) {},
      );

      Pill pill(int index) => tester.widget<Pill>(parallelPillOf(index));
      expect(pill(0).selected, isFalse);
      expect(pill(0).onTap, isNotNull);
      expect(pill(1).selected, isTrue);
      expect(pill(1).onTap, isNotNull);
      expect(pill(2).onTap, isNull, reason: 'no point, no way: refused');
      expect(
        parallelPillOf(2),
        findsOneWidget,
        reason: 'a refused pill keeps its place',
      );
    });

    testWidgets('🚨a family\'s angle cell shows the way it runs, and its '
        'release writes it — 90 EXACTLY the vertical family', (tester) async {
      CutGuides? shown;
      CutGuides? committed;
      await pumpSettings(
        tester,
        CutGuides(
          guides: [
            perspectiveGuide(
              'p1',
              points: [at(-100, 50), VanishingPointTowards(dx: 1, dy: 1)],
            ),
          ],
        ),
        const GuideId('p1'),
        (next) => committed = next,
        onPreview: (next) => shown = next,
      );
      final angle = find.byKey(
        const ValueKey<String>('guide-vanishing-point-1-angle'),
      );
      expect(tester.widget<FieldSlider>(angle).value, closeTo(45, 1e-9));
      expect(
        find.byKey(const ValueKey<String>('guide-vanishing-point-0-angle')),
        findsNothing,
        reason: 'a point on the paper reads where it stands instead',
      );

      tester.widget<FieldSlider>(angle).onChanged!(30);
      expect(committed, isNull, reason: 'a bar in flight is shown, not kept');
      expect(
        perspectiveOf(shown!, 'p1').vanishingPoints[1],
        VanishingPointTowards.atDegrees(30),
      );

      tester.widget<FieldSlider>(angle).onChangeEnd!(90);
      final points = perspectiveOf(committed!, 'p1').vanishingPoints;
      expect(points[1], VanishingPointTowards(dx: 0, dy: 1));
      expect(points.first, at(-100, 50));
    });

    testWidgets('🚨the guide\'s ONE density bar: shown while it moves, kept '
        'once let go, held to 4…48', (tester) async {
      CutGuides? shown;
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
        onPreview: (next) => shown = next,
      );
      final bar = tester.widget<FieldSlider>(
        find.byKey(const ValueKey<String>('guide-line-density')),
      );
      expect(bar.value, defaultGuideLineDensity);
      expect((bar.min, bar.max), (4, 48));

      bar.onChanged!(20.4);
      expect(committed, isNull);
      expect(perspectiveOf(shown!, 'p1').lineDensity, 20);

      bar.onChangeEnd!(30);
      expect(perspectiveOf(committed!, 'p1').lineDensity, 30);
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

    // 🗣️I-58 (유저 2026-10-18): 「ㅁㅁ 삭제」. ↩️It borrowed the guide
    // row's string.
    testWidgets('a point\'s delete names the point, not the guide', (
      tester,
    ) async {
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

      final remove = tester.widget<ToolSettingAction>(
        find.ancestor(
          of: find.descendant(
            of: find.byKey(const ValueKey<String>('guide-vanishing-point-0')),
            matching: find.byKey(const ValueKey<String>('guide-remove')),
          ),
          matching: find.byType(ToolSettingAction),
        ),
      );
      expect(remove.label, strings.guideDeleteVanishingPoint);
    });

    testWidgets('🚨the ＋ adds a point on the plane beside the eye level\'s '
        'handle, ON the eye level — however many there are', (tester) async {
      final addButton = find.byKey(
        const ValueKey<String>('guide-add-vanishing-point'),
      );
      var guides = CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('p1'),
            name: 'p1',
            shape: PerspectiveShape(
              vanishingPoints: [at(-100, 50), at(900, 50)],
              // Tilted, so 「on the eye level」 is no mere x + 420.
              eyeLevel: axis(angleDegrees: 30),
            ),
          ),
        ],
      );
      // ↩️It stopped at three until 2026-10-16 (09-17: 「소실점 몇개든
      // 추가할수있게하고, 기본값은 일반타입」).
      for (var count = 3; count <= 5; count += 1) {
        CutGuides? committed;
        await pumpSettings(
          tester,
          guides,
          const GuideId('p1'),
          (next) => committed = next,
        );
        await tester.tap(addButton);
        await tester.pump();
        guides = committed!;
        expect(perspectiveOf(guides, 'p1').vanishingPoints, hasLength(count));
      }

      final added = perspectiveOf(guides, 'p1').vanishingPoints.last;
      expectStandsAt(
        added,
        50 + 420 * math.cos(math.pi / 6),
        50 + 420 * math.sin(math.pi / 6),
      );
    });

    testWidgets('🚨래스터라이즈 hands over the guide it is pressed for — and keeps '
        'its place, dead, where nothing can take it', (tester) async {
      final guide = perspectiveGuide('p1', points: [at(-100, 50)]);
      final rasterize = find.byKey(const ValueKey<String>('guide-rasterize'));
      DrawingGuide? handed;
      await pumpSettings(
        tester,
        CutGuides(guides: [guide]),
        const GuideId('p1'),
        (_) {},
        onRasterized: (picked) => handed = picked,
      );
      await tester.tap(rasterize);
      await tester.pump();
      expect(handed, guide);

      handed = null;
      await pumpSettings(
        tester,
        CutGuides(guides: [guide]),
        const GuideId('p1'),
        (_) {},
      );
      expect(rasterize, findsOneWidget, reason: 'the button keeps its place');
      await tester.tap(rasterize);
      await tester.pump();
      expect(handed, isNull);
    });
  });

  group('what a vanishing point row says', () {
    Future<String> readoutFor(
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
      return tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('guide-vanishing-point-0-reads'),
            ),
          )
          .data!;
    }

    testWidgets('🚨a point on the paper reads its position ROUNDED, not '
        'truncated — a point at 1234.6 is nearer 1235', (tester) async {
      expect(await readoutFor(tester, at(1234.6, -7.4)), '1235, -7');
    });

    testWidgets('two drawn lines that never meet say so instead of dividing '
        'by zero', (tester) async {
      // A family stated as a direction shows its angle instead — the cell
      // above; two PARALLEL drawn lines are the same point, unnamed.
      final parallel = VanishingPointFromLines(
        GuideLine(a: CanvasPoint(x: 0, y: 0), b: CanvasPoint(x: 10, y: 0)),
        GuideLine(a: CanvasPoint(x: 0, y: 5), b: CanvasPoint(x: 10, y: 5)),
      );
      expect(parallel.resolve().isInfinite, isTrue);

      expect(
        await readoutFor(tester, parallel),
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
        await readoutFor(tester, degenerate),
        strings.guideVanishingPointAtInfinity,
      );
    });
  });
}
