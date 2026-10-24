import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindIcon;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';

/// A row's TYPE CELL (UI-R24 #7) in its two forms since I-57 ①: where a
/// press answers (the timeline's rows, the storyboard's), it is the rail's
/// button — one leaf, the kind for a screen reader, no tooltip of its own;
/// where nothing does (the export window's list), it is the kind's glyph
/// alone, in full ink, not a dead button worn dim.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  final cell = find.named('timeline-layer-type-button-l1');

  testWidgets('where a press answers, the cell is the rail\'s button: one '
      'press, the kind\'s glyph, the kind\'s name', (tester) async {
    var pressed = 0;
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      LayerTypeButton(
        keyPrefix: 'timeline',
        idValue: 'l1',
        kind: LayerKind.animation,
        onTap: () => pressed += 1,
      ),
    );
    expect(tester.widget(cell), isA<RailGlyphButton>());
    expect(
      tester.appIconButton(cell).icon,
      layerKindIcon(LayerKind.animation),
    );
    expect(
      tester.getSemantics(cell),
      isSemantics(
        label: layerTypeSemanticLabel(LayerKind.animation),
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(cell);
    await tester.pump(const Duration(seconds: 2));
    expect(pressed, 1);
    handle.dispose();
  });

  testWidgets('the cell keeps the slot\'s box', (tester) async {
    await pump(
      tester,
      LayerTypeButton(
        keyPrefix: 'timeline',
        idValue: 'l1',
        kind: LayerKind.animation,
        height: 20,
        onTap: () {},
      ),
    );
    expect(tester.getSize(cell), const Size(layerTypeSlotWidth, 20));
  });

  testWidgets('a folder\'s glyph reads its own fold and stands back', (
    tester,
  ) async {
    for (final collapsed in [false, true]) {
      await pump(
        tester,
        LayerTypeButton(
          keyPrefix: 'timeline',
          idValue: 'l1',
          kind: LayerKind.folder,
          folderCollapsed: collapsed,
          onTap: () {},
        ),
      );
      final reading = tester.appIconButton(cell);
      expect(reading.icon, collapsed ? Icons.folder : Icons.folder_open);
      expect(
        reading.iconColor,
        Theme.of(tester.element(cell)).colorScheme.onSurfaceVariant,
      );
    }
  });

  testWidgets('where nothing answers, it is the kind\'s glyph alone — in '
      'the full ink a dead button would not wear', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LayerTypeButton(
        keyPrefix: 'timeline',
        idValue: 'l1',
        kind: LayerKind.animation,
      ),
    );
    expect(find.byType(RailGlyphButton), findsNothing);
    final glyph = find.descendant(of: cell, matching: find.byType(Icon));
    expect(
      tester.widget<Icon>(glyph).icon,
      layerKindIcon(LayerKind.animation),
    );
    expect(
      IconTheme.of(tester.element(glyph)).color,
      AppColors.text,
      reason: 'the ambient ink, as the cell always wore it',
    );
    expect(
      tester.getSemantics(
        find.descendant(of: cell, matching: find.byType(Semantics)).first,
      ),
      isSemantics(
        label: layerTypeSemanticLabel(LayerKind.animation),
        isButton: false,
        hasTapAction: false,
      ),
    );
    expect(tester.getSize(cell), const Size(layerTypeSlotWidth, 24));
    handle.dispose();
  });
}
