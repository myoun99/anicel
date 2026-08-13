import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cursor_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// ⑩ 뿌리 C — the collapsed row draws NOTHING of its own.
///
/// Half of it already mounted the real rail row; the frame half was a
/// private painter, and every symptom reported against the overlay was that
/// copy falling behind the original — blocks that did not move, names that
/// never appeared, SE rows shaped differently, an index that did not
/// update. There was no test on it at all, which is how a second drawing of
/// the same row stayed wrong quietly.
///
/// So these tests do not check pixels. They check WHICH WIDGET is doing the
/// drawing, because that is the property that keeps being true when the row
/// grows a column.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> collapseBottom(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
  }

  Finder inOverlay(Finder matching) => find.descendant(
    of: find.byType(CollapsedRowOverlay),
    matching: matching,
  );

  testWidgets('the frame half is the timeline\'s OWN row widget, not a '
      'second drawing of it', (tester) async {
    await pumpApp(tester);
    expect(find.byType(CollapsedRowOverlay), findsNothing);

    await collapseBottom(tester);

    expect(find.byType(CollapsedRowOverlay), findsOneWidget);
    expect(
      inOverlay(find.byType(TimelineFrameCellsRow)),
      findsOneWidget,
      reason: 'the cells are the shared row, so they cannot drift from it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail half is still the real rail row — both halves come '
      'from the same place now', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    expect(inOverlay(find.byType(TimelineLayerControlsRow)), findsOneWidget);
  });

  /// T16-ⓐ — mounting the real row brought the panel's GROUND with it.
  ///
  /// 유저 2026-08-13: 「원래 구상대로라면 프레임셀쪽은 바탕색은 싹 없애고
  /// 그리드선 띄우고 그 부분도 전체적으로 반투명하게 하기로 하지 않았나?」 —
  /// and it had been confirmed in 2026-08-10. Only the rail half knew how to
  /// take a ground off, so the fix for one half undid the look of the other.
  testWidgets('BOTH halves are chromeless — the row is laid on the artwork, '
      'not on a panel', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    expect(
      tester
          .widget<TimelineFrameCellsRow>(
            inOverlay(find.byType(TimelineFrameCellsRow)),
          )
          .chromeless,
      isTrue,
      reason: 'the cells half had no way to say this, which is why the ground '
          'came back when it started mounting the real row',
    );
    expect(
      tester
          .widget<TimelineLayerControlsRow>(
            inOverlay(find.byType(TimelineLayerControlsRow)),
          )
          .chromeless,
      isTrue,
    );
  });

  /// T16-ⓑ — 유저: 「레이어영역의 가로길이같은거 타임라인 그대로 가져와.
  /// 그래야 열의 규격이 맞을거니까」 · 「없는 버튼이 많고 폭 규격이 안 맞는다」.
  testWidgets('the rail half measures itself with the TIMELINE\'s numbers, '
      'and every column it gates on a callback is present', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    final rail = tester.widget<TimelineLayerControlsRow>(
      inOverlay(find.byType(TimelineLayerControlsRow)),
    );
    final cells = tester.widget<TimelineFrameCellsRow>(
      inOverlay(find.byType(TimelineFrameCellsRow)),
    );

    // ONE metrics object for the two halves: a row whose rail and cells
    // disagreed about a frame's width is a row with two opinions.
    expect(rail.metrics.frameCellWidth, cells.geometry.value.frameCellExtent);
    // The horizontal規格 the columns line up on comes from the panel.
    expect(
      rail.metrics.layerControlsWidth,
      TimelineGridMetrics.defaults.layerControlsWidth,
    );
    expect(
      rail.metrics.sectionLabelGutterWidth,
      TimelineGridMetrics.defaults.sectionLabelGutterWidth,
    );

    // 🚨A null callback is read as "this slot does not exist" by the row, so
    // leaving them out to mean "nothing is pressable here" DELETED buttons —
    // and shifted every column after them.
    expect(rail.onToggleLayerFx, isNotNull);
    expect(rail.onToggleLayerOnionSkin, isNotNull);
    expect(rail.onToggleLanes, isNotNull);
    expect(rail.onToggleLayerFillReference, isNotNull);
    expect(rail.onLayerBlendModeSelected, isNotNull);
  });

  testWidgets('WHERE YOU ARE is its own layer: the cursor rides a value '
      'channel so a frame tick repaints instead of rebuilding',
      (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    expect(
      inOverlay(find.byType(TimelineCursorLayer)),
      findsOneWidget,
      reason: 'the cells row is CURSOR-INDEPENDENT by design, so the '
          'playhead cannot live inside it — mounting the row without this '
          'would silently drop "where am I"',
    );
  });

  testWidgets('expanding puts it away again', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);
    expect(find.byType(CollapsedRowOverlay), findsOneWidget);

    await collapseBottom(tester);

    expect(find.byType(CollapsedRowOverlay), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
