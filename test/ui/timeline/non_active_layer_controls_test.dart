import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';
import '../../helpers/a_folder_made_by_hand.dart';

/// 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 **다른 레이어의 버튼
/// 누르면 작동안함.** 불투명도 슬라이더는 **한번 움직이고 드래그가 풀림.**
/// 액티브 레이어만 작용같은 규칙 두지말고 **자유롭게 가능하도록.** 레이어에
/// 있는 **모든 버튼이나 편집이** 그럼」
///
/// ★The scope is 「모든 버튼」, so this is a law rather than one button —
/// a rail row's controls act on the row they are drawn on, whichever row
/// the drawing target happens to be.
///
/// 🚨B3 (유저 2026-08-17): 「비지블·불투명도만 구현돼 있음. 나머지 버튼 전부
/// 완성」 — the eye and the slider were the only two claiming their press;
/// every other control of the row is driven here now, each with the same
/// two-part pin: the action lands on THAT row's layer, and the drawing
/// target does not move.
///
/// 🚨I-57 ㉣ (10-13): and on every way a row is reached ([_ways]) — the
/// timeline's rail and the x-sheet's headers, each as built and ACROSS A
/// CUT: a switch onto a copy of the cut, every row of which has the face
/// the old row had, so each berth hands the old row back whole. That row
/// was built for the OLD cut's layer and stands for the new one's; a
/// control that acted on the layer it was built for would act on a cut
/// that is not on screen.
void main() {
  Future<EditorSessionManager> pumpRail(
    WidgetTester tester,
    _Way way, {
    EditorSessionManager? existing,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session =
        existing ??
        (EditorSessionManager(initialProject: createDefaultProject())
          ..layerStack.addLayerOfKind(LayerKind.animation));
    if (existing == null) {
      addTearDown(session.dispose);
    }
    final copy = way.acrossACut ? _copyTheCut(session) : null;
    await pumpTimelineHostOn(
      tester,
      session,
      surface: const Size(1400, 1000),
      orientation: way.orientation,
      pixelsPerFrame: 24,
    );
    if (copy != null) {
      await _crossTo(tester, session, copy);
    }
    return session;
  }

  /// The animation row that is NOT the drawing target — the row every
  /// control below is pressed on.
  LayerId otherAnimationRow(EditorSessionManager session) => session.layers
      .firstWhere(
        (layer) =>
            layer.kind == LayerKind.animation &&
            layer.id != session.activeLayerId,
      )
      .id;

  for (final way in _ways) {
    final rail = way.prefix;
    group(way.label, () {
      testWidgets('a NON-active layer\'s visibility button works on the '
          'first press', (tester) async {
        final session = await pumpRail(tester, way);

        // The row that is NOT the drawing target.
        final other = session.layers
            .map((layer) => layer.id)
            .firstWhere((id) => id != session.activeLayerId);
        final before = session.layers
            .firstWhere((l) => l.id == other)
            .isVisible;

        await tester.tap(find.named('$rail-layer-visibility-$other'));
        await tester.pumpAndSettle();

        expect(
          session.layers.firstWhere((l) => l.id == other).isVisible,
          !before,
          reason:
              'the press landed on that row\'s button and did nothing — 「액티브 '
              '레이어만 작용같은 규칙 두지말고」',
        );
      });

      testWidgets('and it did not need to steal the drawing target to do it', (
        tester,
      ) async {
        final session = await pumpRail(tester, way);
        final active = session.activeLayerId;
        final other = session.layers
            .map((layer) => layer.id)
            .firstWhere((id) => id != active);

        await tester.tap(find.named('$rail-layer-visibility-$other'));
        await tester.pumpAndSettle();

        // ⚠️Pinned deliberately. If the button only works BECAUSE the press
        // first made that row active, the row rebuilds under the gesture —
        // and that is the other half of the report: 「슬라이더는 한번
        // 움직이고 드래그가 풀림」.
        expect(
          session.activeLayerId,
          active,
          reason: 'pressing a row control moved the drawing target',
        );
      });

      // B3: the rest of the row, control by control. Each test drives a
      // real tap on a NON-active row and pins BOTH halves at once: the
      // action lands on that row's layer, and the drawing target does not
      // move.
      group('B3 — every row control operates on a NON-active row', () {
        testWidgets('timesheet toggle', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);
          final before = session.layers
              .firstWhere((l) => l.id == other)
              .onTimesheet;

          await tester.tap(find.named('$rail-layer-timesheet-$other'));
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == other).onTimesheet,
            !before,
            reason: 'the timesheet toggle did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('color mark chip', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);

          await tester.tap(find.named('$rail-layer-mark-$other'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey<String>('layer-mark-option-paper')),
          );
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == other).mark,
            const LayerMark(process: LayerProcess.paper),
            reason: 'the mark pick did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('fx master switch', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);
          expect(session.effectsAndFx.layerFxState(other), LayerFxState.on);

          await tester.tap(find.named('$rail-layer-fx-$other'));
          await tester.pumpAndSettle();

          expect(
            session.effectsAndFx.layerFxState(other),
            LayerFxState.off,
            reason: 'the fx switch did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('onion-skin toggle', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);
          expect(session.onionSkin.isLayerOnionSkinEnabled(other), isFalse);

          await tester.tap(find.named('$rail-layer-onion-$other'));
          await tester.pumpAndSettle();

          expect(
            session.onionSkin.isLayerOnionSkinEnabled(other),
            isTrue,
            reason: 'the onion toggle did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('clip toggle', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);
          final before = session.layers
              .firstWhere((l) => l.id == other)
              .clipsToBelow;

          await tester.tap(find.named('$rail-layer-clip-$other'));
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == other).clipsToBelow,
            !before,
            reason: 'the clip toggle did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('blend-mode chip', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);

          await tester.tap(find.named('$rail-layer-blend-$other'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              ValueKey<String>('$rail-layer-blend-option-multiply'),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == other).blendMode,
            LayerBlendMode.multiply,
            reason: 'the blend pick did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('opacity slider', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final other = otherAnimationRow(session);
          final before = session.layers
              .firstWhere((l) => l.id == other)
              .opacity;

          // Toward empty: the slider starts full. The rail's runs along
          // the row; the sheet's, turned with its header, up the column.
          await tester.drag(
            find.named('$rail-layer-opacity-$other'),
            const {
              TimelineOrientation.horizontal: Offset(-30, 0),
              TimelineOrientation.vertical: Offset(0, 30),
            }[way.orientation]!,
          );
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == other).opacity,
            lessThan(before),
            reason: 'the opacity drag did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('property-lane twirl', (tester) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId!;
          final other = otherAnimationRow(session);
          // ↩️It spied on a twirl verb handed to the tab for the test; the
          // tab's is the session's now, so the row it turned is read back.
          List<bool> open() => [
            session.layerSwitches.isLayerLanesOpen(other),
            session.layerSwitches.isLayerLanesOpen(active),
          ];
          expect(open(), [false, false], reason: '⛔전제: both shut');

          await tester.tap(find.named('$rail-lane-toggle-$other'));
          await tester.pumpAndSettle();

          expect(
            open(),
            [true, false],
            reason: 'the lane twirl did not land on its own row',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('folder fold twirl', (tester) async {
          final session = EditorSessionManager(
            initialProject: createDefaultProject(),
          );
          addTearDown(session.dispose);
          // A folder around the new layer, then stand OUTSIDE it: the twirl
          // is pressed on a row that is neither active nor holding the
          // active.
          session.layerStack.addLayerOfKind(LayerKind.animation);
          groupTheActiveRowIntoAFolder(session);
          session.selectLayer(
            session.layers
                .firstWhere(
                  (l) => l.kind == LayerKind.animation && l.folderId == null,
                )
                .id,
          );
          await pumpRail(tester, way, existing: session);
          final folder = session.layers
              .firstWhere((l) => l.kind == LayerKind.folder)
              .id;
          final outside = session.layers
              .firstWhere(
                (l) => l.kind == LayerKind.animation && l.folderId == null,
              )
              .id;
          expect(session.activeLayerId, outside);

          await tester.tap(find.named('$rail-folder-twirl-$folder'));
          await tester.pumpAndSettle();

          expect(
            session.layers.firstWhere((l) => l.id == folder).collapsed,
            isTrue,
            reason: 'the fold twirl did not land on its own row',
          );
          expect(
            session.activeLayerId,
            outside,
            reason: 'pressing a row control moved the drawing target',
          );
        });

        testWidgets('SE speaker opens the mixer without stealing the target', (
          tester,
        ) async {
          final session = await pumpRail(tester, way);
          final active = session.activeLayerId;
          final se = session.layers
              .firstWhere((l) => l.kind == LayerKind.se)
              .id;

          await tester.tap(find.named('$rail-layer-mute-$se'));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey<String>('se-layer-mixer')),
            findsOneWidget,
            reason: 'the speaker did not open its own row\'s mixer',
          );
          expect(
            session.activeLayerId,
            active,
            reason: 'pressing a row control moved the drawing target',
          );
        });
      });
    });
  }
}

