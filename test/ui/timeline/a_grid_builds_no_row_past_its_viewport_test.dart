import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

import '../../helpers/timeline_host.dart';

/// The timeline builds NO ROW past its viewport (card frame-panels-build-in-
/// one-frame, 2026-10-28): two more on each side were made again every time
/// the tab opened, for nobody to see. Every row of the rail and of the cells
/// that is built stands at least partly inside the rows' viewport — at the
/// top of the rows and at their end alike.
void main() {
  testWidgets('every row the grid builds stands in its viewport', (
    tester,
  ) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(1400, 420),
    );
    // More rows than the viewport holds, so some must stay unbuilt.
    for (var added = 0; added < 10; added += 1) {
      session.layerStack.addLayer();
    }
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('timeline-vertical-scroll-viewport'),
    );

    List<Rect> rectsOf(Type row) => [
      for (final element in find.byType(row).evaluate())
        tester.getRect(find.byElementPredicate((e) => identical(e, element))),
    ];

    void expectEveryRowShown(String where) {
      final shown = tester.getRect(viewport);
      for (final row in [TimelineLayerControlsRow, TimelineFrameCellsRow]) {
        final rects = rectsOf(row);
        expect(rects, isNotEmpty, reason: '⛔전제: $where, $row stands');
        expect(
          rects.length,
          lessThan(session.layers.length),
          reason: '⛔전제: $where, not every row fits the viewport',
        );
        for (final rect in rects) {
          expect(
            rect.overlaps(shown),
            isTrue,
            reason: '$where: a $row at $rect, the viewport $shown',
          );
        }
      }
    }

    expectEveryRowShown('at the top');

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: viewport, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expectEveryRowShown('at the end');

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
