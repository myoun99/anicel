import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import 'timeline/timeline_cell_probe.dart';

void main() {
  group('TimelineFrameRowsScrollBody', () {
    testWidgets('exposes the stable body key exactly once', (tester) async {
      await tester.pumpWidget(_body(layers: [_layer('layer-a')]));

      expect(_bodyFinder, findsOneWidget);
      expect(
        _stableKeyFinder('timeline-frame-rows-scroll-body'),
        findsOneWidget,
      );
    });

    testWidgets('renders one frame row per provided layer', (tester) async {
      final layers = [_layer('layer-a'), _layer('layer-b'), _layer('layer-c')];

      await tester.pumpWidget(_body(layers: layers));

      expect(find.byType(TimelineFrameCellsRow), findsNWidgets(layers.length));
      for (final layer in layers) {
        expect(
          find.byKey(ValueKey<String>('timeline-frame-row-area-${layer.id}')),
          findsOneWidget,
        );
      }
    });

    testWidgets('preserves provided layer order', (tester) async {
      final layers = [_layer('layer-a'), _layer('layer-b'), _layer('layer-c')];

      await tester.pumpWidget(_body(layers: layers));

      final firstTop = tester.getTopLeft(_rowFinder(layers[0])).dy;
      final secondTop = tester.getTopLeft(_rowFinder(layers[1])).dy;
      final thirdTop = tester.getTopLeft(_rowFinder(layers[2])).dy;

      expect(firstTop, lessThan(secondTop));
      expect(secondTop, lessThan(thirdTop));
    });

    testWidgets('renders frame cells for the visible frame range', (
      tester,
    ) async {
      const layerId = LayerId('layer-a');

      await tester.pumpWidget(
        _body(
          layers: [_layer(layerId.value)],
          frameStartIndex: 0,
          frameEndIndexExclusive: 3,
        ),
      );

      expect(timelineCellInWindow(tester, layerId.value, 0), isTrue);
      expect(timelineCellInWindow(tester, layerId.value, 2), isTrue);
      expect(timelineCellInWindow(tester, layerId.value, 3), isFalse);
    });

    testWidgets('renders empty layer placeholder without rows or cells', (
      tester,
    ) async {
      const metrics = TimelineGridMetrics(layerRowHeight: 64);
      const totalFrameContentWidth = 320.0;

      await tester.pumpWidget(
        _body(
          layers: const [],
          metrics: metrics,
          totalFrameContentWidth: totalFrameContentWidth,
        ),
      );

      expect(_bodyFinder, findsOneWidget);
      expect(_keyStartingWith('timeline-frame-row-area-'), findsNothing);
      expect(_keyStartingWith('timeline-cell-'), findsNothing);
      expect(
        find.descendant(
          of: _bodyFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox &&
                widget.width == totalFrameContentWidth &&
                widget.height == metrics.layerRowHeight,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rows are cursor-independent: no selection visuals render '
        'here (they live on the grid cursor layer)', (tester) async {
      const activeLayerId = LayerId('layer-active');

      await tester.pumpWidget(
        _body(
          layers: [_layer(activeLayerId.value), _layer('layer-inactive')],
          activeLayerId: activeLayerId,
          currentFrameIndex: 1,
          exposureStateForLayer: (layer, frameIndex) => frameIndex == 1
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.uncovered,
        ),
      );

      expect(timelineCellInWindow(tester, 'layer-active', 1), isTrue);
      // The playback-performance architecture: the selection ring and the
      // exposure outline are the grid cursor layer's job, never the rows'.
      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-selected-exposure-range-outline-layer-active',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-selected-cell')),
        findsNothing,
      );
    });

    testWidgets('forwards layer and frame selection callbacks from cells', (
      tester,
    ) async {
      final layer = _layer('layer-a');
      LayerId? selectedLayerId;
      int? selectedFrameIndex;

      await tester.pumpWidget(
        _body(
          layers: [layer],
          onSelectLayer: (layerId) => selectedLayerId = layerId,
          onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
        ),
      );

      await tapTimelineCell(tester, layer.id.value, 1);

      expect(selectedLayerId, layer.id);
      expect(selectedFrameIndex, 1);
    });

    testWidgets('forwards exposure, mark, and frame name providers to cells', (
      tester,
    ) async {
      final layer = _layer('layer-a');

      await tester.pumpWidget(
        _body(
          layers: [layer],
          frameStartIndex: 0,
          frameEndIndexExclusive: 3,
          exposureStateForLayer: (_, frameIndex) => frameIndex == 2
              ? TimelineCellExposureState.markUncovered
              : TimelineCellExposureState.drawingStart,
          frameNameForLayer: (_, frameIndex) =>
              frameIndex == 1 ? 'Pose A' : null,
        ),
      );

      expect(timelineCellModel(tester, 'layer-a', 0).glyph, '○');
      expect(timelineCellModel(tester, 'layer-a', 1).glyph, 'Pose A');
      expect(timelineCellModel(tester, 'layer-a', 2).glyph, '●');
    });
  });

  group('R9 #1 — the folder band selects', () {
    testWidgets('a folder row mounts the range gesture, so a drag across '
        'its band is a selection like every other row', (tester) async {
      final folder = createFolderLayer(
        id: const LayerId('f1'),
        name: 'Folder',
      );
      final member = _layer('a').copyWith(folderId: folder.id);
      final selects = <(TimelineRowAddress, int, int)>[];

      await tester.pumpWidget(
        _body(
          layers: [folder, member],
          rangeGesture: TimelineRangeGestureCallbacks(
            isInSelection: (_, _) => false,
            onSelectUpdate: (row, anchor, head, _) =>
                selects.add((row, anchor, head)),
            onTapClear: (_) {},
            onMoveBegin: (_, _) => false,
            onMoveUpdate: (_, _) {},
            onMoveEnd: () {},
            onMoveCancel: () {},
          ),
        ),
      );

      // The band used to be pure display — 'taps fall through to nothing' —
      // which made it the one row in the timeline a range drag could not
      // cross. It keeps its comma-less, edge-less band; it gains selection.
      final gesture = _stableKeyFinder(
        'timeline-range-gesture-slot-folder-${folder.id}',
      );
      expect(gesture, findsOneWidget);

      final box = tester.getRect(gesture);
      final pointer = await tester.startGesture(
        box.centerLeft + const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await pointer.moveBy(const Offset(60, 0));
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();

      expect(selects, isNotEmpty);
      expect(
        selects.last.$1,
        LayerRowAddress(folder.id),
        reason: 'the selection addresses the FOLDER row itself — not a '
            'member, and not everything under it',
      );
    });
  });
}

Finder get _bodyFinder =>
    find.byKey(const ValueKey<String>('timeline-frame-rows-scroll-body'));

Finder _stableKeyFinder(String key) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> && widget.key == ValueKey<String>(key),
);

