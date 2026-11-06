import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart' show StoryboardPanel;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAlong;
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_selection_bands.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/repaint_strays.dart';

/// 🚨A STEP OF A ROW SWEEP REPAINTS THE SELECTION'S BANDS — NOTHING AROUND
/// THEM, AND IT BUILDS NO PANEL (a-row-pick-breaks-the-timeline-dock-image,
/// 11-06).
///
/// 🔬S5_BA 컷352, a sweep down the timeline's rail: the host heard the row
/// selection and built its whole panel at every step — the grid, both
/// viewports, the header and the scrollbars painted again, and the bottom
/// dock drawn live instead of from its image on 238 of 248 frames, 8ms of
/// raster a frame against the cells' 1.5. A span grows per pointer move, so
/// a step is a tick, and what it moves — the bands — stands on one.
///
/// Every rail that selects rows by a sweep, each swept with the mouse from
/// its first row's name, a row a step: the timeline's rail, the x-sheet's
/// header strip (the rail on its side) and the storyboard's rail.
void main() {
  const frames = 48;

  /// Eight drawing rows and six S rows on one track.
  Project project() => Project(
    id: const ProjectId('row-sweep'),
    name: 'Row sweep',
    createdAt: DateTime.utc(2026, 11, 6),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: frames,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var i = 0; i < 8; i += 1)
                Layer(
                  id: LayerId('l$i'),
                  name: 'L$i',
                  frames: const [],
                  timeline: const {},
                ),
            ],
          ),
        ],
        seLayers: [
          for (var i = 0; i < 6; i += 1)
            Layer(
              id: LayerId('s$i'),
              name: 'S$i',
              kind: LayerKind.se,
              frames: const [],
            ),
        ],
      ),
    ],
  );

  /// Each rail: the toggle that shows it, the prefix its rows' names wear,
  /// and which way its rows run.
  final rails = <String, (String?, String, Axis)>{
    'timeline\'s rail': (null, 'timeline-layer-name-l', Axis.vertical),
    'x-sheet\'s header strip': (
      'timeline-orientation-toggle-button',
      'xsheet-layer-name-l',
      Axis.horizontal,
    ),
    'storyboard\'s rail': (
      'timeline-mode-storyboard-button',
      'storyboard-layer-name-s',
      Axis.vertical,
    ),
  };

  bool aPanel(Element element) => switch (element.widget) {
    TimelinePanel() || StoryboardPanel() => true,
    _ => false,
  };

  /// Whether [boundary] is a band's tick — the one thing a step may move.
  bool aBandsTick(RenderObject boundary) =>
      nameOfBoundary(boundary, depth: 8).contains('TimelineRowSelectionBands');

  for (final MapEntry(key: rail, value: (toggle, prefix, axis))
      in rails.entries) {
    testWidgets('a step of a sweep down the $rail repaints its bands and '
        'builds no panel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(initialProject: project()),
        ),
      );
      await tester.pumpAndSettle();
      if (toggle != null) {
        await tester.tap(find.byKey(ValueKey<String>(toggle)));
        await tester.pumpAndSettle();
      }
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;

      final first = tester.getCenter(find.named('${prefix}0'));
      final second = tester.getCenter(find.named('${prefix}1'));
      final step = offsetAlong(
        axis,
        along: partAlong(axis, second - first),
        across: 0,
      );
      expect(step.distance, greaterThan(0), reason: 'premise: two rows');

      final gesture = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      // The first row of the sweep: it builds the bands' run once, and
      // stands on the row pressed.
      await gesture.moveBy(step);
      await tester.pump();
      await tester.pump();
      // A move inside a row spans what it spanned, and tells no one.
      final spanned = session.rowSelection.value;
      await gesture.moveBy(step / 4);
      await tester.pump();
      expect(
        session.rowSelection.value,
        same(spanned),
        reason: 'a move inside the row it reached is no new selection',
      );

      Set<String>? strayAtEveryStep;
      final built = <String>[];
      debugOnRebuildDirtyWidget = (element, _) {
        if (aPanel(element)) {
          built.add('${element.widget.runtimeType}');
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      for (var row = 2; row <= 4; row += 1) {
        final before = session.rowSelection.value.length;
        await gesture.moveBy(step);
        // One step, run to its layout and stopped before the paint, so
        // what waits to repaint can be read.
        await tester.pump(null, EnginePhase.layout);
        expect(
          session.rowSelection.value.length,
          before + 1,
          reason: 'premise: the step grew the selection by a row',
        );
        final waiting = {
          for (final view in tester.binding.renderViews)
            ...tickBoundariesUnder(view).where((tick) => tick.debugNeedsPaint),
        };
        expect(
          waiting.any(aBandsTick),
          isTrue,
          reason: 'CONTROL: the step moved the bands, on their tick',
        );
        final strays = {
          for (final view in tester.binding.renderViews)
            ...tickStraysUnder(view),
        };
        strayAtEveryStep = strayAtEveryStep?.intersection(strays) ?? strays;
        await tester.pump();
      }
      debugOnRebuildDirtyWidget = null;
      // What the sweep holds is drawn where it was swept: one band from the
      // row pressed to the fifth, and not past it.
      final band = find.descendant(
        of: find.byType(TimelineRowSelectionBands),
        matching: find.byType(DecoratedBox),
      );
      expect(band, findsOneWidget, reason: 'LIVENESS: one band for the run');
      final covered = tester.getRect(band);
      expect(covered.contains(first), isTrue, reason: 'the row pressed');
      expect(covered.contains(first + step * 4), isTrue, reason: 'the fifth');
      expect(covered.contains(first + step * 5), isFalse, reason: 'past it');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        strayAtEveryStep,
        isEmpty,
        reason: strayAtEveryStep!.join('\n\n'),
      );
      expect(built, isEmpty, reason: 'a step built a panel again: $built');
      expect(
        find.byType(TimelineRowSelectionBands),
        findsOneWidget,
        reason: 'premise: one rail draws the bands',
      );
    });
  }
}
