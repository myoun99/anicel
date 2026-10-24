// A rail row's blend chip is the panels' chip pressed as the rail presses
// (I-57 ①): the rail's plate face around [PanelFlyoutChip], not a tooltip,
// a Material and an InkWell of its own (~43 elements a chip, mounted anew
// whenever a frame panel is shown again — frame-panels-build-in-one-frame,
// 10-24). The chip is clear, so the one ink the app keeps — the hover —
// showed on it; the face paints that hover, and the chip looks as it did.
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/named_finders.dart';

const _chipSize = Size(64, 22);

/// [child] in a box of its own, in the app's theme, captured by key.
Widget _boxed(String key, Widget child) => RepaintBoundary(
  key: ValueKey<String>(key),
  child: SizedBox.fromSize(
    size: _chipSize,
    child: ColoredBox(color: AppColors.surface, child: child),
  ),
);

List<PanelFlyoutEntry> _entries() => [
  const PanelFlyoutItem(keyValue: 'blend-probe-entry', label: 'Multiply'),
];

Future<Uint8List> _pixelsOf(WidgetTester tester, String key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey<String>(key)),
  );
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  return pixels;
}

void main() {
  testWidgets('the rail chip and the InkWell chip paint the same pixels, at '
      'rest and under the mouse', (tester) async {
    const label = 'Normal';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Column(
            children: [
              _boxed(
                'inkwell',
                const PanelFlyoutButton(
                  label: label,
                  expand: true,
                  entriesBuilder: _entries,
                ),
              ),
              _boxed(
                'rail',
                RailFlyoutTrigger(
                  name: 'rail-chip',
                  tooltip: 'Blend',
                  hoverShape: PanelFlyoutChip.shape,
                  entriesBuilder: _entries,
                  child: const PanelFlyoutChip(label: label, expand: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      await _pixelsOf(tester, 'rail'),
      await _pixelsOf(tester, 'inkwell'),
      reason: 'at rest',
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(-50, -50));
    Future<Uint8List> hovered(String key) async {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey<String>(key))));
      // Past the InkWell's hover fade: its first frame starts the fade at
      // nothing, the next one finishes it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final pixels = await _pixelsOf(tester, key);
      await mouse.moveTo(const Offset(-50, -50));
      await tester.pump(const Duration(seconds: 2));
      return pixels;
    }

    final inkwellHovered = await hovered('inkwell');
    final railHovered = await hovered('rail');
    expect(
      inkwellHovered,
      isNot(await _pixelsOf(tester, 'inkwell')),
      reason: 'the hover shows on a clear chip — or this compares nothing',
    );
    expect(railHovered, inkwellHovered, reason: 'under the mouse');
  });

  testWidgets('the row\'s blend chip is the rail plate around the panels\' '
      'chip — no InkWell, no Material, no Tooltip of its own', (tester) async {
    LayerBlendMode? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 64,
              child: LayerBlendModeChip(
                name: 'blend-probe',
                optionKeyPrefix: 'blend-probe-option-',
                blendMode: LayerBlendMode.normal,
                onBlendModeSelected: (mode) => picked = mode,
              ),
            ),
          ),
        ),
      ),
    );

    final chip = find.named('blend-probe');
    expect(tester.widget(chip), isA<RailPlateButton>());
    expect(
      tester.widget<RailPlateButton>(chip).hoverShape,
      PanelFlyoutChip.shape,
      reason: 'a clear chip shows its hover',
    );
    final host = find.byType(LayerBlendModeChip);
    for (final heavy in [
      find.byType(InkWell),
      find.byType(Material),
      find.byType(AppTooltip),
    ]) {
      expect(find.descendant(of: host, matching: heavy), findsNothing);
    }

    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('blend-probe-option-multiply')),
    );
    await tester.pumpAndSettle();
    expect(picked, LayerBlendMode.multiply);
  });
}
