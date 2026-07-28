import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline/timeline_cell_probe.dart';

void main() {
  testWidgets('horizontal mode renders integrated layer timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(orientation: TimelineOrientation.horizontal),
    );

    expect(find.byType(TimelinePanel), findsOneWidget);
    expect(find.byType(LayerTimelineGrid), findsOneWidget);
    // Add-layer moved to the HOST toolbar (R-toolbar round); the panel's
    // own entrance is the rail legend.
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('legend-layer')), findsOneWidget);
    expect(timelineCellInWindow(tester, 'layer-1', 0), isTrue);
  });

  testWidgets('vertical mode renders integrated X-sheet timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(orientation: TimelineOrientation.vertical));

    expect(find.byType(TimelinePanel), findsOneWidget);
    expect(find.byType(XSheetTimelineGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-add-layer-button')),
      findsNothing,
    );
    expect(
      timelineCellInWindow(tester, 'layer-1', 0, prefix: 'xsheet'),
      isTrue,
    );
  });

  testWidgets('horizontal mode displays visual stack order C B A', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.horizontal,
        layers: _abcLayers,
        activeLayerId: const LayerId('layer-c'),
      ),
    );

    final layerCTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('timeline-layer-row-layer-c')),
        )
        .dy;
    final layerBTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('timeline-layer-row-layer-b')),
        )
        .dy;
    final layerATop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('timeline-layer-row-layer-a')),
        )
        .dy;

    expect(layerCTop, lessThan(layerBTop));
    expect(layerBTop, lessThan(layerATop));
    expect(timelineCellInWindow(tester, 'layer-c', 0), isTrue);
  });

  testWidgets('vertical mode keeps raw XSheet order A B C left-to-right', (
    tester,
  ) async {
    LayerId? selectedLayerId;

    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.vertical,
        layers: _abcLayers,
        activeLayerId: const LayerId('layer-b'),
        onSelectLayer: (layerId) => selectedLayerId = layerId,
      ),
    );

    final layerALeft = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('xsheet-layer-header-layer-a')),
        )
        .dx;
    final layerBLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('xsheet-layer-header-layer-b')),
        )
        .dx;
    final layerCLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('xsheet-layer-header-layer-c')),
        )
        .dx;

    expect(layerALeft, lessThan(layerBLeft));
    expect(layerBLeft, lessThan(layerCLeft));
    expect(
      timelineCellInWindow(tester, 'layer-a', 0, prefix: 'xsheet'),
      isTrue,
    );
    expect(
      timelineCellInWindow(tester, 'layer-b', 0, prefix: 'xsheet'),
      isTrue,
    );
    expect(
      timelineCellInWindow(tester, 'layer-c', 0, prefix: 'xsheet'),
      isTrue,
    );

    await tapTimelineCell(tester, 'layer-c', 0, prefix: 'xsheet');

    expect(selectedLayerId, const LayerId('layer-c'));
  });

  testWidgets('renders provided timeline action toolbar', (tester) async {
    await tester.pumpWidget(
      _panel(
        timelineActionToolbar: const Text(
          'Timeline action toolbar content',
          key: ValueKey<String>('provided-timeline-toolbar'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('provided-timeline-toolbar')),
      findsOneWidget,
    );
    expect(find.text('Timeline action toolbar content'), findsOneWidget);
    expect(find.byType(LayerTimelineGrid), findsOneWidget);
  });

  testWidgets('exposure state callback is used in horizontal mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.horizontal,
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.held
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(
      timelineCellModel(
        tester,
        'layer-1',
        0,
        prefix: find.byType(XSheetTimelineGrid).evaluate().isEmpty
            ? 'timeline'
            : 'xsheet',
      ).semanticsLabel,
      'held exposure',
    );
  });

  testWidgets('exposure state callback is used in vertical mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.vertical,
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.held
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(
      timelineCellModel(
        tester,
        'layer-1',
        0,
        prefix: find.byType(XSheetTimelineGrid).evaluate().isEmpty
            ? 'timeline'
            : 'xsheet',
      ).semanticsLabel,
      'held exposure',
    );
  });

  testWidgets('renders only one orientation toggle control', (tester) async {
    await tester.pumpWidget(_panel());

    expect(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
      findsOneWidget,
    );
  });

  testWidgets('orientation toggle callback', (tester) async {
    TimelineOrientation? selectedOrientation;

    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.horizontal,
        onOrientationChanged: (orientation) =>
            selectedOrientation = orientation,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );

    expect(selectedOrientation, TimelineOrientation.vertical);
  });

  testWidgets('the rail legend LAYER heading is plain (R4 #3): no add '
      'flyout', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('legend-layer')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('legend-layer-add')),
      findsNothing,
    );
  });

  testWidgets('visibility callback is forwarded', (tester) async {
    LayerId? toggledLayerId;

    await tester.pumpWidget(
      _panel(onToggleLayerVisibility: (layerId) => toggledLayerId = layerId),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-visibility-layer-2')),
    );

    expect(toggledLayerId, const LayerId('layer-2'));
  });

  testWidgets('opacity callback is forwarded', (tester) async {
    LayerId? changedLayerId;
    double? changedOpacity;

    await tester.pumpWidget(
      _panel(
        onLayerOpacityChanged: (layerId, opacity) {
          changedLayerId = layerId;
          changedOpacity = opacity;
        },
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-layer-opacity-layer-1')),
      const Offset(-30, 0),
    );

    expect(changedLayerId, const LayerId('layer-1'));
    expect(changedOpacity, isNotNull);
  });

  testWidgets('select frame callback still works', (tester) async {
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _panel(onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex),
    );

    await tapTimelineCell(tester, 'layer-1', 3);

    expect(selectedFrameIndex, 3);
  });

  testWidgets('select layer callback still works', (tester) async {
    LayerId? selectedLayerId;

    await tester.pumpWidget(
      _panel(onSelectLayer: (layerId) => selectedLayerId = layerId),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-name-layer-2')),
    );

    expect(selectedLayerId, const LayerId('layer-2'));
  });

  testWidgets('forwards mark exposure states to timeline grids', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(timelineCellModel(tester, 'layer-1', 0).glyph, '●');
    expect(
      timelineCellModel(tester, 'layer-1', 0).semanticsLabel,
      'inbetween mark',
    );
  });

  testWidgets('highlights current frame without triangle label', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(currentFrameIndex: 3));

    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('timeline-current-frame-counter'),
            ),
          )
          .data,
      '4',
    );
    expect(find.text('▶ 4'), findsNothing);
  });

  testWidgets('passes frame names to horizontal and x-sheet renderers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(timelineCellModel(tester, 'layer-1', 0).glyph, 'A1');

    await tester.pumpWidget(
      _panel(
        orientation: TimelineOrientation.vertical,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(
      timelineCellModel(tester, 'layer-1', 0, prefix: 'xsheet').glyph,
      'A1',
    );
  });

  testWidgets('forwards selected cell and layer highlights to both grids', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(orientation: TimelineOrientation.horizontal, currentFrameIndex: 3),
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-cell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _panel(orientation: TimelineOrientation.vertical, currentFrameIndex: 3),
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-selected-cell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-selected-layer')),
      findsOneWidget,
    );
  });
}

