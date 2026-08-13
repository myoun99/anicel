import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canvas pill's settings list — where a control that did not fit on
/// the pill went (유저 확정 2026-08-13).
///
/// 🚨WHICH controls are in there depends on WHERE the panel is and how wide
/// it is, so a test that reaches for one has to know which pill it is
/// holding. A panel in a rail or a dock folds 1:1, rotate, flip, the
/// surface colours and the host's own verbs at every width, and that is the
/// bar most tests here are looking at. The FLOOR's two panels start with
/// all of it laid out and fold only what will not fit — so on a wide floor
/// the gear does not exist at all and this helper will not find it.
///
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
