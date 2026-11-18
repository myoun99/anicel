import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart'
    show timelineRowWindowMargin;

import '../../helpers/timeline_host.dart';

/// The timeline builds NO ROW past a wheel notch beyond its viewport
/// ([timelineRowWindowMargin]): every row of the rail and of the cells that
/// is built stands at least partly inside the viewport grown by that notch
/// on each side — at the top of the rows and at their end alike.
///
/// 🗣️유저 2026-11-18 (a-timeline-wheel-notch-lays-out-the-rail-Q1 = B,
/// 「화면 밖 여유 행 — 늘」): the notch is built, the tab's opening frame
/// too. ↩️⛔From 2026-10-28 (card frame-panels-build-in-one-frame) this
/// pinned no row past the viewport itself — two more on each side were
/// made again every time the tab opened, for nobody to see.
void main() {
  testWidgets('every row the grid builds stands within a notch of its '
      'viewport', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(1400, 420),
    );
    // More rows than the viewport and its notches hold, so some must stay
    // unbuilt.
    for (var added = 0; added < 30; added += 1) {
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
      final view = tester.getRect(viewport);
      final reach = Rect.fromLTRB(
        view.left,
        view.top - timelineRowWindowMargin,
        view.right,
        view.bottom + timelineRowWindowMargin,
      );
      for (final row in [TimelineLayerControlsRow, TimelineFrameCellsRow]) {
        final rects = rectsOf(row);
        expect(rects, isNotEmpty, reason: '⛔전제: $where, $row stands');
        expect(
          rects.length,
          lessThan(session.layers.length),
          reason: '⛔전제: $where, not every row fits the window',
        );
        for (final rect in rects) {
          expect(
            rect.overlaps(reach),
            isTrue,
            reason: '$where: a $row at $rect, the window $reach',
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
