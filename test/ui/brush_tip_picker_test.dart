import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_entry.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tip_picker.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

BrushTipMask _mask(String id, {int value = 200}) => BrushTipMask(
  id: id,
  size: 4,
  alpha: Uint8List.fromList(List<int>.filled(16, value)),
);

BrushTipEntry _entry(String id, String name, {bool loaded = true}) =>
    BrushTipEntry(
      id: id,
      name: name,
      size: 4,
      thumbnail: Uint8List(brushTipThumbnailSide * brushTipThumbnailSide),
      mask: loaded ? _mask(id) : null,
    );

void main() {
  Future<BrushToolState Function()> pumpPanel(
    WidgetTester tester, {
    required List<BrushTipEntry> tips,
    BrushToolState? initial,
    VoidCallback? onTipImportRequested,
  }) async {
    var state = initial ?? BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => BrushSettingsPanel(
                state: state,
                tips: tips,
                onTipImportRequested: onTipImportRequested,
                onChanged: (next) => setState(() => state = next),
              ),
            ),
          ),
        ),
      ),
    );
    return () => state;
  }

  testWidgets('no tip library means no picker at all', (tester) async {
    await pumpPanel(tester, tips: const []);

    expect(
      find.byKey(const ValueKey<String>('brush-tip-picker-tip')),
      findsNothing,
    );
  });

  testWidgets('picking a tip puts it on the brush', (tester) async {
    final read = await pumpPanel(
      tester,
      tips: [_entry('builtin-chalk', 'Chalk'), _entry('tip-1', 'Mine')],
    );

    final swatch = find.byKey(const ValueKey<String>('brush-tip-picker-tip'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tip-cell-tip-1')),
    );
    await tester.pumpAndSettle();

    expect(read().tipMask, _mask('tip-1'));
  });

  testWidgets('the none cell takes the tip back off', (tester) async {
    // copyWith preserves masks so a slider drag never drops one, which is
    // exactly why removing one needs its own path.
    final read = await pumpPanel(
      tester,
      tips: [_entry('tip-1', 'Mine')],
      initial: BrushToolState.defaults.copyWith(tipMask: _mask('tip-1')),
    );
    expect(read().tipMask, isNotNull);

    final swatch = find.byKey(const ValueKey<String>('brush-tip-picker-tip'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-cell-none')));
    await tester.pumpAndSettle();

    expect(read().tipMask, isNull);
  });

  testWidgets('a tip still decoding cannot be applied', (tester) async {
    // Its thumbnail is a preview, not the mask — applying it would put a
    // 16px placeholder on the brush.
    final read = await pumpPanel(
      tester,
      tips: [_entry('tip-1', 'Pending', loaded: false)],
    );

    final swatch = find.byKey(const ValueKey<String>('brush-tip-picker-tip'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tip-cell-tip-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(read().tipMask, isNull);
  });

  testWidgets('dual and texture drive their own slots', (tester) async {
    final read = await pumpPanel(tester, tips: [_entry('tip-1', 'Mine')]);

    for (final role in [BrushTipRole.dual, BrushTipRole.texture]) {
      final swatch = find.byKey(
        ValueKey<String>('brush-tip-picker-${role.name}'),
      );
      await tester.ensureVisible(swatch);
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-tip-cell-tip-1')),
      );
      await tester.pumpAndSettle();
    }

    expect(read().dualMask, _mask('tip-1'));
    expect(read().textureMask, _mask('tip-1'));
    // The tip slot is untouched: three slots, one picker, no crosstalk.
    expect(read().tipMask, isNull);
  });

  testWidgets('the texture sliders appear only once a texture is set', (
    tester,
  ) async {
    await pumpPanel(tester, tips: [_entry('tip-1', 'Mine')]);
    expect(
      find.byKey(const ValueKey<String>('brush-tool-texture-density-slider')),
      findsNothing,
    );

    final swatch = find.byKey(
      const ValueKey<String>('brush-tip-picker-texture'),
    );
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tip-cell-tip-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-tool-texture-density-slider')),
      findsOneWidget,
    );
  });

  testWidgets('the add button asks the host to open an image', (tester) async {
    var requests = 0;
    await pumpPanel(
      tester,
      tips: [_entry('tip-1', 'Mine')],
      onTipImportRequested: () => requests += 1,
    );

    final swatch = find.byKey(const ValueKey<String>('brush-tip-picker-tip'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-tip-picker-add')),
    );
    await tester.pumpAndSettle();

    expect(requests, 1);
  });
}
