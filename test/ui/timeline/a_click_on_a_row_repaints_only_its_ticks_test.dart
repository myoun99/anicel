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
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/repaint_strays.dart';

/// 🚨A CLICK THAT MOVES THE STAND REPAINTS TICKS, AND NOTHING ELSE OF THE
/// REGION IT IS IN (a-row-pick-breaks-the-timeline-dock-image, 11-06).
///
/// 🔬S5_BA 컷352, profile: a click on a rail row drew the bottom dock live
/// on 43–47 of 59 frames, 7.3–8.5ms of raster against a cell click's 1.5.
/// The stand rebuilt the plates of the two rows it moved between and the
/// grid sheet's grounds — each in a layout scope far above it, the rail's
/// and the grid's — so the rail was laid out again and the timeline panel
/// around it repainted, and the rows' viewport with it. Both stand on ticks
/// now, as a cells row does.
///
/// Every rail a click stands on a row in, clicked on its rows' names with
/// the mouse: the timeline's rail, the x-sheet's header strip (the rail on
/// its side) and the storyboard's rail.
void main() {
  const frames = 48;

  /// Eight drawing rows and six S rows on one track.
  Project project() => Project(
    id: const ProjectId('row-click'),
    name: 'Row click',
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

  /// Each rail: the toggle that shows it, and the prefix its rows' names
  /// wear — which is the prefix of the layers they stand for.
  final rails = <String, (String?, String, String)>{
    'timeline\'s rail': (null, 'timeline-layer-name-', 'l'),
    'x-sheet\'s header strip': (
      'timeline-orientation-toggle-button',
      'xsheet-layer-name-',
      'l',
    ),
    'storyboard\'s rail': (
      'timeline-mode-storyboard-button',
      'storyboard-layer-name-',
      's',
    ),
  };

  for (final MapEntry(key: rail, value: (toggle, prefix, layer))
      in rails.entries) {
    testWidgets('a click on a row of the $rail repaints ticks alone in '
        'its region', (tester) async {
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
      final region = tester.renderObject(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) => switch (widget) {
                  TimelinePanel() || StoryboardPanel() => true,
                  _ => false,
                },
              ),
              matching: find.byType(StillRaster),
            )
            .first,
      );

      // One mouse, resting over the rail before it clicks: what its coming
      // in lights is a hover's, not a click's.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.named('$prefix${layer}0')),
      );
      await tester.pumpAndSettle();

      final strays = <String>{};
      for (var row = 1; row <= 3; row += 1) {
        final at = tester.getCenter(find.named('$prefix$layer$row'));
        await mouse.moveTo(at);
        await tester.pumpAndSettle();
        // Marked while the region draws from its image, a boundary WAITS:
        // what a click marks is what it adds.
        final resting = tickStraysUnder(region).toSet();
        await mouse.down(at);
        // The click, run to its layout and stopped before the paint, so
        // what waits to repaint can be read.
        await tester.pump(null, EnginePhase.layout);
        expect(
          session.activeLayerId,
          LayerId('$layer$row'),
          reason: 'premise: the click stood on the row',
        );
        expect(
          tickBoundariesUnder(region).where((tick) => tick.debugNeedsPaint),
          isNotEmpty,
          reason: 'CONTROL: the stand repainted its ticks',
        );
        strays.addAll(
          tickStraysUnder(region).where((name) => !resting.contains(name)),
        );
        await tester.pump();
        await mouse.up();
        // Past a double click's wait, so the next press is a click again.
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }

      expect(strays, isEmpty, reason: strays.join('\n\n'));
    });
  }
}
