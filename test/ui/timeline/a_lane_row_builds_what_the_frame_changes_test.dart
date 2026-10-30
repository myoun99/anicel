import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// T26 (2026-10-30, measured on the device with every lane open: play p95
/// 22–29ms): a lane row shows its lane AT the cursor, and only what shows
/// the frame is built again as the cursor moves — the value, the key
/// buttons, a group's preview — and only when what it shows changes.
///
/// Pinned by widget identity: a widget instance only changes when the
/// widget above it is built again.
void main() {
  final layer = Layer(id: const LayerId('a'), name: 'A', frames: const []);

  Future<ValueNotifier<int?>> pumpRow(
    WidgetTester tester,
    PropertyLaneRow lane, {
    required int at,
  }) async {
    final cursor = ValueNotifier<int?>(at);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane,
              metrics: TimelineGridMetrics.defaults,
              width: TimelineGridMetrics.defaults.layerControlsWidth,
              height: TimelineGridMetrics.defaults.layerRowHeight,
              frameCursor: cursor,
              onSelectFrame: (_) {},
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    return cursor;
  }

  Future<void> moveTo(
    WidgetTester tester,
    ValueNotifier<int?> cursor,
    int frame,
  ) async {
    cursor.value = frame;
    await tester.pump();
  }

  group('a member lane', () {
    // Keys at 2 and 6; the value reads 10 before frame 4 and 20 from it.
    final lane = PropertyLaneRow(
      laneId: 'spin',
      label: 'Spin',
      keyMarks: const {2: KeyMark.linear, 6: KeyMark.linear},
      valueLabel: (frame) => frame < 4 ? '10.00%' : '20.00%',
    );
    final name = find.text('Spin');
    final value = find.byKey(const ValueKey('timeline-lane-value-a-spin'));
    final keyButton = find.byKey(
      const ValueKey('timeline-lane-key-toggle-a-spin'),
    );

    ({Widget name, Widget value, Widget keyButton}) built(
      WidgetTester tester,
    ) => (
      name: tester.widget(name),
      value: tester.widget(value),
      keyButton: tester.widget(keyButton),
    );

    testWidgets('a cursor move that changes nothing it shows builds '
        'nothing', (tester) async {
      final cursor = await pumpRow(tester, lane, at: 0);
      final before = built(tester);

      await moveTo(tester, cursor, 1);

      final after = built(tester);
      expect(identical(after.name, before.name), isTrue);
      expect(identical(after.value, before.value), isTrue);
      expect(identical(after.keyButton, before.keyButton), isTrue);
    });

    testWidgets('a move that changes the value builds the value alone — '
        'and it reads the new frame', (tester) async {
      final cursor = await pumpRow(tester, lane, at: 3);
      final before = built(tester);
      expect(find.descendant(of: value, matching: find.text('10.00%')),
          findsOneWidget);

      await moveTo(tester, cursor, 4);

      final after = built(tester);
      expect(identical(after.value, before.value), isFalse);
      expect(find.descendant(of: value, matching: find.text('20.00%')),
          findsOneWidget);
      expect(identical(after.name, before.name), isTrue);
      expect(identical(after.keyButton, before.keyButton), isTrue);
    });

    testWidgets('crossing a key builds the key buttons alone — and they '
        'read the new frame', (tester) async {
      final cursor = await pumpRow(tester, lane, at: 1);
      final before = built(tester);
      final previous = find.byKey(
        const ValueKey('timeline-lane-prev-key-a-spin'),
      );
      bool enabled(Finder button) =>
          tester.widget<InkWell>(button).onTap != null;
      expect(enabled(previous), isFalse, reason: 'no key before frame 1');

      await moveTo(tester, cursor, 3);

      final after = built(tester);
      expect(identical(after.keyButton, before.keyButton), isFalse);
      expect(enabled(previous), isTrue, reason: 'the key at 2 is behind');
      expect(identical(after.name, before.name), isTrue);
      expect(identical(after.value, before.value), isTrue);
    });
  });

  group('a group header', () {
    // The tag reads plain before frame 3 and bold from it.
    final lane = PropertyLaneRow(
      laneId: 'tag',
      label: 'Tag',
      keyMarks: const {},
      isGroupHeader: true,
      previewText: (
        name: '名前',
        line: 'セリフ',
        tagAt: (frame) => SeNameTag(style: TextCelStyle(bold: frame >= 3)),
      ),
    );
    final preview = find.byKey(
      const ValueKey('timeline-lane-group-preview-a-tag'),
    );
    FontWeight? weight(WidgetTester tester) => tester
        .widget<Text>(find.descendant(of: preview, matching: find.text('名前')))
        .style!
        .fontWeight;

    testWidgets('its preview is built again only when the look at the '
        'cursor changes — and it shows the new look', (tester) async {
      final cursor = await pumpRow(tester, lane, at: 0);
      final name = find.text('Tag');
      final nameBefore = tester.widget(name);
      final previewBefore = tester.widget(preview);
      expect(weight(tester), FontWeight.w400);

      await moveTo(tester, cursor, 1);
      expect(identical(tester.widget(preview), previewBefore), isTrue);

      await moveTo(tester, cursor, 3);
      expect(identical(tester.widget(preview), previewBefore), isFalse);
      expect(weight(tester), FontWeight.w700);
      expect(identical(tester.widget(name), nameBefore), isTrue);
    });
  });
}
