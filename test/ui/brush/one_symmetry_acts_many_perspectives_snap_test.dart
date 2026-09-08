import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// What the guide LIBRARY list decides — the panel was 7% executed before
/// this file (the audit's coverage pass, 2026-09-08), so every law below
/// was standing on nothing.
///
/// The headline is the one the class doc states: the two act-toggles look
/// alike and behave differently on purpose. A symmetry row's is a RADIO
/// (only one may replicate), a perspective row's an independent checkbox
/// (several may snap at once). Everything else here — where a name's
/// number comes from, which id a new guide gets, what a delete does to the
/// selection — is a decision this file makes alone.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);
  final strings = AppText.strings;

  DrawingGuide symmetry(String id, {String? name}) => DrawingGuide(
    id: GuideId(id),
    name: name ?? id,
    shape: SymmetryShape(
      axis: GuideAxis(origin: CanvasPoint(x: 100, y: 100), angleDegrees: 90),
    ),
  );

  DrawingGuide perspective(
    String id, {
    String? name,
    bool snapEnabled = true,
  }) => DrawingGuide(
    id: GuideId(id),
    name: name ?? id,
    shape: PerspectiveShape(
      vanishingPoints: [VanishingPointAt(CanvasPoint(x: -100, y: 50))],
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 50, y: 50), angleDegrees: 0),
      snapEnabled: snapEnabled,
    ),
  );

  PerspectiveShape snapOf(CutGuides cut, String id) =>
      cut.guideFor(GuideId(id))!.shape as PerspectiveShape;

  /// Mounts the list and hands back what it committed. The list is
  /// stateless by design — the cut is the caller's — so one gesture per
  /// pump is the honest shape of the test.
  Future<CutGuides?> tapAndReadCommit(
    WidgetTester tester,
    CutGuides guides,
    String key, {
    GuideId? selected,
    List<GuideId?>? selections,
  }) async {
    CutGuides? committed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuideLibraryList(
            guides: guides,
            canvasSize: canvas,
            selectedGuideId: selected,
            onGuidesCommitted: (next) => committed = next,
            onGuideSelected: (id) => selections?.add(id),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
    return committed;
  }

  group('the act toggles', () {
    testWidgets('🚨switching a symmetry ON stops the one that was acting — '
        'only one may replicate, because two mirror axes at an angle that '
        'does not divide π multiply copies without end', (tester) async {
      final cut = CutGuides(
        guides: [symmetry('s1'), symmetry('s2')],
        activeSymmetryId: const GuideId('s1'),
      );

      final committed = await tapAndReadCommit(tester, cut, 'guide-acting-s2');

      expect(committed!.activeSymmetryId, const GuideId('s2'));
    });

    testWidgets('🚨switching the acting symmetry OFF leaves the cut with '
        'NONE acting — the pointer is cleared, not merely un-set', (
      tester,
    ) async {
      // The killer for `clearActiveSymmetry: !acting`. Without that flag
      // `copyWith` reads `activeSymmetryId ?? this.activeSymmetryId` and
      // the guide the user just switched off keeps replicating.
      final cut = CutGuides(
        guides: [symmetry('s1')],
        activeSymmetryId: const GuideId('s1'),
      );

      final committed = await tapAndReadCommit(tester, cut, 'guide-acting-s1');

      expect(committed!.activeSymmetryId, isNull);
      expect(committed.actingSymmetry, isNull);
    });

    testWidgets('🚨a perspective toggle is an independent checkbox — '
        'switching one off leaves the others snapping', (tester) async {
      final cut = CutGuides(guides: [perspective('p1'), perspective('p2')]);

      final committed = await tapAndReadCommit(tester, cut, 'guide-acting-p1');

      expect(snapOf(committed!, 'p1').snapEnabled, isFalse);
      expect(
        snapOf(committed, 'p2').snapEnabled,
        isTrue,
        reason: 'two buildings in one background each want their own pair',
      );
    });

    testWidgets('a perspective row reads its OWN shape, not the cut\'s '
        'symmetry pointer — one that is off switches on while a symmetry '
        'guide is acting elsewhere', (tester) async {
      final cut = CutGuides(
        guides: [symmetry('s1'), perspective('p1', snapEnabled: false)],
        activeSymmetryId: const GuideId('s1'),
      );

      final committed = await tapAndReadCommit(tester, cut, 'guide-acting-p1');

      expect(snapOf(committed!, 'p1').snapEnabled, isTrue);
      expect(
        committed.activeSymmetryId,
        const GuideId('s1'),
        reason: 'a perspective toggle never moves the symmetry pointer',
      );
    });
  });

  group('picking a row', () {
    testWidgets('a press anywhere on the row picks that guide — both '
        'families, so neither is the one you cannot reach', (tester) async {
      final selections = <GuideId?>[];
      final cut = CutGuides(guides: [symmetry('s1'), perspective('p1')]);

      await tapAndReadCommit(
        tester,
        cut,
        'guide-row-s1',
        selections: selections,
      );
      await tapAndReadCommit(
        tester,
        cut,
        'guide-row-p1',
        selections: selections,
      );

      expect(selections, [const GuideId('s1'), const GuideId('p1')]);
    });
  });

  group('the eye', () {
    testWidgets('hiding a guide does not stop it acting — the drawing and '
        'the steering are separate switches', (tester) async {
      final cut = CutGuides(
        guides: [symmetry('s1')],
        activeSymmetryId: const GuideId('s1'),
      );

      final committed = await tapAndReadCommit(tester, cut, 'guide-visible-s1');

      expect(committed!.guideFor(const GuideId('s1'))!.visible, isFalse);
      expect(committed.activeSymmetryId, const GuideId('s1'));
    });

    testWidgets('🚨the perspective family gets the same eye and the same '
        'delete — the row is written twice, so both copies are pinned', (
      tester,
    ) async {
      final cut = CutGuides(guides: [perspective('p1'), perspective('p2')]);

      final hidden = await tapAndReadCommit(tester, cut, 'guide-visible-p1');
      expect(hidden!.guideFor(const GuideId('p1'))!.visible, isFalse);
      expect(
        snapOf(hidden, 'p1').snapEnabled,
        isTrue,
        reason: 'hiding a perspective does not stop it snapping either',
      );

      final deleted = await tapAndReadCommit(tester, cut, 'guide-delete-p2');
      expect(deleted!.guides.single.id, const GuideId('p1'));
    });
  });

  group('adding', () {
    testWidgets('🚨the number in a new guide\'s name counts its FAMILY, not '
        'the length of the list', (tester) async {
      final cut = CutGuides(
        guides: [symmetry('s1'), symmetry('s2'), perspective('p1')],
      );

      final committed = await tapAndReadCommit(
        tester,
        cut,
        'guide-add-perspective',
      );

      expect(committed!.guides.last.name, '${strings.guideKindPerspective} 2');
    });

    testWidgets('a fresh cut\'s first guide is numbered 1 and is of the '
        'family whose ＋ was pressed', (tester) async {
      final committed = await tapAndReadCommit(
        tester,
        CutGuides.empty,
        'guide-add-symmetry',
      );

      expect(committed!.guides, hasLength(1));
      expect(committed.guides.single.kind, GuideKind.symmetry);
      expect(committed.guides.single.name, '${strings.guideKindSymmetry} 1');
      expect(committed.guides.single.id, const GuideId('symmetry-1'));
    });

    testWidgets('🚨a new id fills the LOWEST free slot in its family, so it '
        'can never collide with a guide that is still here', (tester) async {
      // ⚠️CHARACTERISATION, and the id and the name answer different
      // questions: the id scans for a free number while the name counts how
      // many of the family there are. With `symmetry-1` and `symmetry-3`
      // present the newcomer is id `symmetry-2` and name "… 3" — two
      // guides can therefore wear the same NAME after a delete. Recorded,
      // not changed (the audit's pinning round, 2026-09-08).
      final cut = CutGuides(
        guides: [symmetry('symmetry-1'), symmetry('symmetry-3')],
      );

      final committed = await tapAndReadCommit(
        tester,
        cut,
        'guide-add-symmetry',
      );

      expect(committed!.guides.last.id, const GuideId('symmetry-2'));
    });

    testWidgets('the new guide lands after the ones already there, and the '
        'panel selects it', (tester) async {
      final selections = <GuideId?>[];
      final cut = CutGuides(guides: [symmetry('s1')]);

      final committed = await tapAndReadCommit(
        tester,
        cut,
        'guide-add-symmetry',
        selections: selections,
      );

      expect(committed!.guides.first.id, const GuideId('s1'));
      expect(committed.guides.last.id, const GuideId('symmetry-1'));
      expect(selections, [const GuideId('symmetry-1')]);
    });
  });

  group('deleting', () {
    testWidgets('🚨deleting the SELECTED guide clears the selection', (
      tester,
    ) async {
      final selections = <GuideId?>[];
      final cut = CutGuides(guides: [symmetry('s1'), symmetry('s2')]);

      final committed = await tapAndReadCommit(
        tester,
        cut,
        'guide-delete-s1',
        selected: const GuideId('s1'),
        selections: selections,
      );

      expect(committed!.guides.single.id, const GuideId('s2'));
      expect(selections, [null]);
    });

    testWidgets('🚨deleting ANOTHER guide leaves the selection where it '
        'was — the panel does not lose the guide the user is editing', (
      tester,
    ) async {
      final selections = <GuideId?>[];
      final cut = CutGuides(guides: [symmetry('s1'), symmetry('s2')]);

      final committed = await tapAndReadCommit(
        tester,
        cut,
        'guide-delete-s2',
        selected: const GuideId('s1'),
        selections: selections,
      );

      expect(committed!.guides.single.id, const GuideId('s1'));
      expect(selections, isEmpty);
    });
  });

  group('the list itself', () {
    testWidgets('guides are grouped by family with symmetry first, whatever '
        'order the cut stores them in', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuideLibraryList(
              guides: CutGuides(guides: [perspective('p1'), symmetry('s1')]),
              canvasSize: canvas,
              selectedGuideId: null,
              onGuidesCommitted: (_) {},
              onGuideSelected: (_) {},
            ),
          ),
        ),
      );

      final symmetryRow = find.byKey(const ValueKey<String>('guide-row-s1'));
      final perspectiveRow = find.byKey(const ValueKey<String>('guide-row-p1'));
      expect(symmetryRow, findsOneWidget);
      expect(perspectiveRow, findsOneWidget);
      expect(
        tester.getTopLeft(symmetryRow).dy,
        lessThan(tester.getTopLeft(perspectiveRow).dy),
      );
    });

    testWidgets('the empty line shows only while the cut has no guides', (
      tester,
    ) async {
      Widget list(CutGuides guides) => MaterialApp(
        home: Scaffold(
          body: GuideLibraryList(
            guides: guides,
            canvasSize: canvas,
            selectedGuideId: null,
            onGuidesCommitted: (_) {},
            onGuideSelected: (_) {},
          ),
        ),
      );

      await tester.pumpWidget(list(CutGuides.empty));
      expect(find.text(strings.guideLibraryEmpty), findsOneWidget);

      await tester.pumpWidget(list(CutGuides(guides: [symmetry('s1')])));
      expect(find.text(strings.guideLibraryEmpty), findsNothing);
    });
  });
}
