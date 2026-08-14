import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_shape.dart' show BrushMaskSlot;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

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

    // TP2: the whole table, spelled out by hand — which is what makes it a
    // contract. A tool added later lands here as a row of falses and has to
    // be argued into each column.
    test('every tool declares which strip parameters it honours', () {
      const table = <CanvasTool, Set<ToolParameter>>{
        CanvasTool.brush: {...ToolParameter.values},
        CanvasTool.eraser: {...ToolParameter.values},
        // The fills and the stamp composite and take an opacity; their AREA
        // comes from the flood, the drawn outline or the held piece, never
        // from the tip width, and one tap is not a stroke.
        CanvasTool.fill: {ToolParameter.blend, ToolParameter.opacity},
        CanvasTool.fillShape: {ToolParameter.blend, ToolParameter.opacity},
        CanvasTool.cutStamp: {ToolParameter.blend, ToolParameter.opacity},
        CanvasTool.cut: {},
        CanvasTool.select: {},
        CanvasTool.move: {},
        CanvasTool.guide: {},
        CanvasTool.eyedropper: {},
      };
      expect(
        table.keys.toSet(),
        CanvasTool.values.toSet(),
        reason: 'a new tool must answer this table',
      );
      for (final entry in table.entries) {
        final state = BrushToolState.defaults.copyWith(tool: entry.key);
        for (final parameter in ToolParameter.values) {
          expect(
            state.supports(parameter),
            entry.value.contains(parameter),
            reason: '${entry.key} / $parameter',
          );
        }
        expect(
          state.toolHasBlendMode,
          entry.value.contains(ToolParameter.blend),
          reason: 'the blend getter reads the same table (${entry.key})',
        );
      }
    });

    // The rail's group table, by hand for the same reason as the one above:
    // a tool added later has to declare which BUTTON it answers to instead
    // of quietly becoming a button of its own.
    test('every tool declares which rail button it lives under', () {
      const groups = <CanvasTool, CanvasTool>{
        CanvasTool.brush: CanvasTool.brush,
        CanvasTool.eraser: CanvasTool.eraser,
        CanvasTool.eyedropper: CanvasTool.eyedropper,
        // The two groups with more than one tile.
        CanvasTool.fill: CanvasTool.fill,
        CanvasTool.fillShape: CanvasTool.fill,
        CanvasTool.cut: CanvasTool.cut,
        CanvasTool.cutStamp: CanvasTool.cut,
        CanvasTool.guide: CanvasTool.guide,
        CanvasTool.select: CanvasTool.select,
        CanvasTool.move: CanvasTool.move,
      };
      expect(
        groups.keys.toSet(),
        CanvasTool.values.toSet(),
        reason: 'a new tool must answer this table',
      );
      for (final entry in groups.entries) {
        expect(
          canvasToolRailGroup(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
      for (final tool in CanvasTool.values) {
        final group = canvasToolRailGroup(tool);
        expect(
          canvasToolRailGroup(group),
          group,
          reason: 'a group is named by one of its own members ($tool)',
        );
        // The predicates that LIGHT the two shared buttons have to agree
        // with the table that RE-ENTERS them, or a tile could highlight one
        // button and be restored by another.
        expect(
          canvasToolFills(tool),
          group == CanvasTool.fill,
          reason: '$tool',
        );
        expect(
          canvasToolUsesCutPiece(tool),
          group == CanvasTool.cut,
          reason: '$tool',
        );
      }
    });

    test('TP1: opacity is remembered per tool, and the fills share one', () {
      // 유저: "필 툴도 불투명도 설정하면 그거대로 채워지게. 그렇다고 거기서
      // 브러시툴로 바꾼다고해서 필 툴의 불투명도 남는다거나."
      final state = BrushToolState.defaults
          .copyWith(tool: CanvasTool.brush)
          .withActiveOpacity(0.4)
          .copyWith(tool: CanvasTool.fill)
          .withActiveOpacity(0.8)
          .copyWith(tool: CanvasTool.cutStamp)
          .withActiveOpacity(0.25);

      expect(state.activeOpacity, 0.25);
      expect(
        state.copyWith(tool: CanvasTool.brush).activeOpacity,
        0.4,
        reason: 'the brush kept its own',
      );
      expect(
        state.copyWith(tool: CanvasTool.fill).activeOpacity,
        0.8,
        reason: 'and the fill kept its own',
      );
      expect(
        state.copyWith(tool: CanvasTool.fillShape).activeOpacity,
        0.8,
        reason: 'both fill tiles are one tool — same law as their blend',
      );
      expect(
        state.opacity,
        0.4,
        reason: "the brush's opacity is still the shape's, so presets carry it",
      );
    });

    test('the stamp keeps its own blend, and its own pin', () {
      // Sharing the brush's field would mean painting shadows on multiply
      // and then dropping a stamp on multiply — the leak the fill's own
      // field was split off to stop, one tool over.
      final stamp = BrushToolState.defaults
          .copyWith(tool: CanvasTool.cutStamp)
          .withActiveBlendMode(BrushBlendMode.behind);
      expect(stamp.activeBlendMode, BrushBlendMode.behind);
      expect(
        stamp.copyWith(tool: CanvasTool.brush).activeBlendMode,
        BrushBlendMode.color,
        reason: 'the brush never hears about it',
      );

      final pinned = stamp.withActiveBlendLock(BrushBlendMode.multiply);
      expect(pinned.activeBlendLock, BrushBlendMode.multiply);
      expect(pinned.activeBlendMode, BrushBlendMode.multiply, reason: '핀 > 툴 값');
      expect(
        pinned.copyWith(tool: CanvasTool.brush).activeBlendLock,
        isNull,
        reason: "the brush's pin lives in its preset and stays free",
      );
      expect(
        pinned.withActiveBlendLock(null).activeBlendMode,
        BrushBlendMode.behind,
        reason: 'unpinning falls back to the mode the tool was set to',
      );
    });

    test('picking a tip keeps every hand setting', () {
      // `withMask` rebuilds the state through the raw constructor, which
      // DEFAULTS whatever it is not handed — so this used to snap the three
      // remembered outlines back to the rectangle and both blends back to
      // Color every time a tip was chosen.
      final before = BrushToolState.defaults
          .withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.select)
          .withShapeKind(CanvasShapeKind.polygon, forTool: CanvasTool.cut)
          .copyWith(tool: CanvasTool.fill)
          .withActiveBlendMode(BrushBlendMode.multiply)
          .copyWith(tool: CanvasTool.cutStamp)
          .withActiveBlendMode(BrushBlendMode.behind);
      final after = before.withMask(BrushMaskSlot.tip, null);
      expect(after.selectShape, CanvasShapeKind.lasso);
      expect(after.cutShape, CanvasShapeKind.polygon);
      expect(after.fillBlendMode, BrushBlendMode.multiply);
      expect(after.cutStampBlendMode, BrushBlendMode.behind);
      expect(after.tool, CanvasTool.cutStamp);
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

    testWidgets('the transform tool lists 일반/퍼스/메쉬 and picking one '
        'writes the MODE, not the tool', (tester) async {
      final options = ValueNotifier(TransformToolOptions.defaults);
      addTearDown(options.dispose);
      final switched = <CanvasTool>[];
      await tester.pumpWidget(
        app(
          ToolLibraryPanel(
            tool: CanvasTool.move,
            onToolChanged: switched.add,
            brushLibrary: const SizedBox.shrink(),
            transformOptions: options,
            onTransformOptionsChanged: (value) => options.value = value,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-transform-normal')),
        findsOneWidget,
      );

      // The mesh's only entrance. It used to be a button in Tool Settings
      // that needed no selection to work; the tile inherits that — nothing
      // here knows or cares whether anything is selected.
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-transform-mesh')),
      );
      await tester.pump();
      expect(options.value.mode, TransformMode.mesh);
      expect(
        switched,
        isEmpty,
        reason:
            'a mode is a setting — routing it through onToolChanged would '
            'confirm the open box on the way past',
      );
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
