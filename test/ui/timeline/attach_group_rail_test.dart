import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// UI-R20 P6 (#8–#11): the attach-layer rail — placement arrows instead
/// of kind icons, the group fold twirl, and the + flyout entrance.
void main() {
  Layer layer(
    String id, {
    LayerId? attachedTo,
    AttachedPlacement placement = AttachedPlacement.above,
  }) {
    return Layer(
      id: LayerId(id),
      name: id,
      frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
      timeline: const {},
      attachedToLayerId: attachedTo,
      attachedPlacement: placement,
    );
  }

  Widget grid({
    required List<Layer> layers,
    LayerId activeLayerId = const LayerId('base'),
    Set<LayerId> collapsedAttachBaseIds = const {},
    ValueChanged<LayerId>? onToggleAttachGroup,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 260,
          child: LayerTimelineGrid(
            layers: layers,
            activeLayerId: activeLayerId,
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
            collapsedAttachBaseIds: collapsedAttachBaseIds,
            onToggleAttachGroup: onToggleAttachGroup,
          ),
        ),
      ),
    );
  }

  final baseWithGroup = [
    layer('base'),
    layer('up1', attachedTo: const LayerId('base')),
    layer(
      'down1',
      attachedTo: const LayerId('base'),
      placement: AttachedPlacement.below,
    ),
    layer('plain'),
  ];

  testWidgets('attach rows carry the placement arrow as their ONLY mark — '
      'up-attach bends up-right (flipped), down-attach down-right — and '
      'no kind icon (UI-R20 #10)', (tester) async {
    await tester.pumpWidget(grid(layers: baseWithGroup));

    // The NEAREST Transform ancestor is the Transform.flip wrapper
    // (find.ancestor walks inside-out, so .first is the closest).
    Transform flipOf(String id) => tester.widget<Transform>(
      find
          .ancestor(
            of: find.byKey(ValueKey<String>('timeline-layer-attach-arrow-$id')),
            matching: find.byType(Transform),
          )
          .first,
    );
    // Transform.flip(flipY: true) mirrors vertically: scaleY < 0.
    expect(flipOf('up1').transform.storage[5], lessThan(0));
    expect(flipOf('down1').transform.storage[5], greaterThan(0));

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-up1')),
      findsNothing,
      reason: 'the arrow IS the type mark on attach rows',
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-base')),
      findsOneWidget,
      reason: 'regular rows keep their kind icon',
    );
  });

  testWidgets('the fold twirl shows ONLY on bases that carry attach rows; '
      'tapping reports the base id (UI-R20 #9)', (tester) async {
    final toggled = <LayerId>[];
    await tester.pumpWidget(
      grid(layers: baseWithGroup, onToggleAttachGroup: toggled.add),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-attach-twirl-base')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-attach-twirl-plain')),
      findsNothing,
      reason: 'no group, no twirl',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-attach-twirl-base')),
    );
    expect(toggled, [const LayerId('base')]);
  });

  testWidgets('a folded group renders no attach rows — except the active '
      'attach row, which stays visible (UI-R20 #9)', (tester) async {
    await tester.pumpWidget(
      grid(
        layers: baseWithGroup,
        collapsedAttachBaseIds: {const LayerId('base')},
        onToggleAttachGroup: (_) {},
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-up1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-down1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-base')),
      findsOneWidget,
    );

    // The ACTIVE attach row survives its group's fold (the row-filter
    // exemption rule).
    await tester.pumpWidget(
      grid(
        layers: baseWithGroup,
        activeLayerId: const LayerId('up1'),
        collapsedAttachBaseIds: {const LayerId('base')},
        onToggleAttachGroup: (_) {},
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-up1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-down1')),
      findsNothing,
    );
  });

  testWidgets('while a drag previews the BASE, the attach row\'s gate '
      're-derives the mirror live from the previewed base (UI-R20 #8)', (
    tester,
  ) async {
    final base = Layer(
      id: const LayerId('base'),
      name: 'base',
      frames: [Frame(id: const FrameId('b1'), duration: 1, strokes: const [])],
      timeline: const {0: TimelineExposure.drawing(FrameId('b1'), length: 2)},
    );
    final attach = Layer(
      id: const LayerId('up1'),
      name: '+1',
      frames: [Frame(id: const FrameId('a1'), duration: 1, strokes: const [])],
      timeline: const {},
      attachedToLayerId: const LayerId('base'),
      baseFrameLinks: {const FrameId('b1'): const FrameId('a1')},
    );
    final display = attachedDisplayLayer(attached: attach, base: base);
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    Layer? built;

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineDragPreviewRowGate(
          dragPreview: preview,
          layer: display,
          rowBuilder: (context, layer) {
            built = layer;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(built!.timeline[0]!.length, 2);

    // A comma drag stretches the BASE block to 5: the attach mirror
    // follows the preview live.
    preview.value = ExposureEdgeDragPreview(
      previewLayer: base.copyWith(
        timeline: const {0: TimelineExposure.drawing(FrameId('b1'), length: 5)},
      ),
    );
    await tester.pump();
    expect(built!.timeline[0]!.length, 5);
    expect(built!.timeline[0]!.ghost, isTrue, reason: 'mirror stays ghost');
    expect(built!.timeline[0]!.frameId, const FrameId('a1'));

    // Clearing the preview returns the repository mirror.
    preview.value = null;
    await tester.pump();
    expect(built!.timeline[0]!.length, 2);
  });

  testWidgets('a FREE attach row never re-derives from a base preview '
      '(UI-R21 #3): its own timeline stays put through the drag', (
    tester,
  ) async {
    final freeAttach = Layer(
      id: const LayerId('free1'),
      name: '+1',
      frames: [Frame(id: const FrameId('a1'), duration: 1, strokes: const [])],
      timeline: const {3: TimelineExposure.drawing(FrameId('a1'), length: 2)},
      attachedToLayerId: const LayerId('base'),
      attachedMode: AttachedMode.free,
    );
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    Layer? built;

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineDragPreviewRowGate(
          dragPreview: preview,
          layer: freeAttach,
          rowBuilder: (context, layer) {
            built = layer;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(identical(built, freeAttach), isTrue);

    preview.value = ExposureEdgeDragPreview(
      previewLayer: Layer(
        id: const LayerId('base'),
        name: 'base',
        frames: const [],
        timeline: const {0: TimelineExposure.drawing(FrameId('b1'), length: 9)},
      ),
    );
    await tester.pump();
    expect(
      identical(built, freeAttach),
      isTrue,
      reason: 'a base drag must never overwrite a free row\'s own timeline',
    );
  });

  testWidgets('the timeline + flyout adds attach layers riding the active '
      'layer, named by side (+1 above, -1 below) and shown as attach-arrow '
      'rows (UI-R20 #8 #11)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // R26 #29: attach names hang off the BASE's name (B+1, B-1), so the
    // rail assertions match the SUFFIX.
    Finder attachNamed(String suffix) => find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.endsWith(suffix) ?? false),
    );

    Future<void> addViaFlyout(String itemKey) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(itemKey)));
      await tester.pumpAndSettle();
    }

    await addViaFlyout('add-layer-attach-above');
    expect(attachNamed('+1'), findsWidgets);

    // The fresh attach row is active; adding below still targets ITS base.
    await addViaFlyout('add-layer-attach-below');
    expect(attachNamed('-1'), findsWidgets);

    // Both rows render with the placement arrow (no kind icon), and the
    // base row grew the fold twirl.
    final arrows = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('timeline-layer-attach-arrow-');
    });
    expect(arrows, findsNWidgets(2));
    final twirls = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('timeline-attach-twirl-');
    });
    expect(twirls, findsOneWidget);

    // Folding while an attach row is ACTIVE hands the selection to the
    // BASE (UI-R24 #4), so the whole group actually disappears — no
    // "active row stays and blocks the fold" limbo.
    await tester.tap(twirls);
    await tester.pumpAndSettle();
    expect(attachNamed('+1'), findsNothing);
    expect(attachNamed('-1'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
  });
}
