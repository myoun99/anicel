import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import '../../helpers/app_icon_button_probe.dart';

/// F-87 (유저 2026-09-12): 「fx 헤더 선택범위로 선택한채로 삭제누르면 해당 fx
/// 삭제」 — and 09-16: 「추가한 fx를 삭제하려고 fx헤더 선택범위로 선택하니
/// 삭제버튼이 비활성화된채로있음」. Answered 09-23: the header row was DRAGGED
/// and a band was drawn.
///
/// The 09-16 measurement read the SESSION's answer (`deleteSubject`), never
/// the button on screen. This reads both, on both axes, with each device.
void main() {
  Future<EditorSessionManager> openTheSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    for (final drawn in const [true, false]) {
      testWidgets('${kind.name}, ${drawn ? 'a drawn' : 'an empty'} layer: a '
          'sweep along the fx header row arms the one delete — on the '
          'timeline and on the X-sheet', (tester) async {
        final session = await openTheSheet(tester);
        final layer = session.requireActiveCut.layers.first;
        session.selectLayer(layer.id);
        session.selectFrameIndex(3);
        if (drawn) {
          session.createDrawingAtCurrentFrame();
        }
        session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
        await tester.pumpAndSettle();
        final effect = session.requireActiveCut.layers
            .firstWhere((row) => row.id == layer.id)
            .effects
            .single;
        final headerLane = effectGroupLaneId(effect.id);

        final laneToggle = find.byKey(
          ValueKey<String>('timeline-lane-toggle-${layer.id.value}'),
        );
        await tester.ensureVisible(laneToggle);
        await tester.pumpAndSettle();
        await tester.tap(laneToggle);
        await tester.pumpAndSettle();

        Finder headerBand() => find.byKey(
          ValueKey<String>(
            'timeline-lane-range-layer-${layer.id.value}-$headerLane',
          ),
        );

        /// Sweeps two cells along the band's FRAME axis from half a cell
        /// in — inside the band at both ends, whichever way the sheet is
        /// turned.
        ///
        /// ⚠️A sweep that leaves the band leaves the test window with it,
        /// and a pointer outside the window makes no selection at all —
        /// which reads exactly like the bug this pins (measured 09-16).
        Future<void> sweep({required bool vertical}) async {
          const cell = 24.0;
          const row = timelineLayerRowHeight;
          final start =
              tester.getTopLeft(headerBand()) +
              (vertical
                  ? const Offset(row / 2, cell / 2)
                  : const Offset(cell / 2, row / 2));
          final step = vertical ? const Offset(0, cell) : const Offset(cell, 0);
          final finger = await tester.startGesture(start, kind: kind);
          await finger.moveBy(step);
          await tester.pump();
          await finger.moveBy(step);
          await tester.pump();
          await finger.up();
          await tester.pumpAndSettle();
        }

        final deleteButton = find.byKey(
          const ValueKey<String>('shared-delete-button'),
        );

        for (final vertical in [false, true]) {
          if (vertical) {
            session.clearLaneRangeSelection();
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(
                const ValueKey<String>('timeline-orientation-toggle-button'),
              ),
            );
            await tester.pumpAndSettle();
          }
          final where = vertical ? 'the X-sheet' : 'the timeline';
          expect(
            headerBand(),
            findsOneWidget,
            reason: 'fixture: $where draws it',
          );

          await sweep(vertical: vertical);

          final range = session.laneRangeSelection.value;
          expect(
            range?.spanLaneIds,
            [headerLane],
            reason: '$where: the sweep names the fx header itself',
          );
          expect(
            session.cells.canDeleteCellForSelection,
            isTrue,
            reason: '$where: the live range holds something to delete',
          );
          expect(
            session.deleteSubjectFor(cutsAreThisPanels: false),
            DeleteSubject.cells,
            reason: '$where: so the session arms the one delete',
          );
          expect(deleteButton, findsOneWidget, reason: '$where: the pill');
          expect(
            tester.appIconButton(deleteButton).onPressed,
            isNotNull,
            reason: '$where: and the BUTTON on screen is lit — what the '
                'user saw grey',
          );
        }

        // ⚠️The command bar scrolls sideways, and at this window's width the
        // pill sits past its edge: a press at the button's centre landed on
        // another group's 「100.0%」 and read exactly like a dead delete
        // (measured 2026-09-24). Bring it into view the way a hand would.
        await tester.ensureVisible(deleteButton);
        await tester.pumpAndSettle();
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();
        expect(
          session.requireActiveCut.layers
              .firstWhere((row) => row.id == layer.id)
              .effects,
          isEmpty,
          reason: '「fx 헤더 선택범위로 선택한채로 삭제누르면 해당 fx 삭제」',
        );
      });
    }
  }

  // Every row kind that takes an fx, added the way the Add Layer menu adds
  // it — the user did not say which row it was.
  for (final kind in LayerKind.values.where(
    (kind) => kind.hasLayerEffects && kind != LayerKind.animation,
  )) {
    testWidgets('a ${kind.name} row: the fx header sweep arms the delete and '
        'the press removes the fx', (tester) async {
      final session = await openTheSheet(tester);
      session.layerStack.addLayerOfKind(kind);
      await tester.pumpAndSettle();
      final layer = session.activeLayer!;
      expect(layer.kind, kind, reason: 'fixture: the new row is active');
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      await tester.pumpAndSettle();
      final effect = session.commitLayerById(layer.id)!.effects.single;
      final headerLane = effectGroupLaneId(effect.id);

      final laneToggle = find.byKey(
        ValueKey<String>('timeline-lane-toggle-${layer.id.value}'),
      );
      await tester.ensureVisible(laneToggle);
      await tester.pumpAndSettle();
      await tester.tap(laneToggle);
      await tester.pumpAndSettle();
      final band = find.byKey(
        ValueKey<String>(
          'timeline-lane-range-layer-${layer.id.value}-$headerLane',
        ),
      );
      expect(band, findsOneWidget, reason: 'fixture: the header row is drawn');
      await tester.ensureVisible(band);
      await tester.pumpAndSettle();
      final start =
          tester.getTopLeft(band) +
          const Offset(12, timelineLayerRowHeight / 2);
      final finger = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await finger.moveBy(const Offset(24, 0));
      await tester.pump();
      await finger.moveBy(const Offset(24, 0));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(session.laneRangeSelection.value?.spanLaneIds, [headerLane]);
      final deleteButton = find.byKey(
        const ValueKey<String>('shared-delete-button'),
      );
      expect(
        tester.appIconButton(deleteButton).onPressed,
        isNotNull,
        reason: 'the button on screen is lit',
      );
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(
        session.commitLayerById(layer.id)?.effects,
        isEmpty,
        reason: 'the press removed the fx from the ${kind.name} row',
      );
    });
  }
}
