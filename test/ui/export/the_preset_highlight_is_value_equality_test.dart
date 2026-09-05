import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/export/export_preset_rail.dart';

/// The export window's preset drawer — nothing named it (2026-09-05).
///
/// 🚨The selection highlight is VALUE EQUALITY against the live spec, not
/// a remembered id: editing any knob visibly "leaves" the preset and
/// applying one snaps back. A remembered id would keep a preset looking
/// selected while the spec under it had moved on.
///
/// ⛔Colour only, no marks — the app's selection convention.
void main() {
  ExportPreset preset(String id, ExportTabSpec spec) =>
      ExportPreset(id: ExportPresetId(id), name: 'preset $id', spec: spec);

  const plain = ImageExportSpec();
  final edited = const ImageExportSpec().copyWith(applyLayerFx: false);

  Future<
    ({List<ExportPreset> applied, List<ExportPreset> deleted, List<int> saves})
  >
  pump(
    WidgetTester tester, {
    required ExportTabSpec current,
    bool enabled = true,
  }) async {
    final applied = <ExportPreset>[];
    final deleted = <ExportPreset>[];
    final saves = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: ExportPresetRail(
              tab: ExportTab.image,
              presets: [preset('a', plain), preset('b', edited)],
              currentSpec: current,
              enabled: enabled,
              onApply: applied.add,
              onSaveCurrent: () => saves.add(1),
              onDelete: deleted.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (applied: applied, deleted: deleted, saves: saves);
  }

  Color? tileColourOf(WidgetTester tester, String name) {
    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text(name), matching: find.byType(Container))
          .first,
    );
    final decoration = container.decoration;
    return decoration is ShapeDecoration ? decoration.color : null;
  }

  testWidgets('every preset for the tab gets a row', (tester) async {
    await pump(tester, current: plain);

    expect(find.text('preset a'), findsOneWidget);
    expect(find.text('preset b'), findsOneWidget);
  });

  testWidgets('🚨the highlight follows VALUE equality — the preset whose '
      'spec IS the live one reads selected', (tester) async {
    await pump(tester, current: plain);

    expect(tileColourOf(tester, 'preset a'), isNotNull);
    expect(tileColourOf(tester, 'preset b'), isNull);
  });

  testWidgets('🚨editing a knob visibly LEAVES the preset — nothing is '
      'selected once the spec has moved on', (tester) async {
    await pump(
      tester,
      current: const ImageExportSpec().copyWith(
        sizeMode: ExportSizeMode.canvas,
      ),
    );

    expect(tileColourOf(tester, 'preset a'), isNull);
    expect(tileColourOf(tester, 'preset b'), isNull);
  });

  testWidgets('and applying one snaps back — the OTHER preset lights up '
      'when the spec becomes its own', (tester) async {
    await pump(tester, current: edited);

    expect(tileColourOf(tester, 'preset a'), isNull);
    expect(tileColourOf(tester, 'preset b'), isNotNull);
  });

  testWidgets('⛔selection is COLOUR only — no tick, no mark', (tester) async {
    await pump(tester, current: plain);

    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('pressing a preset applies THAT one', (tester) async {
    final rail = await pump(tester, current: plain);

    await tester.tap(find.text('preset b'));
    await tester.pumpAndSettle();

    expect(rail.applied.single.name, 'preset b');
  });

  testWidgets('the save row reports the current spec', (tester) async {
    final rail = await pump(tester, current: plain);

    // ⚠️A plain tap does not reach a ControlPressClaim's own action: the
    // InkWell's onTap is silenced by design, and the claim fires on the
    // press it took at pointer-DOWN. So the press has to be driven.
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('export-preset-save-current')),
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rail.saves, hasLength(1));
  });

  testWidgets('⛔a DISABLED rail takes no press — a running export must not '
      'be re-specified under itself', (tester) async {
    final rail = await pump(tester, current: plain, enabled: false);

    await tester.tap(find.text('preset b'), warnIfMissed: false);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preset-save-current')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(rail.applied, isEmpty);
    expect(rail.saves, isEmpty);
  });

  test('the tab label names each tab', () {
    for (final tab in ExportTab.values) {
      expect(ExportPresetRail.tabLabel(tab), isNotEmpty, reason: '$tab');
    }
    expect(
      {for (final tab in ExportTab.values) ExportPresetRail.tabLabel(tab)},
      hasLength(ExportTab.values.length),
      reason: 'two tabs sharing a label would be a drawer nobody can read',
    );
  });
}
