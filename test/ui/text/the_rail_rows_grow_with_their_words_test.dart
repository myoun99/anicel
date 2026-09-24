import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

/// 🚨text-scale-rail-rows (유저 2026-09-24, answering
/// rail-rows-under-text-scale: 「행도 글자 크기를 따라 자란다」 — its stated
/// cost: fewer rows on screen, and every surface that reads the row height
/// follows). The bars grew first (text-scale-fixed-height-bars); a census of
/// the whole screen in the app's face then found the same cut in every rail
/// row and in the legend above them — at 1.5× a row's name wanted 30 in its
/// 27, the opacity digits 24 in their 18, and fx folded onto a second line.
///
/// ⚠️In the app's face or not at all ([loadTheAppFaces]), and in the real
/// root ([AnicelApp]) — the same two conditions the bars' pin set.
void main() {
  setUpAll(loadTheAppFaces);

  void atTextScale(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    group('at $scale×', () {
      testWidgets('no word of a rail row is cut off', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();

        final rows = find.byType(TimelineLayerControlsRow);
        expect(rows, findsWidgets, reason: 'LIVENESS — the rail shows rows');
        expect(wordsCutOff(rows), isEmpty);
      });

      testWidgets('a rail row is the height the grid\'s rows are asked for '
          '— one answer', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();

        final row = find.byType(TimelineLayerControlsRow).first;
        final shown = timelineLayerRowHeightIn(tester.element(row));
        expect(
          tester.getSize(row).height,
          closeTo(shown, 0.5),
          reason: 'the rail row and the grid cell are one row',
        );
        expect(
          shown,
          scale == 1.0 ? timelineLayerRowHeight : greaterThan(28),
          reason: '1× stands where it was drawn; a bigger text size grows it',
        );
      });

      testWidgets('no word of the legend is cut off', (tester) async {
        atTextScale(tester, scale);
        await tester.pumpWidget(const AnicelApp());
        await tester.pumpAndSettle();

        final legend = find.byType(TimelineLayerControlsHeader);
        expect(legend, findsWidgets, reason: 'LIVENESS — the legend shows');
        expect(wordsCutOff(legend), isEmpty);
      });
    });
  }
}