Finder _keyStartingWith(String prefix) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(prefix);
});

Finder _rowFinder(Layer layer) =>
    find.byKey(ValueKey<String>('timeline-frame-row-area-${layer.id}'));

Widget _body({
  required List<Layer> layers,
  LayerId? activeLayerId,
  int currentFrameIndex = 0,
  int playbackFrameCount = 24,
  int frameStartIndex = 0,
  int frameEndIndexExclusive = 3,
  double leadingFrameSpacerWidth = 0,
  double trailingFrameSpacerWidth = 0,
  double totalFrameContentWidth = 144,
  TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
  TimelineCellExposureState Function(Layer layer, int frameIndex)?
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  ValueChanged<LayerId>? onSelectLayer,
  ValueChanged<int>? onSelectFrame,
  TimelineRangeGestureCallbacks? rangeGesture,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Material(
        child: TimelineFrameRowsScrollBody(
          rows: buildTimelineDisplayRows(
            layers: layers,
            expandedLayerIds: const {},
            lanesForLayer: (_) => const [],
          ),
          activeLayerId: activeLayerId,
          playbackFrameCount: playbackFrameCount,
          frameStartIndex: frameStartIndex,
          frameEndIndexExclusive: frameEndIndexExclusive,
          leadingFrameSpacerWidth: leadingFrameSpacerWidth,
          trailingFrameSpacerWidth: trailingFrameSpacerWidth,
          totalFrameContentWidth: totalFrameContentWidth,
          metrics: metrics,
          exposureStateForLayer:
              exposureStateForLayer ??
              ((_, _) => TimelineCellExposureState.uncovered),
          frameNameForLayer: frameNameForLayer,
          onSelectLayer: onSelectLayer ?? (_) {},
          onSelectFrame: onSelectFrame ?? (_) {},
          rangeGesture: rangeGesture,
        ),
      ),
    ),
  );
}

Layer _layer(String id) {
  return Layer(id: LayerId(id), name: 'Layer $id', frames: const []);
}