Widget _panel({
  int currentFrameIndex = 0,
  int playbackFrameCount = 12,
  TimelineOrientation orientation = TimelineOrientation.horizontal,
  List<Layer>? layers,
  LayerId? activeLayerId,
  ValueChanged<LayerId>? onSelectLayer,
  ValueChanged<int>? onSelectFrame,
  VoidCallback? onAddLayer,
  ValueChanged<LayerId>? onToggleLayerVisibility,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  ValueChanged<TimelineOrientation>? onOrientationChanged,
  TimelineCellExposureState Function(Layer layer, int frameIndex)?
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  Widget? timelineActionToolbar,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers ?? _layers,
        activeLayerId: activeLayerId ?? const LayerId('layer-1'),
        frameCursor: ValueNotifier<int>(currentFrameIndex),
        playbackFrameCount: playbackFrameCount,
        exposureStateForLayer:
            exposureStateForLayer ??
            (layer, frameIndex) => frameIndex == 0
                ? TimelineCellExposureState.drawingStart
                : TimelineCellExposureState.uncovered,
        frameNameForLayer: frameNameForLayer,
        onSelectLayer: onSelectLayer ?? (_) {},
        onSelectFrame: onSelectFrame ?? (_) {},
        onAddLayer: onAddLayer ?? () {},
        onToggleLayerVisibility: onToggleLayerVisibility ?? (_) {},
        onLayerOpacityChanged: onLayerOpacityChanged ?? (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: orientation,
        onOrientationChanged: onOrientationChanged ?? (_) {},
        timelineActionToolbar: timelineActionToolbar,
      ),
    ),
  );
}

final _layers = [
  Layer(
    id: const LayerId('layer-1'),
    name: 'Layer 1',
    frames: [
      Frame(id: const FrameId('frame-1'), duration: 1, strokes: const []),
    ],
  ),
  Layer(
    id: const LayerId('layer-2'),
    name: 'Layer 2',
    opacity: 0.5,
    frames: [
      Frame(id: const FrameId('frame-2'), duration: 1, strokes: const []),
    ],
  ),
];

final _abcLayers = [
  Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
    ],
  ),
  Layer(
    id: const LayerId('layer-b'),
    name: 'B',
    frames: [
      Frame(id: const FrameId('frame-b'), duration: 1, strokes: const []),
    ],
  ),
  Layer(
    id: const LayerId('layer-c'),
    name: 'C',
    frames: [
      Frame(id: const FrameId('frame-c'), duration: 1, strokes: const []),
    ],
  ),
];
