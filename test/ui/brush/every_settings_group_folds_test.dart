import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_settings_group.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/brush_hand_overlay.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️F-418-Q10 (유저 2026-10-20) — a: 「모든 그룹 머리가 접힌다」. A press
/// on a group's header folds the group and opens it again; a brush keeps
/// its folds as its own, the other tools each theirs.
void main() {
  final strings = AppText.strings;
  const roundness = ValueKey<String>('brush-tool-roundness-slider');
  const flow = ValueKey<String>('brush-tool-flow-slider');
  const stabilizer = ValueKey<String>('brush-tool-stabilizer-slider');

  final plain = BrushToolState.defaults.toBrushSettings();
  final tipFolded = plain.copyWith(folded: {BrushSettingsGroup.tip});

  Finder arrowOf(String header, IconData icon) => find.descendant(
    of: find.ancestor(of: find.text(header), matching: find.byType(Row)),
    matching: find.byIcon(icon),
  );

  group('a brush keeps its folds as its own', () {
    test('they go out with its settings and come back, and a brush that '
        'folds nothing writes nothing', () {
      final both = plain.copyWith(
        folded: {BrushSettingsGroup.texture, BrushSettingsGroup.tip},
      );

      expect(both.toJson()['folded'], ['tip', 'texture']);
      expect(BrushSettings.fromJson(both.toJson()), both);
      expect(plain.toJson().containsKey('folded'), isFalse);
      expect(BrushSettings.fromJson(plain.toJson()).folded, isEmpty);
      expect(both, isNot(tipFolded), reason: 'two brushes, told apart');
      expect(tipFolded, isNot(both));
    });

    test('a fold is what the hand changed on the brush: it comes back with '
        'it — and so does opening a group its file folds', () {
      final folding = brushHandOverlay(
        file: plain,
        hand: tipFolded,
        byName: (_) => true,
      );
      expect(brushSettingsUnderHand(plain, folding).folded, {
        BrushSettingsGroup.tip,
      });

      final opening = brushHandOverlay(
        file: tipFolded,
        hand: plain,
        byName: (_) => true,
      );
      expect(brushSettingsUnderHand(tipFolded, opening).folded, isEmpty);
    });

    test('the brush in hand holds its folds: taken up from its settings or '
        'its preset, carried to another tool, and written back', () {
      final preset = BrushPreset(
        id: const BrushPresetId('pen'),
        name: 'pen',
        settings: tipFolded,
      );

      final held = BrushToolState.defaults.withPreset(
        preset,
        tool: CanvasTool.brush,
      );
      expect(held.folded, {BrushSettingsGroup.tip});
      expect(held.toBrushSettings().folded, {BrushSettingsGroup.tip});
      expect(
        held.copyWith(flow: 0.3).folded,
        {BrushSettingsGroup.tip},
        reason: 'a setting moved leaves the folds as they were',
      );
      expect(held, isNot(held.copyWith(folded: const {})));
      expect(BrushToolState.fromBrushSettings(tipFolded).folded, {
        BrushSettingsGroup.tip,
      });
      expect(
        BrushToolState.defaults
            .withPreset(preset, tool: CanvasTool.brush, held: plain)
            .folded,
        isEmpty,
        reason: 'the hand\'s brush, not the file\'s',
      );
      expect(BrushToolState.defaults.carryingBrushOf(held).folded, {
        BrushSettingsGroup.tip,
      });
    });
  });

  group('the brush\'s panel', () {
    Future<ValueNotifier<BrushToolState>> pumpPanel(
      WidgetTester tester,
    ) async {
      final notifier = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<BrushToolState>(
                valueListenable: notifier,
                builder: (context, state, _) => BrushSettingsPanel(
                  state: state,
                  onChanged: (next) => notifier.value = next,
                ),
              ),
            ),
          ),
        ),
      );
      return notifier;
    }

    testWidgets('a press on a group\'s header folds that group alone into '
        'the brush, and a second opens it', (tester) async {
      final notifier = await pumpPanel(tester);
      expect(find.byKey(roundness), findsOneWidget);
      expect(arrowOf(strings.brGroupTip, Icons.expand_more), findsOneWidget);

      await tester.tap(find.text(strings.brGroupTip));
      await tester.pump();

      expect(notifier.value.folded, {BrushSettingsGroup.tip});
      expect(find.byKey(roundness), findsNothing);
      expect(arrowOf(strings.brGroupTip, Icons.chevron_right), findsOneWidget);
      expect(find.byKey(flow), findsOneWidget, reason: 'インク stays open');
      expect(find.byKey(stabilizer), findsOneWidget, reason: '補正 too');

      await tester.tap(find.text(strings.brGroupTip));
      await tester.pump();

      expect(notifier.value.folded, isEmpty);
      expect(find.byKey(roundness), findsOneWidget);
    });

    testWidgets('🚨every group folds: each header takes its own rows away', (
      tester,
    ) async {
      final notifier = await pumpPanel(tester);
      final groups = {
        strings.brGroupInk: BrushSettingsGroup.ink,
        strings.brGroupTip: BrushSettingsGroup.tip,
        strings.brGroupMixing: BrushSettingsGroup.mixing,
        strings.brGroupScattering: BrushSettingsGroup.scattering,
        strings.brGroupTexture: BrushSettingsGroup.texture,
        strings.brGroupCorrection: BrushSettingsGroup.correction,
      };
      int rowCount() => tester
          .widget<Column>(
            find.byKey(const ValueKey<String>('brush-settings-panel')),
          )
          .children
          .length;
      final allRows = rowCount();

      for (final MapEntry(key: header, value: group) in groups.entries) {
        await tester.tap(find.text(header));
        await tester.pump();
        expect(notifier.value.folded, {group}, reason: header);
        expect(rowCount(), lessThan(allRows), reason: header);
        expect(
          arrowOf(header, Icons.chevron_right),
          findsOneWidget,
          reason: header,
        );
        await tester.tap(find.text(header));
        await tester.pump();
        expect(notifier.value.folded, isEmpty, reason: header);
      }
    });

    testWidgets('another brush shows its own folds', (tester) async {
      final notifier = await pumpPanel(tester);
      notifier.value = BrushToolState.fromBrushSettings(tipFolded);
      await tester.pump();
      expect(find.byKey(roundness), findsNothing);

      notifier.value = BrushToolState.defaults;
      await tester.pump();
      expect(find.byKey(roundness), findsOneWidget);
    });
  });

  group('the other tools, each its own', () {
    tearDown(ToolSettingsFolds.reset);

    Future<void> pumpTool(WidgetTester tester, CanvasTool tool) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 1600,
              child: ToolSettingsPanel(
                state: BrushToolState(tool: tool),
                onChanged: (_) {},
                fillOptions: const FloodFillOptions(),
                onFillOptionsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));

    testWidgets('the text tool\'s 글자 and 상자 fold apart, and stay folded '
        'while another tool is held', (tester) async {
      await pumpTool(tester, CanvasTool.text);
      expect(byKey('text-tool-font'), findsOneWidget);
      expect(byKey('text-tool-rotation'), findsOneWidget);

      await tester.tap(find.text(strings.textToolLetters));
      await tester.pump();
      expect(byKey('text-tool-font'), findsNothing);
      expect(byKey('text-tool-rotation'), findsOneWidget);
      expect(
        arrowOf(strings.textToolLetters, Icons.chevron_right),
        findsOneWidget,
      );

      await pumpTool(tester, CanvasTool.move);
      expect(
        byKey('move-antialias-switch'),
        findsOneWidget,
        reason: 'the text tool\'s fold is its own',
      );
      await pumpTool(tester, CanvasTool.text);
      expect(byKey('text-tool-font'), findsNothing);

      await tester.tap(find.text(strings.textToolLetters));
      await tester.pump();
      expect(byKey('text-tool-font'), findsOneWidget);
    });

    testWidgets('the transform tool\'s 마무리 folds — its buttons stay', (
      tester,
    ) async {
      await pumpTool(tester, CanvasTool.move);

      await tester.tap(find.text(strings.trFinish));
      await tester.pump();
      expect(byKey('move-antialias-switch'), findsNothing);
      expect(byKey('move-reset-button'), findsOneWidget);
      expect(arrowOf(strings.trFinish, Icons.chevron_right), findsOneWidget);

      await tester.tap(find.text(strings.trFinish));
      await tester.pump();
      expect(byKey('move-antialias-switch'), findsOneWidget);
    });

    testWidgets('the ruler\'s 소실점 fold as the ruler\'s, whichever guide '
        'is picked', (tester) async {
      DrawingGuide perspective(String id) => DrawingGuide(
        id: GuideId(id),
        name: id,
        shape: PerspectiveShape(
          vanishingPoints: [
            VanishingPointAt(CanvasPoint(x: 100, y: 50)),
          ],
          eyeLevel: GuideAxis(
            origin: CanvasPoint(x: 50, y: 50),
            angleDegrees: 0,
          ),
        ),
      );
      final guides = CutGuides(guides: [perspective('a'), perspective('b')]);
      Future<void> pick(String id) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuideSettings(
              guides: guides,
              selectedGuideId: GuideId(id),
              canvasSize: const CanvasSize(width: 800, height: 600),
              onGuidesCommitted: (_) {},
              onGuidesPreview: (_) {},
              onGuideRasterized: null,
            ),
          ),
        ),
      );
      final point = byKey('guide-vanishing-point-0');

      await pick('a');
      expect(point, findsOneWidget);
      await tester.tap(find.text(strings.guideVanishingPoint));
      await tester.pump();
      expect(point, findsNothing);
      expect(byKey('guide-add-vanishing-point'), findsOneWidget);

      await pick('b');
      expect(point, findsNothing);
      await tester.tap(find.text(strings.guideVanishingPoint));
      await tester.pump();
      expect(point, findsOneWidget);
    });
  });
}
