import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_mixing_method.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_settings_group.dart';
import 'package:anicel/src/models/brush_settings_row.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/services/brush_hand_overlay.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/group_tab.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/rail_group_button.dart';
import '../../helpers/settings_flyout.dart';
import '../../helpers/settle_async.dart';

/// 🗣️I-141 (유저 2026-10-29): a brush shows in the tool settings only the
/// rows it chose — Q1 ⓐ 「클튜식 — 상세 창에서 고른다」, Q2 「패널 본래 순서
/// 그대로」, no heads 「멤버만 심플하게 하나씩」 — chosen in a window that
/// floats over the canvas (Q3 「떠 있는 창(클튜처럼)」), its groups down its
/// left side as the brush library's are (Q4 「클튜처럼 왼쪽에 두자.
/// 브러시그룹/브러시목록이랑 비슷한느낌으로」).
void main() {
  final plain = BrushSettings();
  final some = plain.copyWith(
    shown: {BrushSettingsRow.spacing, BrushSettingsRow.flow},
  );

  group('a brush keeps what it shows as its own', () {
    test('written off the three every brush shows, read back — and a brush '
        'showing nothing is not one that never said', () {
      expect(plain.shown, BrushSettingsRow.shownByDefault);
      expect(plain.toJson().containsKey('shown'), isFalse);
      expect(
        BrushSettings.fromJson(plain.toJson()).shown,
        BrushSettingsRow.shownByDefault,
      );

      expect(some.toJson()['shown'], ['flow', 'spacing'], reason: 'in order');
      expect(BrushSettings.fromJson(some.toJson()), some);

      final none = plain.copyWith(shown: const {});
      expect(none.toJson()['shown'], isEmpty);
      expect(BrushSettings.fromJson(none.toJson()).shown, isEmpty);

      expect(some, isNot(plain));
      expect(
        some,
        isNot(
          plain.copyWith(
            shown: {BrushSettingsRow.flow, BrushSettingsRow.hardness},
          ),
        ),
        reason: 'as many shown, not the same rows',
      );
    });

    test('what the hand chose comes back with the brush — and so does '
        'handing a brush back to the three', () {
      final choosing = brushHandOverlay(
        file: plain,
        hand: some,
        byName: (_) => true,
      );
      expect(brushSettingsUnderHand(plain, choosing).shown, some.shown);

      final back = brushHandOverlay(
        file: some,
        hand: plain,
        byName: (_) => true,
      );
      expect(
        brushSettingsUnderHand(some, back).shown,
        BrushSettingsRow.shownByDefault,
      );
    });

    test('the brush in hand holds what it shows: taken up from its settings '
        'or its preset, carried to another tool, and written back', () {
      final preset = BrushPreset(
        id: const BrushPresetId('pen'),
        name: 'pen',
        settings: some,
      );
      final held = BrushToolState.defaults.withPreset(
        preset,
        tool: CanvasTool.brush,
      );
      expect(held.shown, some.shown);
      expect(held.toBrushSettings().shown, some.shown);
      expect(held.copyWith(flow: 0.3).shown, some.shown);
      expect(held.withMask(BrushMaskSlot.texture, null).shown, some.shown);
      expect(held, isNot(held.copyWith(shown: const {})));
      expect(BrushToolState.fromBrushSettings(some).shown, some.shown);
      expect(
        BrushToolState.defaults
            .withPreset(preset, tool: CanvasTool.brush, held: plain)
            .shown,
        BrushSettingsRow.shownByDefault,
        reason: 'the hand\'s brush, not the file\'s',
      );
      expect(BrushToolState.defaults.carryingBrushOf(held).shown, some.shown);
    });

    test('every built-in shows the three and what its group\'s brushes are '
        'turned by most', () {
      Set<BrushSettingsRow> shownBy(String id) => defaultBrushPresets
          .firstWhere((preset) => preset.id.value == id)
          .settings
          .shown;
      for (final preset in defaultBrushPresets) {
        expect(
          preset.settings.shown,
          containsAll(BrushSettingsRow.shownByDefault),
          reason: preset.id.value,
        );
      }
      expect(shownBy('builtin-ink-pen'), contains(BrushSettingsRow.hardness));
      for (final (id, row) in [
        ('builtin-pencil', BrushSettingsRow.textureDensity),
        ('builtin-g-pen', BrushSettingsRow.postCorrection),
        ('builtin-charcoal', BrushSettingsRow.textureDensity),
      ]) {
        expect(shownBy(id), contains(row), reason: id);
      }
      expect(
        shownBy('builtin-oil-brush'),
        containsAll([
          BrushSettingsRow.paintAmount,
          BrushSettingsRow.paintDensity,
          BrushSettingsRow.colorStretch,
        ]),
      );
      expect(shownBy('builtin-airbrush'), contains(BrushSettingsRow.flow));
      expect(
        shownBy('builtin-leaves'),
        containsAll([BrushSettingsRow.scatter, BrushSettingsRow.scatterCount]),
      );
      expect(
        shownBy('builtin-airbrush'),
        isNot(contains(BrushSettingsRow.hardness)),
        reason: 'a group\'s own, not every group\'s',
      );
    });
  });

  group('the panel and the brush detail window', () {
    const panelKey = ValueKey<String>('brush-settings-panel');
    final window = find.byKey(const ValueKey<String>('brush-detail-window'));
    final wrench = find.byKey(const ValueKey<String>('brush-detail-button'));

    /// [key] in the panel — while the window is closed: the window hangs
    /// off the wrench in the element tree, so its rows would count too.
    /// With it open, [panelRows] says what the panel stands.
    Finder inPanel(String key) => find.descendant(
      of: find.byKey(panelKey),
      matching: find.byKey(ValueKey<String>(key)),
    );
    Finder inWindow(String key) => find.descendant(
      of: window,
      matching: find.byKey(ValueKey<String>(key)),
    );

    /// Every switch on: two tips, a mix, a dual tip and a texture, the line
    /// steadied and 後補正 at strength — every row stands.
    final everyRowStands = BrushToolState.defaults.copyWith(
      tips: [chalkBrushTipMask, grainBrushTipMask],
      mixesGroundColor: true,
      mixingMethod: BrushMixingMethod.mix,
      correction: const BrushCorrection(steadies: true, postStrength: 30),
      shown: BrushSettingsRow.values.toSet(),
    ).withMask(BrushMaskSlot.dual, splatterBrushTipMask)
        .withMask(BrushMaskSlot.texture, spongeBrushTipMask);

    late int canvasDowns;

    Future<ValueNotifier<BrushToolState>> pumpPanel(
      WidgetTester tester,
      BrushToolState start, {
      ValueNotifier<Offset?>? at,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      canvasDowns = 0;
      final notifier = ValueNotifier<BrushToolState>(start);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Stack(
              children: [
                // The canvas: under everything, taking every press it gets.
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => canvasDowns += 1,
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: SingleChildScrollView(
                      child: ValueListenableBuilder<BrushToolState>(
                        valueListenable: notifier,
                        builder: (context, state, _) => BrushSettingsPanel(
                          state: state,
                          onChanged: (next) => notifier.value = next,
                          detailAt: at,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return notifier;
    }

    /// The rows the panel stands, top to bottom.
    List<Object?> panelRows(WidgetTester tester) => [
      for (final child
          in tester.widget<Column>(find.byKey(panelKey)).children)
        if (child.key case ValueKey<BrushSettingsRow>(:final value)) value,
    ];

    testWidgets('the panel shows the rows the brush shows, in the panel\'s '
        'order, with no group heads', (tester) async {
      await pumpPanel(
        tester,
        BrushToolState.defaults.copyWith(
          shown: {
            BrushSettingsRow.scatter,
            BrushSettingsRow.flow,
            BrushSettingsRow.spacing,
          },
        ),
      );
      expect(panelRows(tester), [
        BrushSettingsRow.flow,
        BrushSettingsRow.spacing,
        BrushSettingsRow.scatter,
      ]);
      expect(inPanel('brush-tool-roundness-slider'), findsNothing);
      expect(find.byType(ToolSettingsGroupHeader), findsNothing);
    });

    testWidgets('🚨every row has its place: a brush showing them all, every '
        'switch on, stands each once, in the order the rows are listed', (
      tester,
    ) async {
      await pumpPanel(tester, everyRowStands);
      expect(panelRows(tester), BrushSettingsRow.values);
    });

    testWidgets('a row the brush shows stands only while the switch above it '
        'is on (F-478-Q2)', (tester) async {
      final notifier = await pumpPanel(
        tester,
        BrushToolState.defaults.copyWith(
          correction: BrushCorrection.none,
        ),
      );
      expect(notifier.value.shown, contains(BrushSettingsRow.stabilizer));
      expect(inPanel('brush-tool-stabilizer-slider'), findsNothing);

      notifier.value = notifier.value.copyWith(
        correction: const BrushCorrection(steadies: true),
      );
      await tester.pump();
      expect(inPanel('brush-tool-stabilizer-slider'), findsOneWidget);
    });

    testWidgets('the wrench opens the window: the groups down its side as '
        'the brush library\'s tabs, and the group\'s rows, each with its '
        'eye — which shows it in the panel or not', (tester) async {
      final notifier = await pumpPanel(tester, BrushToolState.defaults);
      expect(window, findsNothing);

      await tester.tap(wrench);
      await tester.pump();
      expect(window, findsOneWidget);
      expect(
        find.descendant(of: window, matching: find.byType(GroupTab)),
        findsNWidgets(BrushSettingsGroup.values.length),
      );
      expect(inWindow('brush-tool-flow-slider'), findsOneWidget);
      expect(inWindow('brush-tool-sharpen-corners'), findsNothing);

      await tester.tap(inWindow('brush-detail-group-correction'));
      await tester.pump();
      expect(inWindow('brush-tool-flow-slider'), findsNothing);
      expect(inWindow('brush-tool-sharpen-corners'), findsOneWidget);
      expect(
        panelRows(tester),
        isNot(contains(BrushSettingsRow.sharpenCorners)),
      );

      await tester.tap(find.named('brush-detail-eye-sharpenCorners'));
      await tester.pump();
      expect(notifier.value.shown, contains(BrushSettingsRow.sharpenCorners));
      expect(panelRows(tester), contains(BrushSettingsRow.sharpenCorners));

      await tester.tap(find.named('brush-detail-eye-sharpenCorners'));
      await tester.pump();
      expect(
        notifier.value.shown,
        isNot(contains(BrushSettingsRow.sharpenCorners)),
      );
      expect(
        panelRows(tester),
        isNot(contains(BrushSettingsRow.sharpenCorners)),
      );
    });

    testWidgets('a row in the window is the panel\'s own: it sets the brush '
        'as the panel\'s does', (tester) async {
      final notifier = await pumpPanel(tester, BrushToolState.defaults);
      await tester.tap(wrench);
      await tester.pump();
      await tester.tap(inWindow('brush-detail-group-correction'));
      await tester.pump();
      final before = notifier.value.correction.sharpenCorners;

      // The ring: a switch row takes its press there alone (탭만).
      await tester.tap(inWindow('brush-tool-sharpen-corners-ring'));
      await tester.pump();
      expect(notifier.value.correction.sharpenCorners, !before);
    });

    testWidgets('🚨the canvas under it keeps taking the pen while it is open '
        '— the window takes only its own presses', (tester) async {
      await pumpPanel(tester, BrushToolState.defaults);
      await tester.tap(wrench);
      await tester.pump();
      final box = tester.getRect(window);

      await tester.tapAt(const Offset(1150, 850));
      await tester.pump();
      expect(canvasDowns, 1, reason: 'no barrier between it and the canvas');
      expect(window, findsOneWidget, reason: 'and the press did not close it');

      await tester.tapAt(box.bottomRight - const Offset(8, 8));
      await tester.pump();
      expect(canvasDowns, 1, reason: 'a press on the window is the window\'s');
    });

    testWidgets('its title bar moves it, it opens again where it was left, '
        'and it stays inside the screen', (tester) async {
      final at = ValueNotifier<Offset?>(null);
      addTearDown(at.dispose);
      await pumpPanel(tester, BrushToolState.defaults, at: at);
      await tester.tap(wrench);
      await tester.pump();
      final opened = tester.getTopLeft(window);
      expect(
        tester.getCenter(window),
        const Offset(600, 450),
        reason: 'a window never moved opens in the middle',
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('app-window-title-drag')),
        const Offset(-200, 120),
      );
      await tester.pump();
      final moved = tester.getTopLeft(window);
      expect(moved.dx, lessThan(opened.dx));
      expect(moved.dy, greaterThan(opened.dy));
      expect(at.value, moved, reason: 'the host keeps where it stands');

      await tester.tap(
        find.descendant(
          of: window,
          matching: find.byKey(const ValueKey<String>('app-window-close')),
        ),
      );
      await tester.pump();
      expect(window, findsNothing);
      await tester.tap(wrench);
      await tester.pump();
      expect(tester.getTopLeft(window), moved);

      await tester.drag(
        find.byKey(const ValueKey<String>('app-window-title-drag')),
        const Offset(3000, 3000),
      );
      await tester.pump();
      expect(
        tester.getBottomRight(window),
        const Offset(1200, 900),
        reason: 'held in by the screen, not let past it',
      );

      await tester.tap(wrench);
      await tester.pump();
      expect(window, findsNothing, reason: 'the wrench closes it too');
    });
  });

  testWidgets('🚨the layout file keeps where the window was left — a restart '
      'opens it there, and a workspace reset puts it back in the middle', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('brush_detail_at'),
    ))!;
    deleteAfterSessionEnds(directory);
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final window = find.byKey(const ValueKey<String>('brush-detail-window'));
    final wrench = find.byKey(const ValueKey<String>('brush-detail-button'));

    Future<void> pumpHome() async {
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: HomePage(layoutStore: store)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openWindow() async {
      if (wrench.evaluate().isEmpty) {
        await pressToolSettingsButton(tester);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(wrench);
      await tester.pumpAndSettle();
      await tester.tap(wrench);
      await tester.pumpAndSettle();
    }

    await pumpHome();
    await openWindow();
    const middle = Offset(800, 500);
    expect(tester.getCenter(window), middle);
    await tester.drag(
      find.byKey(const ValueKey<String>('app-window-title-drag')),
      const Offset(-300, 150),
    );
    await tester.pumpAndSettle();
    final left = tester.getTopLeft(window);
    expect(left.dx, lessThan(middle.dx - 240), reason: 'premise: it moved');
    expect(left.dy, greaterThan(middle.dy - 200));

    await tester.pump(const Duration(milliseconds: 900));
    Object? saved;
    await settleAsync(tester, () async {
      final payload = await tester.runAsync<Map<String, Object?>?>(store.load);
      saved = payload?['brushDetailAt'];
      return saved != null;
    });
    expect(saved, [left.dx, left.dy]);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome();
    await settleAsync(tester, () async => true);
    await openWindow();
    await settleAsync(tester, () async => tester.getTopLeft(window) == left);
    expect(tester.getTopLeft(window), left);

    await tapPanelsDrawerRow(tester, 'menu-window-reset-layout');
    await tester.pumpAndSettle();
    if (window.evaluate().isEmpty) {
      await openWindow();
    }
    expect(tester.getCenter(window), middle);
  });
}
