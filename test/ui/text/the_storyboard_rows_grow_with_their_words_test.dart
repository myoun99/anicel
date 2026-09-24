import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

/// 🚨text-scale-storyboard-rows (유저 2026-09-24, 「행도 글자 크기를 따라
/// 자란다」). The rows round grew the timeline's rows and this panel's legend
/// BAND, and not the storyboard's own three rows, which are drawn at heights
/// of their own — at 2× an S row's name wanted 40 in its 29, and the legend
/// inside the grown band still read the 1× row (its OPAC 32 in 26).
///
/// Each row is the height it was drawn at plus as much as a row's name grew
/// ([timelineLayerRowGrowthIn]), and a rail label and the strip beside it
/// are ONE row — so both are measured, and so is the ring the panel's row
/// table places, never the table itself.
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

  Future<Finder> openTheBoard(WidgetTester tester) async {
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
    return board;
  }

  Finder keyed(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  /// [label] and [strip] are one row: the same top, the same height, and
  /// that height is [drawn] at 1× plus the name's growth.
  void expectOneRow(
    WidgetTester tester, {
    required Finder label,
    required Finder strip,
    required double drawn,
    required double growth,
  }) {
    final labelRect = tester.getRect(label);
    final stripRect = tester.getRect(strip);
    expect(labelRect.height, closeTo(drawn + growth, 0.5));
    expect(stripRect.top, closeTo(labelRect.top, 0.5));
    expect(stripRect.height, closeTo(labelRect.height, 0.5));
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    group('at $scale×', () {
      testWidgets('no word of the board\'s rows or its legend is cut off', (
        tester,
      ) async {
        atTextScale(tester, scale);
        final board = await openTheBoard(tester);
        expect(wordsCutOff(board), isEmpty);
      });

      testWidgets('an S row and the transition row are as tall as their '
          'words ask — each label and its strip one row', (tester) async {
        atTextScale(tester, scale);
        final board = await openTheBoard(tester);
        final growth = timelineLayerRowGrowthIn(tester.element(board));
        expect(
          growth,
          scale == 1.0 ? 0 : greaterThan(0),
          reason: '1× stands where it was drawn; a bigger text size grows it',
        );

        expectOneRow(
          tester,
          label: keyed('storyboard-se-label-').first,
          strip: keyed('storyboard-se-row-').first,
          drawn: 30,
          growth: growth,
        );
        expectOneRow(
          tester,
          label: keyed('storyboard-transition-label-').first,
          strip: keyed('storyboard-transition-row-').first,
          drawn: 30,
          growth: growth,
        );

        // The legend is the band's row, however tall the band grew.
        expect(
          tester
              .getSize(
                find.descendant(
                  of: board,
                  matching: find.byType(TimelineLayerControlsHeader),
                ),
              )
              .height,
          closeTo(timelineLayerRowHeightIn(tester.element(board)), 0.5),
        );
      });

      testWidgets('a twirled-down lane grows the same way, and no word of it '
          'is cut', (tester) async {
        atTextScale(tester, scale);
        final board = await openTheBoard(tester);
        final growth = timelineLayerRowGrowthIn(tester.element(board));
        await tester.tap(keyed('storyboard-se-lane-toggle-').first);
        await tester.pumpAndSettle();

        final labels = keyed('storyboard-lane-label-');
        expect(labels, findsWidgets, reason: 'LIVENESS — the lanes opened');
        expectOneRow(
          tester,
          label: labels.first,
          strip: keyed('storyboard-se-lane-row-').first,
          drawn: 26,
          growth: growth,
        );
        expect(wordsCutOff(labels), isEmpty);
      });

      testWidgets('the ring stands on the S row the rail draws — the row '
          'table grew with the rows', (tester) async {
        atTextScale(tester, scale);
        await openTheBoard(tester);
        await tester.tap(keyed('storyboard-se-label-').first);
        await tester.pumpAndSettle();

        final ring = tester.getRect(
          find.byKey(const ValueKey<String>('storyboard-standing-cell')),
        );
        final row = tester.getRect(keyed('storyboard-se-row-').first);
        expect(ring.top, closeTo(row.top, 0.5));
        expect(ring.height, closeTo(row.height, 0.5));
      });
    });
  }
}
