import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

void main() {
  group('LayerTimelineGrid extracted composition', () {
    testWidgets('extracted frame-grid structure appears together', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(currentFrameIndex: 3));

      _expectKeyOnce('timeline-frame-grid-area');
      _expectKeyOnce('timeline-horizontal-scrollbar-viewport');
      _expectKeyOnce('timeline-frame-scroll-viewport');
      _expectKeyOnce('timeline-frame-scroll-content');
      _expectKeyOnce('timeline-frame-rows-scroll-body');
    });

    testWidgets('scrollbar rails and slots appear together', (tester) async {
      await tester.pumpWidget(_grid(currentFrameIndex: 3));

      _expectKeyOnce('timeline-horizontal-scrollbar');
      _expectKeyOnce('timeline-bottom-scrollbar-rail');
      _expectKeyOnce('timeline-vertical-scrollbar-slot');
      _expectKeyOnce('timeline-vertical-scrollbar');
    });

    testWidgets('layer controls rail remains outside frame scroll content', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(currentFrameIndex: 3));

      final rail = _key('timeline-layer-controls-rail');
      final content = _key('timeline-frame-scroll-content');

      expect(rail, findsOneWidget);
      expect(content, findsOneWidget);
      expect(find.descendant(of: content, matching: rail), findsNothing);
    });

    testWidgets('body rows, cut boundary, and playhead are in scroll content', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(currentFrameIndex: 3));

      final content = _key('timeline-frame-scroll-content');
      final rowsBody = _key('timeline-frame-rows-scroll-body');
      final cutEndBoundary = _key('timeline-cut-end-boundary');
      final playhead = _key('timeline-playhead');
      final playheadColumn = _key('timeline-playhead-column');

      expect(content, findsOneWidget);
      expect(rowsBody, findsOneWidget);
      expect(cutEndBoundary, findsOneWidget);
      expect(playhead, findsOneWidget);
      expect(playheadColumn, findsOneWidget);
      expect(find.descendant(of: content, matching: rowsBody), findsOneWidget);
      expect(
        find.descendant(of: content, matching: cutEndBoundary),
        findsOneWidget,
      );
      expect(find.descendant(of: content, matching: playhead), findsOneWidget);
      expect(
        find.descendant(of: playhead, matching: playheadColumn),
        findsOneWidget,
      );
    });

    testWidgets('row and cell keys still appear without duplicate structures', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(currentFrameIndex: 3));

      _expectKeyOnce('timeline-frame-row-area-layer-1');
      _expectKeyOnce('timeline-frame-row-area-layer-2');
      _expectKeyOnce('timeline-row-cells-layer-1');
      _expectKeyOnce('timeline-row-cells-layer-2');

      for (final key in _structuralKeys) {
        _expectKeyOnce(key);
      }
    });
  });
}

const _structuralKeys = <String>[
  'timeline-layer-controls-rail',
  'timeline-frame-grid-area',
  'timeline-horizontal-scrollbar-viewport',
  'timeline-frame-scroll-viewport',
  'timeline-frame-scroll-content',
  'timeline-frame-rows-scroll-body',
  'timeline-cut-end-boundary',
  'timeline-horizontal-scrollbar',
  'timeline-bottom-scrollbar-rail',
  'timeline-vertical-scrollbar-slot',
  'timeline-vertical-scrollbar',
  'timeline-playhead',
  'timeline-playhead-column',
];

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void _expectKeyOnce(String key) {
  expect(_key(key), findsOneWidget, reason: key);
}

Widget _grid({int currentFrameIndex = 0, int playbackFrameCount = 24}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 260,
        child: LayerTimelineGrid(
          layers: _layers,
          activeLayerId: const LayerId('layer-1'),
          frameCursor: ValueNotifier<int>(currentFrameIndex),
          playbackFrameCount: playbackFrameCount,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
        ),
      ),
    ),
  );
}

final _layers = [
  _layer(id: 'layer-1', name: 'Layer 1'),
  _layer(id: 'layer-2', name: 'Layer 2', opacity: 0.5),
];

Layer _layer({
  required String id,
  required String name,
  double opacity = 1,
  LayerKind kind = LayerKind.animation,
}) {
  final layerNumber = id.split('-').last;

  return Layer(
    id: LayerId(id),
    name: name,
    kind: kind,
    opacity: opacity,
    frames: [
      Frame(id: FrameId('frame-$layerNumber'), duration: 1, strokes: const []),
    ],
  );
}
