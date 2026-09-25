import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

/// 🚨text-scale-rail-columns (유저 2026-09-25, answering
/// text-scale-rail-columns-Q1: 「칸도 글자 따라 넓어진다」 — its stated cost:
/// the rail widens by what its word-holding columns grew). The rows had grown
/// with their words (text-scale-rail-rows); their columns had not — at 1.5×
/// the opacity digits wanted 35.5 in the bar's 26 and 「Normal」 56.6 in the
/// blend chip's 52, and the sheet's stood-up bars cut the same digits.
///
/// 🚨text-scale-rail-opac (유저 2026-09-25, answering text-scale-rail-opac-Q1:
/// 「칸을 가장 넓은 글자에 맞게 1배부터 넓힌다」). The legend's resting OPAC
/// was short by 8.7 at EVERY size, 1× included — a column narrower than its
/// word from the start, which growth cannot mend. The column widened from
/// 1×, so the legends are held to the same check as the rows.
///
/// ⚠️In the app's face or not at all ([loadTheAppFaces]), and in the real
/// root ([AnicelApp]).
void main() {
  setUpAll(loadTheAppFaces);

  void atTextScale(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// A row's opacity bar under [scope] — every rail keys it
  /// `<surface>-layer-opacity-<id>`.
  Rect rowOpacityBar(WidgetTester tester, Finder scope) => tester.getRect(
    find
        .descendant(
          of: scope,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.contains(
                  '-layer-opacity-',
                ),
          ),
        )
        .first,
  );

  /// The legend's opacity cell under [scope] — the master bar, or the
  /// heading where there is none.
  Rect legendOpacity(WidgetTester tester, Finder scope) => tester.getRect(
    find
        .descendant(
          of: scope,
          matching: find.byKey(const ValueKey<String>('legend-opacity')),
        )
        .first,
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    group('at $scale×', () {
      testWidgets('no word of a rail row is cut at its side, and the rail '
          'pays for the columns that grew', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();

        final rows = find.byType(TimelineLayerControlsRow);
        expect(rows, findsWidgets, reason: 'LIVENESS — the rail shows rows');
        expect(wordsCutAcross(rows), isEmpty);
        expect(
          wordsCutAcross(find.byType(TimelineLayerControlsHeader)),
          isEmpty,
          reason: 'the legend\'s resting OPAC fits its bar, 1× included',
        );

        final shown = layerRailColumnWidthsIn(tester.element(rows.first));
        expect(
          tester.getSize(find.byType(TimelineLayerControlsHeader).first).width,
          closeTo(timelineLayerControlsWidthFor(shown), 0.5),
          reason: 'the rail is as wide as its columns ask',
        );
        expect(
          timelineLayerControlsWidthFor(shown),
          scale == 1.0
              ? timelineLayerControlsWidth
              : greaterThan(timelineLayerControlsWidth),
          reason: '1× stands where it was drawn; a bigger text size grows it',
        );
      });

      testWidgets('the legend\'s master bar sits over the rows\' opacity '
          'column — one column, however wide it grew', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();

        final master = tester.getRect(
          find.byKey(const ValueKey<String>('legend-opacity')),
        );
        final rowBar = tester.getRect(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.contains(
                      '-layer-opacity-',
                    ),
              )
              .first,
        );
        expect(master.left, closeTo(rowBar.left, 0.5));
        expect(master.width, closeTo(rowBar.width, 0.5));
      });

      testWidgets('the sheet\'s stood-up columns cut no word either', (
        tester,
      ) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(
                const ValueKey<String>('timeline-orientation-toggle-button'),
              )
              .first,
        );
        await tester.pumpAndSettle();

        final heads = find.byType(TimelineLayerControlsRow);
        expect(heads, findsWidgets, reason: 'LIVENESS — the sheet shows');
        expect(wordsCutAcross(heads), isEmpty);

        // The legend stands beside the headers, laid out from the same
        // columns: its OPAC heading spans the headers' bar, down the column.
        final bar = rowOpacityBar(tester, find.byType(Scaffold).first);
        final heading = legendOpacity(tester, find.byType(Scaffold).first);
        expect(heading.top, closeTo(bar.top, 0.5));
        expect(heading.height, closeTo(bar.height, 0.5));
        // …and runs the whole block the headers run, grown columns and all.
        final legend = find.byType(TimelineLayerControlsHeader).first;
        expect(wordsCutAcross(legend), isEmpty);
        expect(
          tester.getSize(legend).height,
          closeTo(
            XSheetTimelineGrid.naturalHeaderBlockExtent(
              hasOnionColumn: true,
              hasBlendColumn: true,
              columns: layerRailColumnWidthsIn(tester.element(legend)),
            ),
            0.5,
          ),
        );
      });

      testWidgets('the storyboard\'s rail grows its opacity column the same '
          'way — its own width, its own columns', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(const ValueKey<String>('timeline-mode-storyboard-button'))
              .first,
        );
        await tester.pumpAndSettle();

        final board = find.byType(StoryboardPanel);
        expect(board, findsOneWidget, reason: 'LIVENESS — the board shows');
        expect(wordsCutAcross(board), isEmpty);
        expect(
          StoryboardPanel.railWidthIn(tester.element(board)),
          scale == 1.0 ? 443 : greaterThan(443),
        );

        // Its legend's master bar sits over its S rows' bars.
        final bar = rowOpacityBar(tester, board);
        final master = legendOpacity(tester, board);
        expect(master.left, closeTo(bar.left, 0.5));
        expect(master.width, closeTo(bar.width, 0.5));
      });
    });
  }
}
