// 🗣️I-34 (유저 2026-10-18): 「상단띠 오른쪽에 있는 브러시 사이즈/불투명도 등
// 전체적인것들 그냥 캔버스 패널의 왼쪽 중앙 알약 만들어서 거기로 이동」, then
// 「그리고 기본값은 알약으로 두는걸 기본값으로. 그리고 이름도 브러시 값을
// 상단띠로로 바꾸자」.
//
// THE BRUSH'S VALUES STAND IN ONE PLACE AT A TIME: by default the canvas's
// pill on its left edge, on the top strip where Settings › 패널 › 「브러시 값을
// 상단띠로」 puts them — the choice kept with the layout, and a reset of the
// layout bringing the pill back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/brush_value_group.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settings_flyout.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/number_pad_keyboard.dart';

const pill = ValueKey<String>('canvas-brush-pill');
const row = 'menu-window-brush-values-on-strip';

/// The brush's values that wear the same key wherever they stand.
const parts = [
  'brush-tool-blend-menu-button',
  'brush-tool-pressure-size',
  'brush-tool-pressure-opacity',
];

Finder inStrip(String key) => find.descendant(
  of: find.byType(EditorTopStrip),
  matching: find.byKey(ValueKey<String>(key)),
);

Finder inPill(String key) => find.descendant(
  of: find.byKey(pill),
  matching: find.byKey(ValueKey<String>(key)),
);

Future<void> pumpHome(
  WidgetTester tester, {
  WorkspaceLayoutStore? store,
}) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: HomePage(layoutStore: store)),
  );
  await tester.pumpAndSettle();
}

/// Whether the drawer's row is marked — opened, read, and closed again.
Future<bool> rowMarked(WidgetTester tester) async {
  await openPanelsDrawer(tester);
  final item = find.byKey(const ValueKey<String>(row));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  final marked = tester.booleanDotIn(item).value;
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  return marked;
}

/// The pill's bars' numbers, each in its readout above its bar (I-135).
const readouts = ['brush-pill-size-readout', 'brush-pill-opacity-readout'];

void expectInThePill(String why) {
  expect(find.byKey(pill), findsOneWidget, reason: why);
  for (final key in [
    ...parts,
    'brush-pill-size-bar',
    'brush-pill-opacity-bar',
    ...readouts,
  ]) {
    expect(inPill(key), findsOneWidget, reason: '$key — $why');
  }
  for (final key in [
    ...parts,
    'top-strip-size-bar',
    'top-strip-opacity-bar',
    'top-strip-brush-group-button',
  ]) {
    expect(inStrip(key), findsNothing, reason: '$key off the strip — $why');
  }
}

void expectOnTheStrip(String why) {
  expect(find.byKey(pill), findsNothing, reason: why);
  for (final key in readouts) {
    expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: why);
  }
  for (final key in [
    ...parts,
    'top-strip-size-bar',
    'top-strip-opacity-bar',
  ]) {
    expect(inStrip(key), findsOneWidget, reason: '$key — $why');
  }
}

