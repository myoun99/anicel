import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️F-418-Q10 (유저 2026-10-20) — a: 「모든 그룹 머리가 접힌다」. A press
/// on a group's header folds the group and opens it again, each tool's its
/// own. ↩️A brush kept its folds as its own too, until its settings showed
/// the rows a brush shows with no heads (I-141 —
/// `a_brush_shows_the_settings_it_chose_test`).
void main() {
  final strings = AppText.strings;

  /// The group header named [label] — not a row that shares its word.
  Finder headerOf(String label) => find.descendant(
    of: find.byType(ToolSettingsGroupHeader),
    matching: find.text(label),
  );

  Finder arrowOf(String header, IconData icon) => find.descendant(
    of: find.ancestor(
      of: headerOf(header),
      matching: find.byType(ToolSettingsGroupHeader),
    ),
    matching: find.byIcon(icon),
  );

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

      await tester.tap(headerOf(strings.textToolLetters));
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

      await tester.tap(headerOf(strings.textToolLetters));
      await tester.pump();
      expect(byKey('text-tool-font'), findsOneWidget);
    });

    testWidgets('the transform tool\'s 마무리 folds — its buttons stay', (
      tester,
    ) async {
      await pumpTool(tester, CanvasTool.move);

      await tester.tap(headerOf(strings.trFinish));
      await tester.pump();
      expect(byKey('move-antialias-switch'), findsNothing);
      expect(byKey('move-reset-button'), findsOneWidget);
      expect(arrowOf(strings.trFinish, Icons.chevron_right), findsOneWidget);

      await tester.tap(headerOf(strings.trFinish));
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
      await tester.tap(headerOf(strings.guideVanishingPoint));
      await tester.pump();
      expect(point, findsNothing);
      expect(byKey('guide-add-vanishing-point'), findsOneWidget);

      await pick('b');
      expect(point, findsNothing);
      await tester.tap(headerOf(strings.guideVanishingPoint));
      await tester.pump();
      expect(point, findsOneWidget);
    });
  });
}
