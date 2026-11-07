import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import '../../helpers/scrollable_of.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_zoom.dart';

/// 🗣️유저 2026-11-07 (card a-live-dock-frame-costs-a-whole-draw-Q5, a): a
/// drag on the frame strip held past the far end builds the room past it a
/// screen at a time, and lets it go when the hand does — the drag alone; a
/// walk past the end builds what it reaches (`a_flip_reaches_past_the_end`).
/// ↩️It built the cells the view had just reached, a cell or two a pointer
/// move, and each build laid every row out again.
///
/// Every panel that runs a frame axis, through its own strip and a real
/// pointer: the timeline's ruler, the x-sheet's rail, the storyboard's
/// ruler.
void main() {
  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );
  final layers = <Layer>[drawing('draw-0'), drawing('draw-1')];

  TimelineGridHooks hooks(ValueNotifier<int> cursor, int frames) =>
      TimelineGridHooks(
        activeLayer: ValueNotifier(const LayerId('draw-0')),
        frameCursor: cursor,
        playbackFrameCount: frames,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
      );

  /// Stands the axis behind [position] at its end, holds a drag on [strip]
  /// past the far end of its view for [moves] pointer moves — each a hair
  /// further out, as a hand pushing on does — and on until the axis grows
  /// once more, then lets go.
  ///
  /// ⚠️On frames of [cell] that the view holds more than a second of: the
  /// room shrinks back by a second at the most (`endlessTrailingFrames`), so
  /// on a view of fewer cells a move on could never shrink a screen of it.
  Future<void> expectAScreenAtATime(
    WidgetTester tester, {
    required Finder strip,
    required Axis axis,
    required ScrollPosition Function() position,
    required double cell,
    int moves = 120,
  }) async {
    position().jumpTo(position().maxScrollExtent);
    await tester.pumpAndSettle();
    final area = tester.getRect(strip);
    final view = position().viewportDimension;
    expect(view / cell, greaterThan(24 + 8), reason: '⛔premise: wide');
    final from = position().pixels;
    Offset at(double along) => offsetAlong(
      axis,
      along: startAlong(axis, area) + along,
      across: partAcross(axis, area.center),
    );

    final hand = await tester.startGesture(
      at(extentAlong(axis, area.size) - 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    var past = extentAlong(axis, area.size) + 4;
    var built = position().maxScrollExtent;
    var growths = 0;
    var shrinks = 0;
    var grewLast = false;
    for (var move = 0; move < moves || !grewLast; move += 1) {
      expect(move, lessThan(moves * 4), reason: 'the axis stopped growing');
      past += 0.5;
      await hand.moveTo(at(past));
      await tester.pump();
      grewLast = position().maxScrollExtent > built;
      if (position().maxScrollExtent < built) {
        shrinks += 1;
      }
      if (grewLast) {
        growths += 1;
      }
      built = position().maxScrollExtent;
    }
    expect(shrinks, 0, reason: 'the room shrank under a hand moving on');
    final panned = position().pixels - from;
    expect(panned, greaterThan(view * 2), reason: '⛔premise: two screens');
    // A screen at a time: as many builds as screens the view went past the
    // end, and the one it started on.
    expect(
      growths,
      lessThanOrEqualTo((panned / view).ceil() + 1),
      reason: 'built again ${growths}× over ${panned.round()} px past the '
          'end, a ${view.round()} px view',
    );
    final runway = position().maxScrollExtent - position().pixels;
    expect(runway, greaterThan(view / 2), reason: '⛔premise: let go with a '
        'runway ahead');

    await hand.up();
    await tester.pumpAndSettle();
    // Let go, the room is what the view reaches — no screen of it ahead.
    expect(
      position().maxScrollExtent - position().pixels,
      lessThan(view / 2),
      reason: 'the runway stayed after the hand let go',
    );

    // Held again, past the end until a runway is built, then pulled back
    // past the near end: moving back, the room shrinks as it always did,
    // the hand still down.
    final again = await tester.startGesture(
      at(extentAlong(axis, area.size) - 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final rested = position().maxScrollExtent;
    past = extentAlong(axis, area.size) + 4;
    for (var move = 0; position().maxScrollExtent <= rested; move += 1) {
      expect(move, lessThan(moves), reason: '⛔premise: grew again');
      past += 0.5;
      await again.moveTo(at(past));
      await tester.pump();
    }
    final grown = position().maxScrollExtent;
    var near = -4.0;
    for (var move = 0; move < 8; move += 1) {
      near -= 0.5;
      await again.moveTo(at(near));
      await tester.pump();
    }
    expect(
      position().maxScrollExtent,
      lessThan(grown),
      reason: 'pulled back, the runway stayed ahead',
    );
    await again.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the timeline\'s ruler', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: hooks(cursor, 160),
            layers: layers,
            metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectAScreenAtATime(
      tester,
      strip: find.byKey(
        const ValueKey<String>('timeline-frame-ruler-scrub-area'),
      ),
      axis: Axis.horizontal,
      cell: 12,
      position: () => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position,
    );
  });

  testWidgets('the x-sheet\'s rail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayer: ValueNotifier(const LayerId('draw-0')),
            frameCursor: cursor,
            playbackFrameCount: 240,
            pixelsPerFrame: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('xsheet-frame-vertical-viewport'),
    );
    await expectAScreenAtATime(
      tester,
      strip: find.byKey(
        const ValueKey<String>('xsheet-frame-rail-scrub-area'),
      ),
      axis: Axis.vertical,
      cell: 12,
      position: () =>
          tester.widget<SingleChildScrollView>(viewport).controller!.position,
    );
  });

  testWidgets('the storyboard\'s ruler', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.repository.updateCutDuration(
      cutId: session.repository.requireProject().tracks.first.cuts.first.id,
      duration: 200,
    );
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(900, 600),
      pixelsPerFrame: 8,
    );
    final viewport = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    await expectAScreenAtATime(
      tester,
      strip: find.byKey(const ValueKey<String>('storyboard-ruler')),
      axis: Axis.horizontal,
      cell: 8,
      position: () =>
          tester.widget<SingleChildScrollView>(viewport).controller!.position,
    );
  });

  // Only a view past the built end grows the runway: a zoom out standing at
  // the end grows the axis too — the view reaches more frames — and builds
  // what it reaches, no screen ahead of it. 🧪Built a screen ahead, the
  // timeline's room past the view went from 14 px to 471 (11-07).
  group('a zoom out standing at the end builds no runway —', () {
    Project film() => Project(
      id: const ProjectId('runway-zoom'),
      name: 'Runway zoom',
      createdAt: DateTime.utc(2026, 11, 7),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'cut',
              duration: 240,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: const LayerId('cut-layer'),
                  name: 'A',
                  frames: const [],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    for (final (panel, opener, frames) in [
      (
        'the timeline',
        null,
        'timeline-frame-scroll-viewport',
      ),
      (
        'the x-sheet',
        'timeline-orientation-toggle-button',
        'xsheet-frame-vertical-viewport',
      ),
      (
        'the storyboard',
        'timeline-mode-storyboard-button',
        'storyboard-timeline-horizontal-viewport',
      ),
    ]) {
      testWidgets(panel, (tester) async {
        await tester.binding.setSurfaceSize(const Size(1500, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: HomePage(initialProject: film()),
          ),
        );
        await tester.pumpAndSettle();
        if (opener != null) {
          await tester.tap(find.byKey(ValueKey<String>(opener)).first);
          await tester.pumpAndSettle();
        }
        ScrollPosition axis() => scrollableOf(
          tester,
          find.byKey(ValueKey<String>(frames)),
        ).controller!.position;
        axis().jumpTo(axis().maxScrollExtent);
        await tester.pumpAndSettle();
        final view = axis().viewportDimension;
        final stood = axis().pixels;

        await dragTimelineZoom(tester, -30);

        expect(axis().pixels, lessThan(stood), reason: '⛔premise: zoomed');
        expect(
          axis().maxScrollExtent - axis().pixels,
          lessThan(view / 2),
          reason: 'a screen built ahead of a view that did not go past it',
        );
      });
    }
  });
}
