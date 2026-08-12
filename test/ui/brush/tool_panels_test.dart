import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';

/// R11-④: the Tool Library / Tool Settings panels follow the active tool.
void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ToolLibraryPanel', () {
    testWidgets('painting tools show the brush library', (tester) async {
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.eraser,
            onToolChanged: (_) {},
            brushLibrary: const Text('library-content'),
          ),
        ),
      );
      expect(find.text('library-content'), findsOneWidget);
    });

    testWidgets('the select tool lists its shapes and picks one on tap', (
      tester,
    ) async {
      final switched = <(CanvasTool, CanvasShapeKind)>[];
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.select,
            onToolChanged: (_) {},
            onShapeKindChanged: (verb, kind) => switched.add((verb, kind)),
            brushLibrary: const SizedBox.shrink(),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-select-rect')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-select-lasso')),
      );
      expect(switched, [(CanvasTool.select, CanvasShapeKind.lasso)]);
    });

    testWidgets('every shape gets a tile under every drag-out verb', (
      tester,
    ) async {
      // The point of the shared vocabulary: adding a CanvasShapeKind must
      // not need a hand-written tile per verb. If this fails after a shape
      // is added, some verb was left behind.
      for (final (verb, prefix) in const [
        (CanvasTool.select, 'sub-tool-select'),
        (CanvasTool.cut, 'sub-tool-cut'),
      ]) {
        await tester.pumpWidget(
          app(
            ToolLibraryPanel(
              tool: verb,
              onToolChanged: (_) {},
              onShapeKindChanged: (_, _) {},
              brushLibrary: const SizedBox.shrink(),
            ),
          ),
        );
        for (final kind in CanvasShapeKind.values) {
          expect(
            find.byKey(ValueKey<String>('$prefix-${kind.name}')),
            findsOneWidget,
            reason: '$verb / $kind',
          );
        }
      }
    });
  });

  group('the fill tool lists a bucket and the shapes', () {
    testWidgets('both fill tiles show the same list', (tester) async {
      for (final verb in [CanvasTool.fill, CanvasTool.fillShape]) {
        await tester.pumpWidget(
          app(
            ToolLibraryPanel(
              tool: verb,
              onToolChanged: (_) {},
              onShapeKindChanged: (_, _) {},
              brushLibrary: const SizedBox.shrink(),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('sub-tool-fill-bucket')),
          findsOneWidget,
          reason: '$verb',
        );
        for (final kind in CanvasShapeKind.values) {
          expect(
            find.byKey(ValueKey<String>('sub-tool-fill-${kind.name}')),
            findsOneWidget,
            reason: '$verb / $kind',
          );
        }
      }
    });

    testWidgets('a fill shape tile enters the shape-fill verb', (tester) async {
      final picked = <(CanvasTool, CanvasShapeKind)>[];
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.fill,
            onToolChanged: (_) {},
            onShapeKindChanged: (verb, kind) => picked.add((verb, kind)),
            brushLibrary: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-fill-ellipse')),
      );
      expect(picked, [(CanvasTool.fillShape, CanvasShapeKind.ellipse)]);
    });

    testWidgets('the shape tile settings drop the knobs that read the '
        'picture', (tester) async {
      // 유저 확정 ⑥: 타일별 패널, 해당하는 설정이 보이도록. Tolerance and
      // gap close are questions about where a flood may go, and a drawn
      // outline never asks one.
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(
              tool: CanvasTool.fillShape,
            ),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('tool-settings-fill-shape')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('fill-tolerance-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('fill-gap-close-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('fill-shape-anti-alias-switch')),
        findsOneWidget,
        reason: 'the edge IS shared — both tiles end in a coverage mask',
      );
    });
  });

  group('blend modes live on the tool (유저 확정)', () {
    test('the fill and the brush keep separate blends', () {
      // Otherwise painting shadows on multiply and then reaching for the
      // bucket fills on multiply too — a setting arriving from another
      // tool unannounced.
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.brush)
          .withActiveBlendMode(BrushBlendMode.multiply)
          .copyWith(tool: CanvasTool.fill)
          .withActiveBlendMode(BrushBlendMode.behind);
      expect(state.brushBlendMode, BrushBlendMode.multiply);
      expect(state.fillBlendMode, BrushBlendMode.behind);
      expect(state.activeBlendMode, BrushBlendMode.behind);
      expect(
        state.copyWith(tool: CanvasTool.brush).activeBlendMode,
        BrushBlendMode.multiply,
      );
    });

    test('both fill tiles share one blend', () {
      // 유저 확정: 채우기 툴 하나로 공유 — the bucket and the shapes are one
      // tool wearing two ways of choosing an area.
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.fillShape)
          .withActiveBlendMode(BrushBlendMode.behind);
      expect(
        state.copyWith(tool: CanvasTool.fill).activeBlendMode,
        BrushBlendMode.behind,
      );
    });

    test('a pin wins over the tool value, and each tool pins its own', () {
      // 유저: 잠금이 있는 거는 그거 따라가고 없으면 마지막에 선택한 블렌드.
      final fill = BrushToolState.defaults
          .copyWith(tool: CanvasTool.fill)
          .withActiveBlendMode(BrushBlendMode.behind)
          .withActiveBlendLock(BrushBlendMode.multiply);
      expect(fill.activeBlendMode, BrushBlendMode.multiply);
      expect(fill.fillBlendMode, BrushBlendMode.behind, reason: 'still there');
      expect(
        fill.withActiveBlendLock(null).activeBlendMode,
        BrushBlendMode.behind,
        reason: 'unlocking falls back to the tool value',
      );
      // The brush pins through its PRESET, where a brush's pin belongs.
      final brush = fill.copyWith(tool: CanvasTool.brush);
      expect(brush.activeBlendLock, isNull, reason: 'the fill pin is not its');
    });

    test('the eraser IS the erase blend and outranks everything', () {
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.eraser)
          .copyWith(brushBlendMode: BrushBlendMode.multiply);
      expect(state.activeBlendMode, BrushBlendMode.erase);
      expect(state.toInputSettings().erase, isTrue);
    });

    test('the fill carries its blend into the commit', () {
      // The regression this whole thread exists to prevent: the fill used
      // to hardcode srcOver and ignore the control the strip was showing.
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.fill)
          .withActiveBlendMode(BrushBlendMode.behind);
      expect(state.toInputSettings().blendMode, BrushBlendMode.behind);
      final erasing = state.withActiveBlendMode(BrushBlendMode.erase);
      expect(erasing.toInputSettings().erase, isTrue, reason: '도형 지우기');
    });

    test('tools that composite nothing get no blend control', () {
      for (final tool in CanvasTool.values) {
        expect(
          BrushToolState.defaults.copyWith(tool: tool).toolHasBlendMode,
          tool == CanvasTool.brush ||
              tool == CanvasTool.eraser ||
              tool == CanvasTool.fill ||
              tool == CanvasTool.fillShape,
          reason: '$tool',
        );
      }
    });
  });

  group('the polygon confirm button', () {
    const buttonKey = ValueKey<String>('selection-close-polygon-button');

    Future<void> pumpSettings(
      WidgetTester tester, {
      required CanvasShapeKind shape,
      required int points,
      CanvasSelectionCommands? commands,
    }) async {
      final channel = commands ?? CanvasSelectionCommands();
      for (var i = 0; i < points; i += 1) {
        channel.addPolygonPoint(CanvasPoint(x: i * 10, y: i * 10));
      }
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults.withShapeKind(
              shape,
              forTool: CanvasTool.select,
            ),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
            selectionCommands: channel,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('is absent for the shapes that have no trace to close', (
      tester,
    ) async {
      // Every shape but the polygon finishes on the release of one drag,
      // so a confirm there would be a permanently dead row.
      for (final shape in const [
        CanvasShapeKind.rect,
        CanvasShapeKind.ellipse,
        CanvasShapeKind.lasso,
      ]) {
        await pumpSettings(tester, shape: shape, points: 0);
        expect(find.byKey(buttonKey), findsNothing, reason: '$shape');
      }
    });

    testWidgets('is dead until three vertices are down', (tester) async {
      await pumpSettings(
        tester,
        shape: CanvasShapeKind.polygon,
        points: 2,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
    });

    testWidgets('closes the trace when pressed', (tester) async {
      final commands = CanvasSelectionCommands();
      await pumpSettings(
        tester,
        shape: CanvasShapeKind.polygon,
        points: 3,
        commands: commands,
      );
      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      expect(commands.hasOpenPolygon, isFalse);
    });
  });

  group('shape memory (유저 확정: 도형은 동사별로 기억)', () {
    test('picking a shape for one verb leaves the other verb alone', () {
      final state = BrushToolState.defaults
          .withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.select)
          .withShapeKind(CanvasShapeKind.rect, forTool: CanvasTool.cut);
      expect(state.selectShape, CanvasShapeKind.lasso);
      expect(state.cutShape, CanvasShapeKind.rect);
    });

    test('a shape tile also enters its verb', () {
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.cutStamp)
          .withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.cut);
      expect(state.tool, CanvasTool.cut);
      expect(state.cutShape, CanvasShapeKind.lasso);
    });

    test('leaving the tool and coming back restores the outline', () {
      // What the rail's single Select button used to need a remembered
      // variant for: the memory is the state now, so a round trip through
      // another tool cannot lose it.
      final armed = BrushToolState.defaults.withShapeKind(
        CanvasShapeKind.lasso,
        forTool: CanvasTool.select,
      );
      final roundTrip = armed
          .copyWith(tool: CanvasTool.brush)
          .copyWith(tool: CanvasTool.select);
      expect(roundTrip.activeShapeKind, CanvasShapeKind.lasso);
    });

    test('applying a brush preset does not reset the outlines', () {
      // A preset is a brush; which outline the select and cut tools drag is
      // not part of one.
      final armed = BrushToolState.defaults
          .withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.select)
          .withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.cut);
      final applied = armed.withPresetSettings(
        BrushToolState.defaults.toBrushSettings(),
        tool: CanvasTool.brush,
      );
      expect(applied.selectShape, CanvasShapeKind.lasso);
      expect(applied.cutShape, CanvasShapeKind.lasso);
    });

    test('verbs that trace nothing store no outline', () {
      final state = BrushToolState.defaults.withShapeKind(
        CanvasShapeKind.lasso,
        forTool: CanvasTool.move,
      );
      expect(state, BrushToolState.defaults);
      expect(state.activeShapeKind, isNull);
    });

    test('the outline is part of state identity', () {
      // Otherwise a listener can skip the rebuild that repaints the tiles.
      final rect = BrushToolState.defaults.withShapeKind(
        CanvasShapeKind.rect,
        forTool: CanvasTool.select,
      );
      final lasso = BrushToolState.defaults.withShapeKind(
        CanvasShapeKind.lasso,
        forTool: CanvasTool.select,
      );
      expect(rect == lasso, isFalse);
      expect(rect.hashCode == lasso.hashCode, isFalse);
    });
  });

  group('ToolSettingsPanel', () {
    testWidgets('fill shows the flood knobs and reports edits', (tester) async {
      final changes = <FloodFillOptions>[];
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: changes.add,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('fill-tolerance-slider')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('fill-anti-alias-switch')),
      );
      await tester.pump();
      expect(changes, hasLength(1));
      expect(changes.single.antiAlias, isFalse);
      expect(changes.single.tolerance, 32, reason: 'other knobs untouched');
    });

    testWidgets('painting tools keep the brush settings panel', (tester) async {
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults,
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
          ),
        ),
      );
      // Size left for the top strip, so the signature control is now the
      // first knob a preset DOES carry and a hand does not reach for
      // mid-stroke.
      expect(
        find.byKey(const ValueKey<String>('brush-tool-flow-slider')),
        findsOneWidget,
      );
    });
  });
}
