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
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
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

  Cut shortCut(String id, {int leadingGapFrames = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: frames,
    leadingGapFrames: leadingGapFrames,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [Layer(id: LayerId('$id-cel'), name: 'A', frames: const [])],
  );

  Project project() => Project(
    id: const ProjectId('scrub-layers'),
    name: 'Scrub layers',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [for (var i = 0; i < cuts; i += 1) shortCut('cut-$i')],
      ),
    ],
  );

  /// The open track's first cut, a long gap and a last cut — and a second
  /// track's short cuts under the whole of it, so a scrub through the gap
  /// parks and the stack it shows crosses that track's cuts.
  Project gapOverAnotherTrack() => Project(
    id: const ProjectId('scrub-layers-gap'),
    name: 'Scrub layers gap',
    createdAt: DateTime.utc(2026, 10, 10),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          shortCut('open'),
          shortCut('after', leadingGapFrames: frames * (cuts - 2)),
        ],
      ),
      Track(
        id: const TrackId('under'),
        name: 'Video 2',
        cuts: [for (var i = 0; i < cuts; i += 1) shortCut('under-$i')],
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

  // canvas-stack-relays-the-panel-per-scrub-crossing (I-22 계측, 09-28): where
  // a scrub parks, the canvas shows the track stack, which rebuilds as the
  // frame it follows crosses into another cut — bare under the panel
  // content's LayoutBuilder, that relaid out and repainted the whole canvas
  // panel. ↩️A scrub parked past the open cut over every other cut's frames
  // until I-57 ②; it crosses into those now and parks in a gap alone, where
  // the stack still crosses cuts — another track's.
  testWidgets('a scrub through a gap repaints the canvas\'s tick layers and '
      'nothing else of it, as the stack crosses another track\'s cuts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: gapOverAnotherTrack()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final canvas = find.ancestor(
      of: find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
      matching: find.byType(RepaintBoundary),
    );
    List<String> strays() => [
      for (final stray in repaintStrays(
        tester.renderObject(canvas.first),
        allowed: {
          for (final layer in find
              .descendant(of: canvas.first, matching: find.byType(TickLayer))
              .evaluate())
            layer.renderObject!,
        },
      ))
        nameOfBoundary(stray),
    ];
    final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
    final area = tester.getRect(ruler.first);
    final step = area.width * 0.55 / 19;

    final gesture = await tester.startGesture(
      Offset(area.left + 4, area.center.dy),
    );
    await tester.pump();
    final moves = <String>[];
    var parkedMoves = 0;
    final crossedUnder = <CutId>{};
    for (var move = 1; move < 20; move += 1) {
      // The move that takes the canvas INTO the gap swaps its content for
      // the track stack — once, and a new content is laid out whole. What
      // is measured is every move the stack was already showing.
      final parked = find.byType(CanvasTrackStackView).evaluate().isNotEmpty;
      await gesture.moveBy(Offset(step, 0));
      if (!parked) {
        // ⚠️A whole frame for a move not measured: the swap mounts new
        // repaint boundaries, and a frame stopped after its layout leaves
        // them queued with no layer — every later paint then stops at them
        // (a framework assertion), and each move after looks like a stray.
        await tester.pump(const Duration(milliseconds: 16));
        continue;
      }
      await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
      final now = strays();
      parkedMoves += 1;
      final at = session.editingSession.gapGlobalFrame;
      if (at != null) {
        crossedUnder.addAll([
          for (final under in session.rowSpans.trackStackContributionsAt(at))
            under.cut.id,
        ]);
      }
      if (now.isNotEmpty) {
        moves.add('move $move:\n${now.join('\n')}');
      }
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      parkedMoves,
      greaterThan(5),
      reason: '⛔premise: the scrub walked the gap with the stack shown',
    );
    expect(
      crossedUnder.length,
      greaterThan(2),
      reason: '⛔premise: the stack crossed cut after cut of the other track',
    );
    expect(moves, isEmpty, reason: moves.join('\n\n'));
  });
}
