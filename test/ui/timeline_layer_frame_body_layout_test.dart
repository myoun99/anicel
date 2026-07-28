import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_frame_body_layout.dart';

void main() {
  group('TimelineLayerFrameBodyLayout', () {
    testWidgets('provided layer controls rail child renders', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_layerControlsRailKey), findsOneWidget);
    });

    testWidgets('provided vertical scrollbar slot child renders', (
      tester,
    ) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_verticalScrollbarSlotKey), findsOneWidget);
    });

    testWidgets('provided frame grid area child renders', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      expect(find.byKey(_frameGridAreaKey), findsOneWidget);
    });

    testWidgets('preserves direct Row child order', (tester) async {
      await tester.pumpWidget(_layoutHarness());

      final row = tester.widget<Row>(find.byType(Row));

      expect(row.children.length, 3);
      expect(row.children[0].key, _layerControlsRailKey);
      expect(row.children[1].key, _verticalScrollbarSlotKey);

      final frameGridArea = row.children[2];
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
      expect(find.byKey(_verticalScrollbarSlotKey), findsOneWidget);
      expect(find.byKey(_frameGridAreaKey), findsOneWidget);

      for (final key in _productionStableKeys) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
    });
  });
}

const _layerControlsRailKey = ValueKey<String>('test-layer-controls-rail');
const _verticalScrollbarSlotKey = ValueKey<String>(
  'test-vertical-scrollbar-slot',
);
const _frameGridAreaKey = ValueKey<String>('test-frame-grid-area');

const _productionStableKeys = <String>[
  'timeline-layer-controls-rail',
  'timeline-frame-grid-area',
  'timeline-vertical-scrollbar-slot',
];

Widget _layoutHarness() {
  return const MaterialApp(
    home: Material(
      child: SizedBox(
        width: 600,
        height: 120,
        child: TimelineLayerFrameBodyLayout(
          layerControlsRail: SizedBox(
            key: _layerControlsRailKey,
            width: 120,
            height: 120,
          ),
          verticalScrollbarSlot: SizedBox(
            key: _verticalScrollbarSlotKey,
            width: 14,
            height: 120,
          ),
          frameGridArea: Expanded(
            child: SizedBox(key: _frameGridAreaKey, height: 120),
          ),
        ),
      ),
    ),
  );
}
