import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_choice.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// I-69 — the shape tool's own settings, as 유저 answered them
/// (2026-10-08): Q1 「일반」 · Q5 「설정 스위치 + Shift」 · Q7 「새
/// 도형도구에서도 선/채움을 고르는 줄」 · Q8 「모서리: 각지게 | 둥글게」,
/// 「일반은 브러시랑 전혀 관계없는 독립적인것임」 · Q9 「채움은 타입과
/// 무관하다」.
///
/// What is pinned: the values are the TOOL'S (one value on the tool state,
/// saved with the tools), the strip's size and opacity are the tool's own
/// wherever it does not draw with the brush, and every row of its settings
/// is always there — one that means nothing keeps its place and loses its
/// tap.
void main() {
  BrushToolState shapeTool({
    CanvasShapeKind shape = CanvasShapeKind.rect,
    ShapeToolOptions options = const ShapeToolOptions(),
  }) => BrushToolState.defaults.copyWith(
    tool: CanvasTool.shape,
    drawShape: shape,
    shapeOptions: options,
  );

  const plain = ShapeToolOptions(type: ShapeLineType.plain);
  const fill = ShapeToolOptions(part: ShapePart.fill);

  group('the options', () {
    test('a tool nobody has set lays a line, with the brush, unlocked', () {
      const fresh = ShapeToolOptions();
      expect(fresh.part, ShapePart.line);
      expect(fresh.type, ShapeLineType.brush);
      expect(fresh.corners, ShapeCorners.sharp);
      expect(fresh.antiAlias, isTrue);
      expect(fresh.ratioLock, isFalse);
      expect(fresh.opacity, 1);
      expect(fresh.size, ShapeToolOptions.defaultSize);
    });

    test('are written and read back whole', () {
      const set = ShapeToolOptions(
        part: ShapePart.fill,
        type: ShapeLineType.plain,
        size: 12.5,
        opacity: 0.4,
        antiAlias: false,
        corners: ShapeCorners.round,
        ratioLock: true,
      );
      expect(ShapeToolOptions.fromJson(set.toJson()), set);
      expect(set, isNot(const ShapeToolOptions()));
      expect(set.hashCode, isNot(const ShapeToolOptions().hashCode));
    });

    test('each differs from the fresh ones by itself', () {
      const fresh = ShapeToolOptions();
      for (final other in [
        fresh.copyWith(part: ShapePart.fill),
        fresh.copyWith(type: ShapeLineType.plain),
        fresh.copyWith(size: 9),
        fresh.copyWith(opacity: 0.5),
        fresh.copyWith(antiAlias: false),
        fresh.copyWith(corners: ShapeCorners.round),
        fresh.copyWith(ratioLock: true),
      ]) {
        expect(other, isNot(fresh));
        expect(ShapeToolOptions.fromJson(other.toJson()), other);
      }
    });

    test('🚨every part answers for itself: one this build cannot read keeps '
        'its default, and the rest still lands', () {
      final read = ShapeToolOptions.fromJson({
        'part': 'hatching',
        'type': 'plain',
        'size': -3,
        'opacity': 7,
        'antiAlias': 'yes',
        'corners': 'round',
        'ratioLock': true,
      })!;
      expect(read.part, ShapePart.line, reason: 'a name nobody knows');
      expect(read.type, ShapeLineType.plain);
      expect(read.size, ShapeToolOptions.defaultSize, reason: 'no width');
      expect(read.opacity, 1, reason: 'out of range');
      expect(read.antiAlias, isTrue, reason: 'not a switch');
      expect(read.corners, ShapeCorners.round);
      expect(read.ratioLock, isTrue);
    });

    test('what is not a set of options at all reads as none', () {
      expect(ShapeToolOptions.fromJson(null), isNull);
      expect(ShapeToolOptions.fromJson('plain'), isNull);
    });
  });

  group('the tool state', () {
    test('holds them, and a state that differs in them is another state', () {
      final a = shapeTool();
      final b = shapeTool(options: plain);
      expect(a.shapeOptions, const ShapeToolOptions());
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(b.copyWith(tool: CanvasTool.brush).shapeOptions, plain);
    });

    test('every way a state is made carries them', () {
      expect(BrushToolState(shapeOptions: plain).shapeOptions, plain);
      expect(BrushToolState.clamped(shapeOptions: plain).shapeOptions, plain);
      expect(
        BrushToolState.fromShape(
          BrushToolState.defaults.shape,
          shapeOptions: plain,
        ).shapeOptions,
        plain,
      );
      // A value of the brush set through the state rebuilds it.
      expect(shapeTool(options: plain).copyWith(size: 30).shapeOptions, plain);
      expect(
        shapeTool(options: plain)
            .withMask(BrushMaskSlot.values.first, null)
            .shapeOptions,
        plain,
      );
    });

    test('🚨a line has no inside: under the line tile the tool lays the '
        'line whatever was chosen — and what was chosen keeps', () {
      final onTheLine = shapeTool(shape: CanvasShapeKind.line, options: fill);
      expect(onTheLine.shapePart, ShapePart.line);
      expect(onTheLine.shapeOptions.part, ShapePart.fill, reason: 'kept');

      final backOnTheRect = onTheLine.withShapeKind(
        CanvasShapeKind.rect,
        forTool: CanvasTool.shape,
      );
      expect(backOnTheRect.shapePart, ShapePart.fill);
      expect(shapeTool(options: fill).shapePart, ShapePart.fill);
      expect(
        shapeTool(shape: CanvasShapeKind.ellipse, options: fill).shapePart,
        ShapePart.fill,
      );
    });

    test('it draws with the brush only where it lays a line of the brush '
        'type', () {
      expect(shapeTool().shapeDrawsWithTheBrush, isTrue);
      expect(shapeTool(options: plain).shapeDrawsWithTheBrush, isFalse);
      expect(shapeTool(options: fill).shapeDrawsWithTheBrush, isFalse);
      expect(
        shapeTool(
          shape: CanvasShapeKind.line,
          options: fill,
        ).shapeDrawsWithTheBrush,
        isTrue,
        reason: 'under the line tile the fill is a line, of the brush type',
      );
    });
  });

  // 유저 (TP1): 「툴마다 기억하게해서 … 거기서 브러시툴로 바꾼다고해서 필 툴의
  // 불투명도 남는다거나 없게」 — the same law, for the shape tool's own.
  group('the strip\'s size and opacity are the active tool\'s', () {
    final brush = BrushToolState.defaults.copyWith(size: 40, opacity: 0.8);

    test('a line of the brush type: the brush\'s', () {
      final tool = brush.copyWith(tool: CanvasTool.shape);
      expect(tool.activeSize, 40);
      expect(tool.activeOpacity, 0.8);

      final set = tool.withActiveSize(55).withActiveOpacity(0.3);
      expect(set.size, 55);
      expect(set.opacity, 0.3);
      expect(set.shapeOptions, const ShapeToolOptions(), reason: 'untouched');
    });

    test('🚨a plain line: the tool\'s own — the brush\'s are not read, and '
        'not written', () {
      final tool = brush.copyWith(
        tool: CanvasTool.shape,
        shapeOptions: plain.copyWith(size: 6, opacity: 0.5),
      );
      expect(tool.activeSize, 6);
      expect(tool.activeOpacity, 0.5);

      final set = tool.withActiveSize(9).withActiveOpacity(0.25);
      expect(set.shapeOptions.size, 9);
      expect(set.shapeOptions.opacity, 0.25);
      expect(set.size, 40, reason: 'the brush keeps its size');
      expect(set.opacity, 0.8, reason: 'and its opacity');
    });

    test('a fill: the tool\'s own opacity', () {
      final tool = brush.copyWith(
        tool: CanvasTool.shape,
        shapeOptions: fill.copyWith(opacity: 0.6),
      );
      expect(tool.activeOpacity, 0.6);
      expect(tool.withActiveOpacity(0.1).shapeOptions.opacity, 0.1);
      expect(tool.withActiveOpacity(0.1).opacity, 0.8);
    });

    test('what is set is held to the range the strip has', () {
      final tool = shapeTool(options: plain);
      expect(
        tool.withActiveSize(-5).shapeOptions.size,
        BrushToolState.clampSize(-5),
      );
      expect(
        tool.withActiveSize(1e9).shapeOptions.size,
        BrushToolState.clampSize(1e9),
      );
      expect(tool.withActiveOpacity(3).shapeOptions.opacity, 1);
    });

    test('another tool in hand: the shape tool\'s own are nobody\'s', () {
      final tool = brush.copyWith(
        shapeOptions: plain.copyWith(size: 6, opacity: 0.5),
      );
      expect(tool.tool, CanvasTool.brush, reason: '⛔premise');
      expect(tool.activeSize, 40);
      expect(tool.activeOpacity, 0.8);
      expect(tool.withActiveSize(12).shapeOptions.size, 6);
    });

    test('what the strip offers: a fill has no width, and no tool of this '
        'kind reads the pen\'s pressure', () {
      for (final tool in [
        shapeTool(),
        shapeTool(options: plain),
        shapeTool(options: fill),
      ]) {
        expect(tool.supports(ToolParameter.blend), isTrue);
        expect(tool.supports(ToolParameter.opacity), isTrue);
        expect(tool.supports(ToolParameter.pressure), isFalse);
      }
      expect(shapeTool().supports(ToolParameter.size), isTrue);
      expect(shapeTool(options: plain).supports(ToolParameter.size), isTrue);
      expect(shapeTool(options: fill).supports(ToolParameter.size), isFalse);
      expect(
        shapeTool(
          shape: CanvasShapeKind.line,
          options: fill,
        ).supports(ToolParameter.size),
        isTrue,
        reason: 'under the line tile it is a line',
      );
    });
  });

  group('the tool choice', () {
    test('writes and reads back the shape tool\'s options', () {
      final tools = PaintToolStateNotifier(
        shapeTool(options: plain.copyWith(corners: ShapeCorners.round)),
      );
      addTearDown(tools.dispose);

      final read = ToolChoice.fromJson(toolChoiceOf(tools).toJson());
      expect(read.shapeOptions, plain.copyWith(corners: ShapeCorners.round));
    });

    test('a file that says nothing of them reads none, and resuming it '
        'leaves what the tool holds', () {
      expect(ToolChoice.fromJson(const {}).shapeOptions, isNull);

      final tools = PaintToolStateNotifier(shapeTool(options: plain));
      addTearDown(tools.dispose);
      resumeToolChoice(
        tools,
        const ToolChoice(),
        brushFor: (from, tool, preset) => null,
      );
      expect(tools.value.shapeOptions, plain);
    });

    test('resuming puts back what the tool was left on', () {
      final tools = PaintToolStateNotifier(shapeTool());
      addTearDown(tools.dispose);
      resumeToolChoice(
        tools,
        const ToolChoice(shapeOptions: fill),
        brushFor: (from, tool, preset) => null,
      );
      expect(tools.value.shapeOptions, fill);
    });
  });

  group('the settings', () {
    Future<ValueNotifier<BrushToolState>> pump(
      WidgetTester tester,
      BrushToolState state,
    ) async {
      final tools = ValueNotifier<BrushToolState>(state);
      addTearDown(tools.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<BrushToolState>(
              valueListenable: tools,
              builder: (context, state, _) => ToolSettingsPanel(
                state: state,
                onChanged: (next) => tools.value = next,
                fillOptions: const FloodFillOptions(),
                onFillOptionsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      return tools;
    }

    Pill pill(WidgetTester tester, String key) =>
        tester.widget<Pill>(find.byKey(ValueKey<String>('shape-tool-$key')));

    SettingsSwitchRow row(WidgetTester tester, String key) =>
        tester.widget<SettingsSwitchRow>(
          find.byWidgetPredicate(
            (widget) =>
                widget is SettingsSwitchRow &&
                widget.tileKey == ValueKey<String>('shape-tool-$key-switch'),
          ),
        );

    const pills = [
      'part-line',
      'part-fill',
      'type-brush',
      'type-plain',
      'corners-sharp',
      'corners-round',
    ];

    testWidgets('🚨every row is there whatever is chosen', (tester) async {
      for (final state in [
        shapeTool(),
        shapeTool(options: plain),
        shapeTool(options: fill),
        shapeTool(shape: CanvasShapeKind.line),
      ]) {
        await pump(tester, state);
        for (final key in pills) {
          expect(
            find.byKey(ValueKey<String>('shape-tool-$key')),
            findsOneWidget,
            reason: '$key under ${state.shapeOptions.toJson()}',
          );
        }
        expect(row(tester, 'anti-alias'), isNotNull);
        expect(row(tester, 'ratio-lock'), isNotNull);
      }
    });

    testWidgets('a line of the brush type: the type is to choose; the '
        'corners and the edge are the plain line\'s, and off', (tester) async {
      await pump(tester, shapeTool());

      expect(pill(tester, 'part-line').selected, isTrue);
      expect(pill(tester, 'type-brush').selected, isTrue);
      expect(pill(tester, 'type-plain').onTap, isNotNull);
      expect(pill(tester, 'corners-sharp').onTap, isNull);
      expect(pill(tester, 'corners-round').onTap, isNull);
      expect(row(tester, 'anti-alias').onChanged, isNull);
      expect(row(tester, 'ratio-lock').onChanged, isNotNull);
    });

    testWidgets('「일반」 is chosen by its pill, and then its corners and its '
        'edge are to set', (tester) async {
      final tools = await pump(tester, shapeTool());

      await tester.tap(find.byKey(const ValueKey('shape-tool-type-plain')));
      await tester.pump();
      expect(tools.value.shapeOptions.type, ShapeLineType.plain);
      expect(pill(tester, 'type-plain').selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('shape-tool-corners-round')));
      await tester.pump();
      expect(tools.value.shapeOptions.corners, ShapeCorners.round);
      expect(pill(tester, 'corners-round').selected, isTrue);

      expect(row(tester, 'anti-alias').value, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('shape-tool-anti-alias-switch')),
      );
      await tester.pump();
      expect(tools.value.shapeOptions.antiAlias, isFalse);
      expect(row(tester, 'anti-alias').value, isFalse);
    });

    testWidgets('🚨「채움」 has no line: the type and the corners keep their '
        'place and lose their tap — the edge is the fill\'s to set', (
      tester,
    ) async {
      final tools = await pump(tester, shapeTool(options: plain));

      await tester.tap(find.byKey(const ValueKey('shape-tool-part-fill')));
      await tester.pump();
      expect(tools.value.shapeOptions.part, ShapePart.fill);
      expect(pill(tester, 'part-fill').selected, isTrue);
      for (final key in [
        'type-brush',
        'type-plain',
        'corners-sharp',
        'corners-round',
      ]) {
        expect(pill(tester, key).onTap, isNull, reason: key);
      }
      expect(
        tools.value.shapeOptions.type,
        ShapeLineType.plain,
        reason: 'what the line was is kept for when it is a line again',
      );
      expect(row(tester, 'anti-alias').onChanged, isNotNull);

      await tester.tap(find.byKey(const ValueKey('shape-tool-part-line')));
      await tester.pump();
      expect(tools.value.shapeOptions.part, ShapePart.line);
      expect(pill(tester, 'type-plain').onTap, isNotNull);
    });

    testWidgets('🚨under the line tile 「채움」 takes no press, and the line is '
        'what is lit — whatever was chosen for the other shapes', (
      tester,
    ) async {
      final tools = await pump(
        tester,
        shapeTool(shape: CanvasShapeKind.line, options: fill),
      );

      expect(pill(tester, 'part-fill').onTap, isNull);
      expect(pill(tester, 'part-fill').selected, isFalse);
      expect(pill(tester, 'part-line').selected, isTrue);
      expect(pill(tester, 'type-plain').onTap, isNotNull, reason: 'a line');

      await tester.tap(
        find.byKey(const ValueKey('shape-tool-part-fill')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tools.value.shapeOptions.part, ShapePart.fill, reason: 'kept');
    });

    testWidgets('the ratio lock is a switch, whatever is chosen', (
      tester,
    ) async {
      for (final state in [shapeTool(), shapeTool(options: fill)]) {
        final tools = await pump(tester, state);
        expect(row(tester, 'ratio-lock').value, isFalse);

        await tester.tap(
          find.byKey(const ValueKey('shape-tool-ratio-lock-switch')),
        );
        await tester.pump();
        expect(tools.value.shapeOptions.ratioLock, isTrue);
        expect(row(tester, 'ratio-lock').value, isTrue);
      }
    });
  });
}
