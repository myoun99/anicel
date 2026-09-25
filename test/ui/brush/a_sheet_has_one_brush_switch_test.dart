import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🚨F-179 — ONE BRUSH SWITCH FOR EVERY SHEET, and the sheet's live stroke
/// held one way.
///
/// 유저 2026-09-25: 「잉크 허용이아니라 직관적으로 브러시 허용으로 바꾸고,
/// 버튼 법 통일하고, 기본값 off로」. Each sheet host built its own toggle —
/// two with English words pinned in code, an icon for on and another for
/// off, the timesheet's alone starting on. The shell builds it now, and the
/// shell is where a sheet's stroke is let go when its drawing goes off.
void main() {
  const switchKey = ValueKey<String>('probe-brush-toggle-button');

  Widget sheet({
    required bool allowed,
    required ValueChanged<bool> onChanged,
    Object? hostToken = 'same',
    bool drawingOn = false,
    SheetStrokeHold? hold,
  }) => SheetCanvasPanel(
    cacheInvalidationSink: BrushEditCacheInvalidationSink(),
    canvasSize: const CanvasSize(width: 600, height: 800),
    viewport: CanvasViewport(),
    bottomBarHostToken: hostToken,
    brushSwitch: (allowed: allowed, onChanged: onChanged, keyPrefix: 'probe'),
    drawingOn: drawingOn,
    strokeHold: hold,
    content: (context, viewport) => const SizedBox.expand(),
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  group('the switch', () {
    testWidgets('is one button with one word and one icon — its state is '
        'its colour alone', (tester) async {
      final seen = <({bool selected, String tooltip, IconData? icon})>[];
      for (final allowed in [false, true]) {
        await pump(tester, sheet(allowed: allowed, onChanged: (_) {}));
        final button = tester.appIconButton(find.byKey(switchKey));
        seen.add((
          selected: button.isSelected,
          tooltip: button.tooltip,
          icon: (button.icon as Icon).icon,
        ));
      }
      expect(seen.map((s) => s.selected), [false, true]);
      expect(
        seen.map((s) => s.tooltip).toSet(),
        {AppText.strings.sheetBrushAllow},
        reason: 'one word, read from the table, in both states',
      );
      expect(
        seen.map((s) => s.icon).toSet(),
        hasLength(1),
        reason: 'selection is colour alone — no icon swap',
      );
    });

    testWidgets('a press asks for the other state', (tester) async {
      final asked = <bool>[];
      await pump(tester, sheet(allowed: false, onChanged: asked.add));
      await tester.tap(find.byKey(switchKey));
      await tester.pump();
      expect(asked, [true]);
    });

    testWidgets('stands at the head of the bar, before the host\'s own '
        'commands', (tester) async {
      await pump(
        tester,
        SheetCanvasPanel(
          cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          canvasSize: const CanvasSize(width: 600, height: 800),
          viewport: CanvasViewport(),
          brushSwitch: (allowed: false, onChanged: (_) {}, keyPrefix: 'probe'),
          bottomBarLeading: [
            AppIconButton(
              keyValue: 'probe-host-command',
              tooltip: 'host',
              icon: const Icon(Icons.edit_note),
              size: AppIconButtonSize.strip,
              onPressed: () {},
            ),
          ],
          drawingOn: false,
          content: (context, viewport) => const SizedBox.expand(),
        ),
      );
      expect(
        tester.getCenter(find.byKey(switchKey)).dx,
        lessThan(
          tester
              .getCenter(
                find.byKey(const ValueKey<String>('probe-host-command')),
              )
              .dx,
        ),
      );
    });

    testWidgets('is never served stale by the bar\'s memo — the host\'s '
        'token need not name it', (tester) async {
      // The same host token on both pumps: only the switch changed.
      await pump(tester, sheet(allowed: false, onChanged: (_) {}));
      expect(tester.appIconButton(find.byKey(switchKey)).isSelected, isFalse);
      await pump(tester, sheet(allowed: true, onChanged: (_) {}));
      expect(tester.appIconButton(find.byKey(switchKey)).isSelected, isTrue);
    });
  });

  testWidgets('a sheet lays its paper on the backdrop — no pasteboard', (
    tester,
  ) async {
    await pump(tester, sheet(allowed: false, onChanged: (_) {}));
    expect(
      tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
          .hasPasteboard,
      isFalse,
    );
  });

  group('the stroke hold', () {
    testWidgets('carries a stroke to the brush input and back', (
      tester,
    ) async {
      final said = <bool>[];
      final hold = SheetStrokeHold(brushInput: said.add);
      addTearDown(hold.dispose);
      hold.value = true;
      hold.value = false;
      expect(said, [true, false]);
    });

    testWidgets('drawing going off under the pen lets it go — after the '
        'frame, so a listener OUTSIDE the sheet may rebuild', (tester) async {
      // The part the timeline's toolbar plays: it rebuilds on the brush
      // input, and it is not below the sheet.
      final outside = ValueNotifier<int>(0);
      addTearDown(outside.dispose);
      final said = <bool>[];
      final hold = SheetStrokeHold(
        brushInput: (live) {
          said.add(live);
          outside.value += 1;
        },
      );
      addTearDown(hold.dispose);
      final drawing = ValueNotifier<bool>(true);
      addTearDown(drawing.dispose);

      await pump(
        tester,
        Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: outside,
              builder: (context, count, _) => Text('$count'),
            ),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: drawing,
                builder: (context, on, _) => sheet(
                  allowed: on,
                  onChanged: (_) {},
                  drawingOn: on,
                  hold: hold,
                ),
              ),
            ),
          ],
        ),
      );

      hold.value = true; // the pen is down on the sheet's ink
      await tester.pump();
      drawing.value = false; // …and the brush goes off under it
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(hold.value, isFalse, reason: 'nothing else will lift this pen');
      expect(said, [true, false]);
    });

    testWidgets('a hold torn down mid-stroke lets the brush input go', (
      tester,
    ) async {
      final said = <bool>[];
      final hold = SheetStrokeHold(brushInput: said.add);
      hold.value = true;
      hold.dispose();
      expect(said, [true, false]);
    });
  });
}
