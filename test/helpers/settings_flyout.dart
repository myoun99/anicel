// Reaching the SETTINGS popover's rows — including the two DRAWERS.
//
// 🗣️F-146 (유저 2026-09-16 / 2026-09-18) folded most of that popover into a
// second level: the workspace behind `menu-window-panels` (「도구 버튼부터
// 작업공간 배치 초기화까지 싹 다 패널설정 버튼안으로」) and the measurement
// switches behind `menu-edit-debug` (「입력 인스펙터같은건 디버그라는? 거기다
// 넣기」).
//
// ⛔ONE way in, because five test files had grown five: the moment those rows
// moved, each of them broke in its own dialect and would have been fixed in
// its own dialect. The submenu opens on HOVER, which is a mouse and a pair of
// moves, and that is not something a case about panel layout should have to
// know.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ONE mouse per test. A second `addPointer` for the same device trips
/// `MouseTracker`'s add/remove assertion, and `createGesture` hands every
/// mouse device 0 however the pointer id is spelled.
TestGesture? _hoverMouse;

/// Moves the pointer onto [itemKey] so its second level opens.
///
/// ⚠️Away FIRST: a popover that closed and reopened leaves the pointer
/// sitting where it already was, and a move to the same place is no event at
/// all — the submenu would never open a second time in one test.
Future<void> hoverFlyoutRow(WidgetTester tester, String itemKey) async {
  final item = find.byKey(ValueKey<String>(itemKey));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  if (_hoverMouse == null) {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    _hoverMouse = mouse;
    addTearDown(() async {
      await mouse.removePointer();
      _hoverMouse = null;
    });
  }
  await _hoverMouse!.moveTo(Offset.zero);
  await tester.pumpAndSettle();
  await _hoverMouse!.moveTo(tester.getCenter(item));
  await tester.pumpAndSettle();
}

/// Opens the settings popover.
Future<void> openSettingsFlyout(WidgetTester tester) async {
  final button = find.byKey(
    const ValueKey<String>('top-strip-settings-button'),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Opens the settings popover and its PANELS drawer — the switchboard and
/// every layout choice.
///
/// ⚠️The drawer is as tall as the panel list (≈726px at the shipped tab
/// count) and SCROLLS in a smaller window, so a row below the fold is
/// reached the way [tapPanelsDrawerRow] does: `ensureVisible` first.
Future<void> openPanelsDrawer(WidgetTester tester) async {
  await openSettingsFlyout(tester);
  await hoverFlyoutRow(tester, 'menu-window-panels');
}

/// Opens the settings popover and its DEBUG drawer.
Future<void> openDebugDrawer(WidgetTester tester) async {
  await openSettingsFlyout(tester);
  await hoverFlyoutRow(tester, 'menu-edit-debug');
}

/// Opens the PANELS drawer and taps one row in it.
Future<void> tapPanelsDrawerRow(WidgetTester tester, String itemKey) async {
  await openPanelsDrawer(tester);
  final item = find.byKey(ValueKey<String>(itemKey));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}
