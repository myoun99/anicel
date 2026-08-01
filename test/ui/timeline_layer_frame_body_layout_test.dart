import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_frame_body_layout.dart';

void main() {
  group('TimelineLayerFrameBodyLayout', () {
    testWidgets('provided layer controls rail child renders', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_layerControlsRailKey), findsOneWidget);
    });

    testWidgets('provided layer-axis scrollbar slot child renders', (
      tester,
    ) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_layerAxisScrollbarSlotKey), findsOneWidget);
    });

    testWidgets('provided frame grid area child renders', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_frameGridAreaKey), findsOneWidget);
    });

    testWidgets('preserves direct Row child order', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      final row = tester.widget<Row>(find.byType(Row));

      // The rail-window order: the layer-axis bar took the grid's left
      // EDGE, and the gap it used to hold between the rail and the cells
      // is the splitter's now.
      expect(row.children.length, 4);
      expect(row.children[0].key, _layerAxisScrollbarSlotKey);
      expect(row.children[1].key, _layerControlsRailKey);
      expect(row.children[2].key, _railSplitterSlotKey);

      final frameGridArea = row.children[3];
      expect(frameGridArea, isA<Expanded>());
      expect((frameGridArea as Expanded).child.key, _frameGridAreaKey);
    });

    testWidgets('preserves Row cross axis alignment', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      final row = tester.widget<Row>(find.byType(Row));

      expect(row.crossAxisAlignment, CrossAxisAlignment.start);
    });

    testWidgets('does not introduce or duplicate production stable keys', (
      tester,
    ) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_layerControlsRailKey), findsOneWidget);
      expect(find.byKey(_layerAxisScrollbarSlotKey), findsOneWidget);
      expect(find.byKey(_railSplitterSlotKey), findsOneWidget);
      expect(find.byKey(_frameGridAreaKey), findsOneWidget);

      for (final key in _productionStableKeys) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
    });
  });
}

const _layerControlsRailKey = ValueKey<String>('test-layer-controls-rail');
const _layerAxisScrollbarSlotKey = ValueKey<String>(
  'test-layer-axis-scrollbar-slot',
);
const _railSplitterSlotKey = ValueKey<String>('test-rail-splitter-slot');
const _frameGridAreaKey = ValueKey<String>('test-frame-grid-area');

const _productionStableKeys = <String>[
  'timeline-layer-controls-rail',
  'timeline-frame-grid-area',
  'timeline-rail-splitter',
];

Widget _layoutHarness() {
  return const MaterialApp(
    home: Material(
      child: SizedBox(
        width: 600,
        height: 120,
        child: TimelineLayerFrameBodyLayout(
          layerAxisScrollbarSlot: SizedBox(
            key: _layerAxisScrollbarSlotKey,
            width: 16,
            height: 120,
          ),
          layerControlsRail: SizedBox(
            key: _layerControlsRailKey,
            width: 120,
            height: 120,
          ),
          railSplitterSlot: SizedBox(key: _railSplitterSlotKey, width: 5),
          frameGridArea: Expanded(
            child: SizedBox(key: _frameGridAreaKey, height: 120),
          ),
        ),
      ),
    ),
  );
}
