import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';

/// 🚨I-22 ③: A SCRUB REPAINTS ITS PANEL'S TICK LAYERS AND NOTHING ELSE OF IT.
///
/// A scrub moves the playhead the way a tick does, and at a far zoom every
/// move crosses into another cut — so what follows the cut under the
/// playhead (the storyboard's V row: its buttons act on that cut) changes on
/// every move. Rebuilt bare in the storyboard body's layout scope, it laid
/// the body out again and repainted the whole panel per move (measured at
/// 0.16px on a ten-minute film: the panel's paint-through 30ms of a 366ms
/// scrub sample). This drags each frame panel's ruler across short cuts and
/// names, at every move, any boundary of the dock region the panel sits in
/// waiting to repaint that is not a [TickLayer]'s (or inside one).
void main() {
  // Short cuts: a move of the drag crosses into the next.
  const cuts = 12;
  const frames = 8;

  Project project() => Project(
    id: const ProjectId('scrub-layers'),
    name: 'Scrub layers',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < cuts; i += 1)
            Cut(
              id: CutId('cut-$i'),
              name: 'cut-$i',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('cut-$i-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  /// Every boundary of the dock region around [panel] waiting to repaint in
  /// the scene that is not a tick layer's, or inside one. The REGION, not the
  /// panel: a layout in the panel marks the boundary above it, and that is
  /// the region's.
  List<String> strays(WidgetTester tester, Finder panel) {
    final region = find
        .ancestor(of: panel, matching: find.byType(StillRaster))
        .first;
    return [
      for (final stray in repaintStrays(
        tester.renderObject(region),
        allowed: {
          for (final layer in find
              .descendant(of: region, matching: find.byType(TickLayer))
              .evaluate())
            layer.renderObject!,
        },
      ))
        nameOfBoundary(stray),
    ];
  }

  for (final storyboard in [false, true]) {
    final view = storyboard ? 'storyboard' : 'timeline';
    testWidgets('a scrub along the $view ruler repaints its tick layers and '
        'nothing else of the panel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(initialProject: project()),
        ),
      );
      await tester.pumpAndSettle();
      if (storyboard) {
        await tester.tap(
          find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
        );
        await tester.pumpAndSettle();
      }
      final panel = find.byType(storyboard ? StoryboardPanel : TimelinePanel);
      final ruler = find.byKey(
        ValueKey<String>(
          storyboard ? 'storyboard-ruler' : 'timeline-frame-ruler-scrub-area',
        ),
      );
      final area = tester.getRect(ruler.first);
      // Over the middle of the ruler only: a scrub that reaches the edge
      // pans the view, and a pan repaints what it scrolls — the scroll's
      // cost, not the tick's.
      final step = area.width * 0.55 / 19;

      final gesture = await tester.startGesture(
        Offset(area.left + 4, area.center.dy),
      );
      await tester.pump();
      final moves = <String>[];
      for (var move = 1; move < 20; move += 1) {
        await gesture.moveBy(Offset(step, 0));
        // The move's frame, run to its layout and stopped before the paint.
        await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
        final now = strays(tester, panel);
        if (now.isNotEmpty) {
          moves.add('move $move:\n${now.join('\n')}');
        }
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(moves, isEmpty, reason: moves.join('\n\n'));
    });
  }
}
