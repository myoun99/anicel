import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/widgets/named.dart';

/// A STEP OF THE RAIL SPLITTER BUILDS NO ROW (row-extent-drag-rebuilds-
/// every-visible-row, 2026-10-30): the step moves where the rail's window
/// ends and how far the frames' view reaches, and both are laid out and
/// painted — never built.
///
/// ↩️Every row of cells read the view's breadth as it was built, so each
/// pixel missed every row's keep at once: 299 widgets a step on the
/// timeline, 292 on the x-sheet (the default project, measured; 147 and
/// 152 after — the grid's frame around the rows, its scrollbars and its
/// ruler). On 10-11, before the rows' window kept them, it was 828 and every
/// rail row too.
///
/// ↩️The storyboard's strips held the breadth to cut the window their pieces
/// are built for, and a pixel moved the window's end a cell at a time
/// (storyboard-strips-build-on-every-view-pixel, 10-30): 273 a step, 162
/// after. They key on the spans the window reaches now
/// (`timelineFrameWindowReachFor`), and the rows that cut no window hold no
/// breadth at all.
///
/// ⚠️The sheet's column BOX (`xsheet-column-…`) is laid fresh on every
/// pass by design, outside the kept column (F-244) — what is held to
/// nothing here is what the box holds.
void main() {
  final aRow = RegExp(
    '^(timeline-rail-row-|timeline-row-|timeline-frame-row-area-'
    '|xsheet-frame-column-area-|xsheet-row-cells-'
    '|timeline-range-gesture-|storyboard-)',
  );

  for (final (grid, toggle, step) in [
    ('timeline', null, const Offset(-1, 0)),
    ('x-sheet', 'timeline-orientation-toggle-button', const Offset(0, -1)),
    ('storyboard', 'timeline-mode-storyboard-button', const Offset(-1, 0)),
  ]) {
    testWidgets('one pixel of the $grid\'s rail splitter builds none of its '
        'rows', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();
      if (toggle != null) {
        await tester.tap(find.byKey(ValueKey<String>(toggle)));
        await tester.pumpAndSettle();
      }
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LayerRailSplitter).first),
      );
      // Past any slop, so the step measured is a step of the drag.
      await gesture.moveBy(step * 30);
      await tester.pump();

      final built = <String>[];
      var elements = 0;
      await gesture.moveBy(step);
      debugOnRebuildDirtyWidget = (element, _) {
        elements += 1;
        if (element.widget case Named(:final name?)) {
          built.add(name);
        }
      };
      try {
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }

      expect(
        built.where(aRow.hasMatch),
        isEmpty,
        reason: 'the step built rows again: $built',
      );
      expect(
        elements,
        greaterThan(0),
        reason: 'CONTROL: the step built what it moves around the rows',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }
}
