import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canvas pill's settings list (유저 확정 2026-08-13).
///
/// The pill shows the zoom readout, Fit and the host's own few controls;
/// 1:1, rotate, flip and the three surface colours moved behind the gear,
/// because "공통적으로 쓰는 것만 노출하고 나머지는 설정". Every flow that
/// pressed one of those gains ONE tap here and nothing else — which is the
/// same shape the media browser's row menu took when its buttons moved.
/// Pass [of] whenever more than one canvas panel is mounted — the default
/// workspace docks the timesheet open, and the sheet is a real
/// [BrushCanvasPanel] with a gear of its own (see `panel_finders.dart`).
Future<void> openViewSettings(WidgetTester tester, {Finder? of}) async {
  const key = ValueKey<String>('canvas-viewport-settings');
  final gear = of == null
      ? find.byKey(key)
      : find.descendant(of: of, matching: find.byKey(key));
  await tester.ensureVisible(gear);
  await tester.pumpAndSettle();
  await tester.tap(gear);
  await tester.pumpAndSettle();
}

/// Opens the settings list and presses one of its controls.
///
/// ⚠️A knob (rotate, flip, a swatch) leaves the list OPEN — it is a
/// [PanelFlyoutRow] and rows take no tap of their own. A command (1:1)
/// closes it. So a test pressing two knobs in a row should
/// [openViewSettings] once and tap directly rather than call this twice.
Future<void> tapInViewSettings(
  WidgetTester tester,
  String keyValue, {
  Finder? of,
}) async {
  await openViewSettings(tester, of: of);
  final control = find.byKey(ValueKey<String>(keyValue));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}