void main() {
  testWidgets('by default the canvas\'s pill holds them, on its left edge in '
      'the middle of its room, and the strip holds none', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    expectInThePill('the default');
    expect(await rowMarked(tester), isFalse, reason: 'the row says so');

    // Where it stands, against what the floor says covers it.
    final floor = tester.widget<CanvasFloorInsets>(
      find.byType(CanvasFloorInsets),
    );
    final shell = tester.getRect(
      find.byKey(const ValueKey<String>('canvas-editor-panel-shell')).first,
    );
    final seat = tester
        .getRect(find.byKey(const ValueKey<String>('canvas-left-pill')))
        .shift(-shell.topLeft);
    final beside = canvasFloorBandIntrudes(
      floor.leftRailBand,
      top: seat.top,
      bottom: seat.bottom,
    );
    expect(
      seat.left,
      closeTo((beside ? floor.insets.left : 0) + 6, 0.01),
      reason: 'on the left edge, past the left rail where it is beside it',
    );
    final view = tester.getRect(
      find.byKey(const ValueKey<String>('canvas-view-pill')).first,
    );
    final bar = tester.getRect(
      find.byKey(const ValueKey<String>('canvas-panbar-horizontal')).first,
    );
    expect(
      seat.center.dy + shell.top,
      closeTo((view.bottom + 6 + bar.top - 6) / 2, 0.5),
      reason: 'in the middle of the room under the pill\'s band, over the '
          'bar\'s row',
    );
  });

  testWidgets('Settings › 패널 › 「브러시 값을 상단띠로」 stands them on the strip, '
      'and again brings them back to the pill', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    await tapPanelsDrawerRow(tester, row);
    expectOnTheStrip('the row put them there');
    expect(await rowMarked(tester), isTrue);

    await tapPanelsDrawerRow(tester, row);
    expectInThePill('the row took them back');
    expect(await rowMarked(tester), isFalse);
  });

  testWidgets('the layout file keeps the choice — a restart stands them where '
      'they were left, and a reset of the layout brings the pill back', (
    tester,
  ) async {
    // Real file IO only inside runAsync — awaited on the fake clock a
    // testWidgets body runs on, createTemp never completes.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('brush_values_place'),
    ))!;
    deleteAfterSessionEnds(directory);
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, store: store);

    await tapPanelsDrawerRow(tester, row);
    // The save is debounced 800 ms behind the last change; the write is real
    // IO whose steps complete in real time and continue on the fake clock.
    await tester.pump(const Duration(milliseconds: 900));
    Object? saved;
    await settleAsync(tester, () async {
      final payload = await tester.runAsync<Map<String, Object?>?>(store.load);
      saved = payload?['brushValuesOnStrip'];
      return saved != null;
    });
    expect(saved, isTrue, reason: 'the row is the change that saved');

    // A restart: the old workspace goes, a new one reads the same file.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, store: store);
    await settleAsync(tester, () => !tester.any(find.byKey(pill)));
    await tester.pumpAndSettle();
    expectOnTheStrip('the restored layout');

    await tapPanelsDrawerRow(tester, 'menu-window-reset-layout');
    expectInThePill('the reset');
  });

  testWidgets('the pill as it was drawn (시안 판 6; I-135-Q1 a): as wide as '
      'its numbers, every part 20 across and centred in it, the two bars one '
      'length — each without its name — and the blend as long as their '
      'tracks, written down it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    // The pill as DRAWN is the size it lays itself out at (`getSize`), not
    // the one it is shown at: a room shorter than the pill shows the whole
    // pill smaller (the panel's pin 'a panel shorter than the left pill
    // gets the whole pill, …'), and this window's default layout is such a
    // room — 405 for a pill 494 tall (measured 2026-10-19, on the commit
    // that wrote this pin too).
    // ↩️28 until its numbers stood over its bars (I-135): as wide as they
    // are, and the ring's pixel either side — 37 in the app's face
    // (`the_brush_pill_writes_its_numbers_above_its_bars_test`).
    expect(
      tester.getSize(find.byKey(pill)).width,
      tester.getSize(inPill(readouts.first)).width + 2,
    );
    final box = tester.getRect(find.byKey(pill));
    Size part(String key) => tester.getSize(inPill(key));
    for (final key in [
      ...parts,
      'brush-pill-size-bar',
      'brush-pill-opacity-bar',
    ]) {
      expect(part(key).width, 20, reason: '$key across');
      expect(
        tester.getRect(inPill(key)).center.dx,
        closeTo(box.center.dx, 0.01),
        reason: '$key centred',
      );
    }
    final size = part('brush-pill-size-bar');
    expect(part('brush-pill-opacity-bar').height, size.height);
    // Each bar's curve one step under it — where the pill lays them, not
    // where it is shown smaller.
    final drawn = tester.renderObject<RenderBox>(find.byKey(pill));
    double top(String key) => tester
        .renderObject<RenderBox>(inPill(key))
        .localToGlobal(Offset.zero, ancestor: drawn)
        .dy;
    expect(
      top('brush-tool-pressure-size') - top('brush-pill-size-bar'),
      size.height + BrushValueBars.gap,
    );
    for (final (bar, name) in [
      ('brush-pill-size-bar', AppText.strings.brSize),
      ('brush-pill-opacity-bar', AppText.strings.brOpacity),
    ]) {
      expect(
        find.descendant(of: inPill(bar), matching: find.text(name)),
        findsNothing,
        reason: '$bar: the number alone (I-34-Q3 「숫자만」)',
      );
    }
    expect(
      part('brush-tool-blend-menu-button').height,
      size.height - FieldSlider.readoutHandsReach,
    );
    expect(
      find.descendant(
        of: inPill('brush-tool-blend-menu-button'),
        matching: find.byType(VerticalWritingText),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(pill), matching: find.byType(Divider)),
      findsOneWidget,
      reason: 'the rule between the blend and the bars lies across',
    );

    // The eraser's blend is the same button, dimmed on its one mode (F-442).
    await tester.tap(find.byKey(const ValueKey<String>('tool-eraser-button')));
    await tester.pumpAndSettle();
    final dimmed = inPill('brush-tool-blend-menu-button');
    expect(tester.widget<PanelFlyoutButton>(dimmed).enabled, isFalse);
    expect(tester.getSize(dimmed).width, 20);
    expect(
      find.descendant(of: dimmed, matching: find.byType(VerticalWritingText)),
      findsOneWidget,
    );
  });

  testWidgets('stood, the blend is as thick as it is told in any room — not '
      'only where the pill holds it to that', (tester) async {
    final brushTool = ValueNotifier(BrushToolState.defaults);
    addTearDown(brushTool.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BrushBlendModeControl(
            brushTool: brushTool,
            axis: Axis.vertical,
            length: 300,
            thickness: 20,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(BrushBlendModeControl)),
      const Size(20, 300),
    );
  });

  testWidgets('the pill\'s numbers stand whole in their readouts — at twice '
      'the OS text too: the two readouts one size, the wider number\'s', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    // The size's readout is its bar's pencil: a press opens the bar's number
    // pad (I-134). ↩️It typed into the bar, in the row turned a quarter
    // clockwise, its field the bar's track whole.
    await tester.tap(inPill(readouts.first));
    await tester.pumpAndSettle();
    await openThePadsKeyboard(tester);
    final input = find.byKey(const ValueKey<String>('field-slider-type-input'));
    await tester.enterText(input, '2000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The NUMBER each readout writes, which this is about: whole means its
    // line asks no more than the readout holds, across and down.
    final boxes = [for (final key in readouts) inPill(key)];
    expect(tester.getSize(boxes.last), tester.getSize(boxes.first));
    final written = <String>[];
    for (final box in boxes) {
      final number = find.descendant(of: box, matching: find.byType(Text));
      expect(number, findsOneWidget, reason: '⛔fixture premise: it writes');
      written.add(tester.widget<Text>(number).data!);
      final line = tester.renderObject<RenderParagraph>(
        find.descendant(of: number, matching: find.byType(RichText)),
      );
      final room = tester.getSize(box);
      expect(
        line.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(room.width),
        reason: written.last,
      );
      expect(
        line.getMaxIntrinsicHeight(double.infinity),
        lessThanOrEqualTo(room.height),
        reason: '${written.last}: its line grown with the OS text',
      );
    }
    expect(written.first, '2000.0', reason: '⛔premise: the widest it says');
  });
}
