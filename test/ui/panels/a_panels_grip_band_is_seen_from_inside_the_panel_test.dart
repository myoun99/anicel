// 🗣️F-257 (유저 2026-10-02): 「바닥 도킹 패널만 탭 띠가 표시안됨. 규칙/법
// 통일」 — and where (2026-10-08): 「밑 도킹영역인 지금으로치면 타임라인패널이나
// 콘티패널이 있는곳. 그 곳의 패널 버튼만 버튼에 호버해야 드래그가능한 회색
// 띠가 뜸. 다른 사이드띠 패널들은 패널 안에 들어가기만하면 띠가 뜨는데」.
//
// THE LAW (유저, R3 #9: 패널에 호버하면 기본색): with the pointer anywhere in a
// panel, the tab that lifts it wears its grip band — and the band is SEEN.
//
// 🔬Why this reads PIXELS. The band of the region under the canvas took its
// ink like every dock's the moment the pointer entered the panel; the state
// was right and the screen was not. A resting band is two pixels on the
// strip's outer edge, and in that region the edge is the region's own
// outline — its ring, painted over what the region holds, covered one of the
// two and dimmed the other. A pin on the band's colour would have stayed
// green through all of it.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';

const _window = Size(1600, 1000);
const _shot = ValueKey<String>('the-whole-window');

/// A point over the canvas and under no button, while the region is under
/// the canvas: nothing is near it, and no tooltip comes up over a band from
/// it.
const _away = Offset(800, 300);

/// The same, with that region at the top of the window.
const _awayBelow = Offset(800, 800);

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_window);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The window as it is painted now.
Future<ByteData> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shot),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  image.dispose();
  return data;
}

Color _at(ByteData data, int x, int y) {
  final i = (y * _window.width.toInt() + x) * 4;
  return Color.fromARGB(
    255,
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

/// How far [seen] is from [ink], channel by channel — the largest of the
/// three, of 255.
int _distance(Color seen, Color ink) {
  int channel(double a, double b) => ((a - b) * 255).round().abs();
  return [
    channel(seen.r, ink.r),
    channel(seen.g, ink.g),
    channel(seen.b, ink.b),
  ].reduce((a, b) => a > b ? a : b);
}

Finder _gripOf(String tabId) =>
    find.byKey(ValueKey<String>('panel-grip-$tabId'));

Finder _bandOf(String tabId) =>
    find.descendant(of: _gripOf(tabId), matching: find.byType(ColoredBox));

/// The panel [tabId]'s tab lifts: its dock's whole box.
Rect _panelOf(WidgetTester tester, String tabId) => tester.getRect(
  find
      .ancestor(of: _gripOf(tabId), matching: find.byType(EditorPanelTabs))
      .first,
);

/// Every row of [tabId]'s band, as painted down the middle of it.
Future<List<Color>> _bandRows(WidgetTester tester, String tabId) async {
  final rect = tester.getRect(_bandOf(tabId));
  final data = await _pixels(tester);
  final x = rect.center.dx.round();
  return [
    for (var y = rect.top.round(); y < rect.bottom.round(); y += 1)
      _at(data, x, y),
  ];
}

void main() {
  // The docks a fresh window opens with: the region under the canvas (its
  // strip on the edge against the window frame), and a column on each side.
  const docks = {
    EditorWorkspace.timelineTabId: 'the region under the canvas',
    EditorWorkspace.storyboardTabId: 'the region under the canvas, its '
        'other tab',
    EditorWorkspace.brushesTabId: 'the left column',
    EditorWorkspace.timesheetTabId: 'the right column',
  };

  /// A band row counts as seen within this of the ink. The ring's
  /// antialiasing takes about a tenth off the row beside it (measured: 5 of
  /// 255 at rest, 12 under the pointer); a row UNDER the ring is 44 away.
  const near = 16;

  Future<TestGesture> aMouse(WidgetTester tester, [Offset at = _away]) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    addTearDown(mouse.removePointer);
    await tester.pump();
    return mouse;
  }

  Future<void> expectSeenFromInside(
    WidgetTester tester,
    TestGesture mouse,
    String tabId,
    String where, {
    Offset away = _away,
  }) async {
    expect(_gripOf(tabId), findsOneWidget, reason: '⛔premise: $where');
    await mouse.moveTo(away);
    await tester.pump();
    expect(
      tester.widget<ColoredBox>(_bandOf(tabId)).color,
      Colors.transparent,
      reason: '⛔premise ($where): nothing is near, and the band is clear',
    );

    await mouse.moveTo(_panelOf(tester, tabId).center);
    await tester.pump();

    final ink = GripBand.ink(nearby: true, hovered: false, active: false);
    expect(tester.widget<ColoredBox>(_bandOf(tabId)).color, ink, reason: where);
    final rows = await _bandRows(tester, tabId);
    expect(rows, hasLength(GripBand.rest.round()), reason: where);
    expect(
      [for (final row in rows) _distance(row, ink)],
      everyElement(lessThanOrEqualTo(near)),
      reason:
          '$where: every row of the resting band is SEEN from inside the '
          'panel — painted $rows, its ink is $ink',
    );
  }

  testWidgets('🚨with the pointer in a panel, its tab\'s grip band is seen — '
      'in every dock, the region under the canvas like the columns', (
    tester,
  ) async {
    await _pumpApp(tester);
    final mouse = await aMouse(tester);
    for (final MapEntry(key: tabId, value: where) in docks.entries) {
      await expectSeenFromInside(tester, mouse, tabId, where);
    }
  });

  // 「아래 도킹 영역은 위/아래 설정 가능」 — the strip rides the edge against
  // the frame either way, and that edge is the outline either way.
  testWidgets('…and with that region moved to the top of the window', (
    tester,
  ) async {
    await _pumpApp(tester);
    final keys = EditorShortcutScope.peek(
      tester.element(find.byType(EditorWorkspace)),
    )!;
    keys.setActivators(EditorActionIds.regionOnTop, const [
      SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true),
    ]);
    expect(
      keys.conflictedActionIds,
      isEmpty,
      reason: '⛔premise: a chord no other action is on',
    );
    await tester.pump();
    final below = _panelOf(tester, EditorWorkspace.timelineTabId);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final above = _panelOf(tester, EditorWorkspace.timelineTabId);
    expect(above.top, lessThan(below.top), reason: '⛔premise: it moved up');
    expect(
      tester
          .widget<EditorPanelTabs>(
            find
                .ancestor(
                  of: _gripOf(EditorWorkspace.timelineTabId),
                  matching: find.byType(EditorPanelTabs),
                )
                .first,
          )
          .stripAtBottom,
      isFalse,
      reason: '⛔premise: its strip is on its top edge now',
    );

    final mouse = await aMouse(tester, _awayBelow);
    await expectSeenFromInside(
      tester,
      mouse,
      EditorWorkspace.timelineTabId,
      'the region, at the top',
      away: _awayBelow,
    );
  });

  testWidgets('the band under the pointer is seen whole too — the handle '
      'you reach for', (tester) async {
    await _pumpApp(tester);
    final mouse = await aMouse(tester);
    const tabId = EditorWorkspace.timelineTabId;
    await mouse.moveTo(tester.getCenter(_gripOf(tabId)));
    await tester.pump();

    final ink = GripBand.ink(nearby: true, hovered: true, active: false);
    final rows = await _bandRows(tester, tabId);
    expect(rows, hasLength(GripBand.reach.round()));
    expect(
      [for (final row in rows) _distance(row, ink)],
      everyElement(lessThanOrEqualTo(near)),
      reason: 'painted $rows, its ink is $ink',
    );
  });
}
