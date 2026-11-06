import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import '../../helpers/storyboard_host.dart';

/// 🗣️유저 2026-11-07 (card a-live-dock-frame-costs-a-whole-draw-Q4, c): a
/// drag on the frame strip held past the far end builds the room past it a
/// screen at a time, and lets it go when the hand does. ↩️It built the
/// cells the view had just reached, a cell or two a pointer move, and each
/// build laid every row out again — 30~55 ms a frame (main PC, 11-07).
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
  Future<void> expectAScreenAtATime(
    WidgetTester tester, {
    required Finder strip,
    required Axis axis,
    required ScrollPosition Function() position,
    int moves = 120,
  }) async {
    position().jumpTo(position().maxScrollExtent);
    await tester.pumpAndSettle();
    final area = tester.getRect(strip);
    final view = position().viewportDimension;
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
    var grewLast = false;
    for (var move = 0; move < moves || !grewLast; move += 1) {
      expect(move, lessThan(moves * 4), reason: 'the axis stopped growing');
      past += 0.5;
      await hand.moveTo(at(past));
      await tester.pump();
      grewLast = position().maxScrollExtent != built;
      if (grewLast) {
        growths += 1;
        built = position().maxScrollExtent;
      }
    }
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
  }

  testWidgets('the timeline\'s ruler', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(hooks: hooks(cursor, 160), layers: layers),
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
      pixelsPerFrame: 24,
    );
    final viewport = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    await expectAScreenAtATime(
      tester,
      strip: find.byKey(const ValueKey<String>('storyboard-ruler')),
      axis: Axis.horizontal,
      position: () =>
          tester.widget<SingleChildScrollView>(viewport).controller!.position,
    );
  });
}
