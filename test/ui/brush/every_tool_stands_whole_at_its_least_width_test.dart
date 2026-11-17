import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_in_and_out.dart';
import 'package:anicel/src/models/brush_mixing_method.dart';
import 'package:anicel/src/models/brush_settings_row.dart';
import 'package:anicel/src/models/brush_shape.dart' show BrushMaskSlot;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/fill_gradient.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/app_faces.dart';

/// 🗣️tool-settings-segments-overlap-at-the-narrowest-Q1 (유저 2026-11-17):
/// 「도구 설정이 든 레일은 설정 칸이 서는 폭보다 좁아지지 않게 한다」.
///
/// Each tool's settings, every choice they can show standing, laid at the
/// least width the panel says that tool needs: every answer's word whole —
/// and a pixel narrower, one of them cut, so the least is no wider than
/// the words make it. A choice a section adds and its least width does not
/// count is cut here.
void main() {
  const vanishing = GuideId('p1');

  /// Every row of the brush standing: a mix, a texture, the line steadied.
  final everyBrushRow =
      BrushToolState.defaults
          .copyWith(
            tips: [chalkBrushTipMask, grainBrushTipMask],
            mixesGroundColor: true,
            mixingMethod: BrushMixingMethod.mix,
            correction: const BrushCorrection(steadies: true, postStrength: 30),
            inAndOut: const BrushInAndOut(inLength: 20),
            shown: BrushSettingsRow.values.toSet(),
          )
          .withMask(BrushMaskSlot.dual, splatterBrushTipMask)
          .withMask(BrushMaskSlot.texture, spongeBrushTipMask);

  BrushToolState stateFor(CanvasTool tool) => switch (tool) {
    CanvasTool.brush || CanvasTool.eraser => everyBrushRow.copyWith(tool: tool),
    // The plain line: its corners stand under its type.
    CanvasTool.shape => BrushToolState.defaults.copyWith(
      tool: tool,
      shapeOptions: const ShapeToolOptions(type: ShapeLineType.plain),
    ),
    _ => BrushToolState.defaults.copyWith(tool: tool),
  };

  /// What a tool's settings show differently by what they are set to —
  /// the text's alignment names the sides of a line or of a column.
  List<bool> facesOf(CanvasTool tool) =>
      tool == CanvasTool.text ? const [false, true] : const [false];

  /// A vanishing point, whose last line holds the 「평행」 pill.
  final guides = CutGuides(
    guides: [
      DrawingGuide(
        id: vanishing,
        name: 'P',
        shape: PerspectiveShape(
          eyeLevel: GuideAxis(
            origin: CanvasPoint(x: 100, y: 200),
            angleDegrees: 0,
          ),
          vanishingPoints: [VanishingPointAt(CanvasPoint(x: -100, y: 200))],
        ),
      ),
    ],
  );

  Future<void> pumpAt(
    WidgetTester tester,
    CanvasTool tool,
    double width, {
    required bool columns,
  }) async {
    final text = ValueNotifier(TextToolOptions(vertical: columns));
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 4000,
              child: ToolSettingsPanel(
                state: stateFor(tool),
                onChanged: (_) {},
                // The gradient on: its two choices stand under it.
                fillOptions: const FloodFillOptions(
                  gradient: FillGradientOptions(enabled: true),
                ),
                onFillOptionsChanged: (_) {},
                textOptions: text,
                guides: guides,
                selectedGuideId: vanishing,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Every answer's word — a glyph's too, which is laid as a line — at its
  /// whole width, and how many answers there are.
  ({bool whole, int answers}) answersIn(WidgetTester tester) {
    final lines = find
        .descendant(
          of: find.byType(Pill),
          matching: find.byWidgetPredicate((line) => line is RichText),
        )
        .evaluate()
        .map((line) => line.renderObject! as RenderParagraph)
        .toList();
    return (
      whole: lines.every(
        (line) =>
            line.size.width + 0.01 >=
            line.getMaxIntrinsicWidth(double.infinity),
      ),
      answers: lines.length,
    );
  }

  /// Whether [tool]'s answers stand whole at [width] in every face.
  Future<({bool whole, int answers})> standingAt(
    WidgetTester tester,
    CanvasTool tool,
    double width,
  ) async {
    var whole = true;
    var answers = 0;
    for (final columns in facesOf(tool)) {
      await pumpAt(tester, tool, width, columns: columns);
      final face = answersIn(tester);
      whole = whole && face.whole;
      answers += face.answers;
    }
    return (whole: whole, answers: answers);
  }

  for (final language in AppLanguage.values) {
    testWidgets('every tool\'s choices stand whole at its least width, and '
        'a pixel less cuts one — ${language.name}', (tester) async {
      await loadTheAppFaces();
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      for (final tool in CanvasTool.values) {
        await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const Scaffold()),
        );
        final context = tester.element(find.byType(Scaffold));
        final least = ToolSettingsPanel.minWidthOf(tool, context);
        expect(
          least,
          lessThanOrEqualTo(ToolSettingsPanel.minPanelWidthIn(context)),
        );

        final at = await standingAt(tester, tool, least);
        expect(at.whole, isTrue, reason: '${tool.name} at $least');
        if (at.answers == 0) {
          continue;
        }
        expect(
          (await standingAt(tester, tool, least - 1)).whole,
          isFalse,
          reason: '${tool.name} at ${least - 1}: no wider than its words',
        );
      }
    });
  }
}