/// A way the rows are reached: which grid, and whether across a cut.
typedef _Way = ({TimelineOrientation orientation, bool acrossACut});

const _ways = <_Way>[
  (orientation: TimelineOrientation.horizontal, acrossACut: false),
  (orientation: TimelineOrientation.vertical, acrossACut: false),
  (orientation: TimelineOrientation.horizontal, acrossACut: true),
  (orientation: TimelineOrientation.vertical, acrossACut: true),
];

extension on _Way {
  /// What the grid's rows' names begin with.
  String get prefix =>
      orientation == TimelineOrientation.horizontal ? 'timeline' : 'xsheet';

  String get label => acrossACut ? '$prefix, across a cut' : prefix;
}

/// A copy of the active cut, both cuts standing on the row of the same
/// name — so a switch between the two changes no row's face, only which
/// layer each row stands for. The original is the active cut again.
CutId _copyTheCut(EditorSessionManager session) {
  final original = session.activeCutId!;
  final before = {for (final cut in session.activeTrack.cuts) cut.id};
  final standing = session.activeLayer!.name;
  session.cutVerbs.duplicateActiveCut();
  final copy = session.activeTrack.cuts
      .firstWhere((cut) => !before.contains(cut.id))
      .id;
  for (final cut in [copy, original]) {
    session.selectCut(cut);
    session.selectLayer(
      session.layers.firstWhere((layer) => layer.name == standing).id,
    );
  }
  return copy;
}

/// Switches to [copy] — and holds that the rail's rows came back WHOLE:
/// the very widgets the old cut's layers were built as.
Future<void> _crossTo(
  WidgetTester tester,
  EditorSessionManager session,
  CutId copy,
) async {
  List<Widget> rows() =>
      tester.widgetList(find.byType(TimelineLayerControlsRow)).toList();
  final before = rows();
  expect(before, isNotEmpty, reason: 'LIVENESS: the rows stand');

  session.selectCut(copy);
  await tester.pumpAndSettle();

  expect(session.activeCutId, copy, reason: 'LIVENESS: the switch happened');
  expect(
    rows(),
    orderedEquals(before),
    reason:
        '🚨I-57 ㉣: every row of the copy has the face the old row had, so '
        'each berth hands its row back whole',
  );
}
