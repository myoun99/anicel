import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show timelineLayerRowLeadingBorder;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerRailLeadingSlot, layerRailLeadingWidthTo;

/// **I-1 — a row button's swipe is about the COLUMN, not about the eye.**
///
/// 유저 2026-08-24: 「레이어의 버튼 조작하는거 **일괄조작**하는 기능 넣고싶음
/// … 탭 다운 한 채로 아래로 드래그하면 **해당 다른 레이어도 버튼조작**되도록.
/// 즉 여러 레이어 드래그하면서 **비지블버튼 off**한다거나 그런느낌」
///
/// The Krita-style paint-swipe existed for the EYE alone, with the eye's
/// x-range typed into the widget that owned it. The swipe was never about
/// the eye — so the column is the argument now, and the rail lists the
/// toggle columns it has.
void main() {
  Project project() => Project(
    id: const ProjectId('swipe'),
    name: 'Swipe',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var i = 0; i < 5; i += 1)
                Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    return sessionOf(tester);
  }

  /// Presses the button on [fromKey] and drags DOWN across [rows] rows.
  Future<void> swipeDown(
    WidgetTester tester,
    String fromKey, {
    required int rows,
    String rowKey = 'timeline-layer-row-l4',
  }) async {
    final start = tester.getCenter(find.byKey(ValueKey<String>(fromKey)));
    final rowHeight = tester
        .getRect(find.byKey(ValueKey<String>(rowKey)))
        .height;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= rows; step += 1) {
      await gesture.moveBy(Offset(0, rowHeight));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  List<bool> visibility(EditorSessionManager s) => [
    for (final layer in s.requireActiveCut.layers) layer.isVisible,
  ];

  testWidgets('the EYE column still paints down the rows', (tester) async {
    final s = await pump(tester);
    expect(visibility(s).every((on) => on), isTrue, reason: 'premise');

    // The rail renders the stack reversed, so l4 is the TOP row: a downward
    // swipe from it crosses l3, l2, …
    await swipeDown(tester, 'timeline-layer-visibility-l4', rows: 2);

    final hidden = [
      for (final layer in s.requireActiveCut.layers)
        if (!layer.isVisible) layer.id.value,
    ];
    expect(
      hidden.length,
      greaterThan(1),
      reason: 'the swipe painted more than the row it started on',
    );
  });

  testWidgets('and so does the ONION column — the swipe is the column\'s, '
      'not the eye\'s', (tester) async {
    final s = await pump(tester);
    expect(
      s.onionSkinLayerIds.value,
      isEmpty,
      reason: 'premise: nothing ghosting yet',
    );

    await swipeDown(tester, 'timeline-layer-onion-l4', rows: 2);

    expect(
      s.onionSkinLayerIds.value.length,
      greaterThan(1),
      reason: 'I-1: 「타임시트버튼이든 뭐 그런것들」 — every toggle column, '
          'not the one that happened to be built first',
    );
  });

  testWidgets('⛔a swipe that starts between columns paints nothing', (
    tester,
  ) async {
    final s = await pump(tester);
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-row-l4')),
    );
    // The NAME area — a place to grab the row by, never a column.
    final gesture = await tester.startGesture(
      Offset(row.left + 40, row.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 2; step += 1) {
      await gesture.moveBy(Offset(0, row.height));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(visibility(s).every((on) => on), isTrue);
    expect(s.onionSkinLayerIds.value, isEmpty);
  });

  /// I-1 잔여 — the LEADING run.
  ///
  /// 🚨The leading columns are a GEOMETRY problem the trailing ones are not:
  /// the folder indent falls between the mark and the twirl, so the sheet
  /// toggle's x moves one whole slot per level of nesting. A band typed as a
  /// constant is right only on unnested rows.
  group('the leading columns paint too', () {
    Project nested() => Project(
      id: const ProjectId('swipe'),
      name: 'Swipe',
      createdAt: DateTime.utc(2026, 8, 25),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: 'C',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              // Rendered top-to-bottom reversed, so the rail reads
              // m1, m0, F, l1, l0 — a downward swipe from a MEMBER crosses
              // the folder row and then two unnested rows, which is the
              // depth change the bands have to survive.
              //
              // Every real row starts OFF the sheet so the swipe TURNS THEM
              // ON: that is what makes "the folder was skipped" observable.
              // A folder is off by construction (it prints nothing), so a
              // swipe that merely left it alone would look identical to one
              // that treated it as an ordinary false.
              layers: [
                for (var i = 0; i < 2; i += 1)
                  Layer(
                    id: LayerId('l$i'),
                    name: 'L$i',
                    frames: const [],
                    onTimesheet: false,
                  ),
                createFolderLayer(id: const LayerId('f'), name: 'F'),
                for (var i = 0; i < 2; i += 1)
                  Layer(
                    id: LayerId('m$i'),
                    name: 'M$i',
                    frames: const [],
                    onTimesheet: false,
                    folderId: const LayerId('f'),
                  ),
              ],
            ),
          ],
        ),
      ],
    );

    Future<EditorSessionManager> pumpNested(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: nested())),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      return sessionOf(tester);
    }

    List<String> offSheet(EditorSessionManager s) => [
      for (final layer in s.requireActiveCut.layers)
        if (!layer.onTimesheet) layer.id.value,
    ];

    List<String> onSheet(EditorSessionManager s) => [
      for (final layer in s.requireActiveCut.layers)
        if (layer.onTimesheet) layer.id.value,
    ];

    testWidgets('the TIMESHEET column — the one the report named', (
      tester,
    ) async {
      final s = await pump(tester);
      expect(offSheet(s), isEmpty, reason: 'premise: every row is on sheet');

      await swipeDown(tester, 'timeline-layer-timesheet-l4', rows: 2);

      expect(
        offSheet(s).length,
        greaterThan(1),
        reason: 'I-1: 「타임시트버튼이든 뭐 그런것들」',
      );
    });

    testWidgets('a swipe STARTED on a nested row still finds its column', (
      tester,
    ) async {
      final s = await pumpNested(tester);
      expect(onSheet(s), isEmpty, reason: 'premise: nothing prints yet');

      // M1 sits one level in, so its sheet toggle is two slots right of an
      // unnested row's. Pressing it is the whole geometry problem: with a
      // constant band this press lands in no column at all.
      await swipeDown(
        tester,
        'timeline-layer-timesheet-m1',
        rows: 3,
        rowKey: 'timeline-layer-row-m1',
      );

      expect(
        onSheet(s),
        containsAll(<String>['m1', 'm0']),
        reason: 'the press engaged on the nested row it landed on',
      );
      expect(
        onSheet(s),
        contains('l1'),
        reason:
            '🚨and kept painting ACROSS the depth change — after the press '
            'the swipe paints by column identity, never by re-testing x',
      );
      expect(
        onSheet(s),
        isNot(contains('f')),
        reason:
            'a swipe cannot paint what a tap could not: the folder row it '
            'crossed carries no sheet toggle at all',
      );
    });

    testWidgets(
      '⛔and the unnested sheet x on a nested row is the NESTING cell, '
      'which paints nothing',
      (tester) async {
        final s = await pumpNested(tester);
        final unnested = tester.getCenter(
          find.byKey(const ValueKey<String>('timeline-layer-timesheet-l1')),
        );
        final nestedRow = tester.getRect(
          find.byKey(const ValueKey<String>('timeline-layer-row-m1')),
        );

        final gesture = await tester.startGesture(
          Offset(unnested.dx, nestedRow.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 16));
        for (var step = 1; step <= 3; step += 1) {
          await gesture.moveBy(Offset(0, nestedRow.height));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          onSheet(s),
          isEmpty,
          reason:
              'that x holds the ↳ on this row — a band that ignored depth '
              'would paint the sheet column from a press on the indent',
        );
      },
    );
    testWidgets('the LANE TWIRL column paints too', (tester) async {
      await pump(tester);
      Finder openTwirls() => find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.arrow_drop_down,
      );
      final before = openTwirls().evaluate().length;

      await swipeDown(tester, 'timeline-lane-toggle-l4', rows: 2);

      expect(
        openTwirls().evaluate().length,
        greaterThan(before + 1),
        reason:
            'the twirl is the leading column most exposed to the indent — '
            'it is the very cell the nesting run pushes',
      );
    });

    testWidgets(
      'the band function is what the rail actually renders, at every depth',
      (tester) async {
        await pumpNested(tester);

        double insetOf(String rowId) {
          final button = tester.getTopLeft(
            find.byKey(ValueKey<String>('timeline-layer-timesheet-$rowId')),
          );
          final row = tester.getTopLeft(
            find.byKey(ValueKey<String>('timeline-layer-row-$rowId')),
          );
          return button.dx - row.dx;
        }

        // 🚨Measured against the tree, not against the constants it is made
        // of: a band derived from a number nothing renders is a band that
        // can be wrong in both places at once.
        expect(
          insetOf('l1'),
          timelineLayerRowLeadingBorder +
              layerRailLeadingWidthTo(to: LayerRailLeadingSlot.timesheet),
          reason: 'unnested',
        );
        expect(
          insetOf('m1'),
          timelineLayerRowLeadingBorder +
              layerRailLeadingWidthTo(
                to: LayerRailLeadingSlot.timesheet,
                depth: 1,
              ),
          reason:
              'one level in — the indent moved the column, and the band '
              'moved with it',
        );
        expect(
          insetOf('m1') - insetOf('l1'),
          greaterThan(0),
          reason:
              'fixture premise: the two rows really do differ, so the test '
              'above is not comparing a number with itself',
        );
      },
    );
  });
}
