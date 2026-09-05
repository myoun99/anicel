import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/export/export_cels_rows.dart';

/// The compact layer-label row three export lists share — the Cels label
/// list, the Add-from-timeline sub list and the Layers member list all
/// speak this grammar, and nothing named it (2026-09-05).
void main() {
  Layer row(
    String id, {
    LayerMark mark = LayerMark.none,
    LayerId? attachedTo,
    AttachedMode mode = AttachedMode.synced,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
    mark: mark,
    attachedToLayerId: attachedTo,
    attachedMode: mode,
    attachedPlacement: AttachedPlacement.above,
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 320, child: child)),
    ),
  );

  group('the attach tag', () {
    test('⛔a 기준 row shows NONE — it is the base, not something riding one', () {
      expect(ExportLayerRow.attachTag(row('base')), isNull);
    });

    test('a SYNCED rider says sync, a free one says free', () {
      expect(
        ExportLayerRow.attachTag(row('r', attachedTo: const LayerId('base'))),
        'sync',
      );
      expect(
        ExportLayerRow.attachTag(
          row('r', attachedTo: const LayerId('base'), mode: AttachedMode.free),
        ),
        'free',
      );
    });
  });

  group('the row', () {
    testWidgets('it shows the layer name', (tester) async {
      await pump(tester, ExportLayerRow(layer: row('A셀')));

      expect(find.text('A셀'), findsOneWidget);
    });

    testWidgets('⛔the include dot is HIDDEN when the list does not ask for '
        'one — a list with no include question must not grow a control that '
        'answers nothing', (tester) async {
      await pump(tester, ExportLayerRow(layer: row('a')));
      expect(find.byType(Checkbox), findsNothing);

      await pump(
        tester,
        ExportLayerRow(
          layer: row('a'),
          includeDot: true,
          dotKey: const ValueKey<String>('dot'),
        ),
      );
      expect(find.byKey(const ValueKey<String>('dot')), findsOneWidget);
    });

    testWidgets('🚨SELECTION is colour only — no tick, no mark', (
      tester,
    ) async {
      await pump(tester, ExportLayerRow(layer: row('a'), selected: true));

      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text('✓'), findsNothing);
    });

    testWidgets('a tap reports through, and the row claims its own press', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        ExportLayerRow(layer: row('a'), onTap: () => taps += 1),
      );

      await tester.tap(find.text('a'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('the trailing tag rides at the end when the list gives one', (
      tester,
    ) async {
      await pump(tester, ExportLayerRow(layer: row('a'), trailingTag: '기준'));

      expect(find.text('기준'), findsOneWidget);
    });

    testWidgets('a MARKED row wears its mark colour, and an unmarked one '
        'does not borrow it', (tester) async {
      await pump(
        tester,
        ExportLayerRow(
          layer: row('a', mark: const LayerMark(process: LayerProcess.key)),
        ),
      );
      final marked = tester
          .widgetList<Container>(find.byType(Container))
          .map((box) => (box.decoration as ShapeDecoration?)?.color)
          .whereType<Color>()
          .toSet();

      await pump(tester, ExportLayerRow(layer: row('a')));
      final plain = tester
          .widgetList<Container>(find.byType(Container))
          .map((box) => (box.decoration as ShapeDecoration?)?.color)
          .whereType<Color>()
          .toSet();

      expect(marked, isNot(plain));
    });

    testWidgets('⛔a DIMMED row is dim — an export list shows what it will '
        'not take rather than hiding it', (tester) async {
      await pump(tester, ExportLayerRow(layer: row('a'), dimmed: true));

      expect(find.text('a'), findsOneWidget);
    });
  });
}
