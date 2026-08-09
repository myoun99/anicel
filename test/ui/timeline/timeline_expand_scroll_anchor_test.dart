import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// UI-R5 #3: expanding an attach group must not SCROLL the timeline.
///
/// The wanted behaviour (user, 08-09): the rows below the insertion move
/// down, so the standing cursor and the twirl the user just tapped drift
/// apart. That drift IS the insertion — it must stay. What was reported is
/// the sequel: with the view scrolled down, the offset then slid by exactly
/// the inserted rows and put everything back where it was.
///
/// 🚨The defect needs a COLLAPSE first. A shrink corrects the position's
/// pixels silently (no listener call), so the grid's cached offset freezes
/// at the pre-collapse value; the expand is merely when that corpse gets up.
/// A fixture that only ever expands is green either way.
void main() {
  Layer layer(String id, {LayerId? attachedTo}) {
    return Layer(
      id: LayerId(id),
      name: id,
      frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
      timeline: const {},
      attachedToLayerId: attachedTo,
    );
  }

  // The group sits at the END of the model so its twirl rides the BOTTOM of
  // the row list: the user has to see the twirl to tap it, and the reported
  // state is 'scrolled down'.
  final layers = <Layer>[
    for (var index = 1; index <= 8; index++) layer('plain$index'),
    layer('base'),
    layer('up1', attachedTo: const LayerId('base')),
    layer('up2', attachedTo: const LayerId('base')),
  ];

  /// The measured geometry from the hands-on repro: 28px rows over a body
  /// viewport a few rows short of the content.
  Widget host({required ValueNotifier<Set<LayerId>> collapsed}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 264,
          child: ValueListenableBuilder<Set<LayerId>>(
            valueListenable: collapsed,
            builder: (context, collapsedIds, _) => LayerTimelineGrid(
              layers: layers,
              activeLayerId: const LayerId('base'),
              frameCursor: ValueNotifier<int>(0),
              playbackFrameCount: 12,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              collapsedAttachBaseIds: collapsedIds,
              onToggleAttachGroup: (baseId) {
                collapsed.value = collapsedIds.contains(baseId)
                    ? (Set<LayerId>.from(collapsedIds)..remove(baseId))
                    : (Set<LayerId>.from(collapsedIds)..add(baseId));
              },
            ),
          ),
        ),
      ),
    );
  }

  ScrollController controllerOf(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
      )
      .controller!;

  Future<void> tapTwirl(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-attach-twirl-base')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('folding a group and unfolding it again leaves the view where '
      'the user parked it', (tester) async {
    final collapsed = ValueNotifier<Set<LayerId>>(const {});
    addTearDown(collapsed.dispose);
    await tester.pumpWidget(host(collapsed: collapsed));
    await tester.pumpAndSettle();

    final controller = controllerOf(tester);
    final expandedMax = controller.position.maxScrollExtent;
    expect(
      expandedMax,
      greaterThan(0),
      reason: 'the fixture must overflow, or nothing can scroll at all',
    );

    // Parked at the bottom — the state the user reported from. (Also the
    // real path: our own scrollbar drives the view with jumpTo.)
    controller.jumpTo(expandedMax);
    await tester.pumpAndSettle();

    await tapTwirl(tester);
    final collapsedMax = controller.position.maxScrollExtent;
    expect(
      collapsedMax,
      lessThan(expandedMax),
      reason: 'the fixture must really have folded rows away',
    );
    expect(
      controller.offset,
      moreOrLessEquals(collapsedMax),
      reason:
          'the rows shrank out from under an offset that is now out of '
          'range; the view has to come back or the leading spacer inflates '
          'and pushes every section down (UI-R9 #9)',
    );

    await tapTwirl(tester);
    expect(
      controller.position.maxScrollExtent,
      moreOrLessEquals(expandedMax),
      reason: 'the fixture must really have grown the content back',
    );
    expect(
      controller.offset,
      moreOrLessEquals(collapsedMax),
      reason:
          'growing the rows must not move the view. The two rows appear '
          'ABOVE the base and push it down — that drift is what the user '
          'asked to see, and scrolling to the new bottom cancels it.',
    );
  });

  testWidgets('an expand with no fold behind it also leaves the view alone', (
    tester,
  ) async {
    final collapsed = ValueNotifier<Set<LayerId>>({const LayerId('base')});
    addTearDown(collapsed.dispose);
    await tester.pumpWidget(host(collapsed: collapsed));
    await tester.pumpAndSettle();

    final controller = controllerOf(tester);
    final collapsedMax = controller.position.maxScrollExtent;
    controller.jumpTo(collapsedMax);
    await tester.pumpAndSettle();

    await tapTwirl(tester);

    expect(controller.position.maxScrollExtent, greaterThan(collapsedMax));
    expect(controller.offset, moreOrLessEquals(collapsedMax));
  });
}
