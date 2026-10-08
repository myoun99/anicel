import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_choice.dart';
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// I-69 (유저 2026-10-04): 「도형 그리는 도구 … 사각형,원형,직선. 그냥 새로운
/// 도구로 하자」 — the shape tool is a fourth verb on the shapes' own axis,
/// and the line is the first shape not every verb speaks.
///
/// 🚨What is pinned here is the SEAM that makes that safe: which shapes a
/// verb speaks is said in one place (`canvasToolShapes`), and everything
/// that lists, names, remembers or reads back a shape asks it — so a line
/// can be drawn and cannot be selected, cut or filled, by any door.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  group('the shapes a verb speaks', () {
    test('select, cut and fill speak every shape with an inside, and only '
        'those', () {
      final enclosing = [
        for (final shape in CanvasShapeKind.values)
          if (canvasShapeEncloses(shape)) shape,
      ];
      expect(enclosing, [
        CanvasShapeKind.rect,
        CanvasShapeKind.ellipse,
        CanvasShapeKind.lasso,
        CanvasShapeKind.polygon,
      ]);
      for (final verb in [
        CanvasTool.select,
        CanvasTool.cut,
        CanvasTool.fillShape,
      ]) {
        expect(canvasToolShapes(verb), enclosing, reason: '$verb');
      }
    });

    test('the shape tool speaks the three the card names', () {
      expect(canvasToolShapes(CanvasTool.shape), [
        CanvasShapeKind.rect,
        CanvasShapeKind.ellipse,
        CanvasShapeKind.line,
      ]);
    });

    test('the shape tool marks the cel and drags on the selection layer', () {
      expect(canvasToolDrawsShapes(CanvasTool.shape), isTrue);
      expect(canvasToolMarksCel(CanvasTool.shape), isTrue);
      expect(canvasToolSelects(CanvasTool.shape), isTrue);
      expect(canvasToolPaints(CanvasTool.shape), isFalse);
      expect(canvasToolRailGroup(CanvasTool.shape), CanvasTool.shape);
    });

    test('a tool that traces nothing speaks none', () {
      for (final tool in CanvasTool.values) {
        final traces =
            tool == CanvasTool.select ||
            tool == CanvasTool.cut ||
            tool == CanvasTool.fillShape ||
            tool == CanvasTool.shape;
        expect(canvasToolShapes(tool).isEmpty, !traces, reason: '$tool');
      }
    });
  });

  group('a tile sets the shape of its own verb', () {
    const state = BrushToolState.defaults;

    test('the shape tool takes a line, and is the tool in hand with it', () {
      final next = state.withShapeKind(
        CanvasShapeKind.line,
        forTool: CanvasTool.shape,
      );
      expect(next.tool, CanvasTool.shape);
      expect(next.drawShape, CanvasShapeKind.line);
      expect(next.activeShapeKind, CanvasShapeKind.line);
      expect(next.selectShape, state.selectShape, reason: 'each verb its own');
    });

    test('⛔a line is nothing to select, cut or fill: the state is left as '
        'it was', () {
      for (final verb in [
        CanvasTool.select,
        CanvasTool.cut,
        CanvasTool.fillShape,
      ]) {
        expect(
          state.withShapeKind(CanvasShapeKind.line, forTool: verb),
          same(state),
          reason: '$verb',
        );
      }
    });

    test('⛔nor is a lasso a shape the shape tool draws', () {
      expect(
        state.withShapeKind(CanvasShapeKind.lasso, forTool: CanvasTool.shape),
        same(state),
      );
    });
  });

  group('the shape tool\'s blend is its own', () {
    final inHand = BrushToolState.defaults.copyWith(
      tool: CanvasTool.shape,
      blendMode: BrushBlendMode.multiply,
      fillBlendMode: BrushBlendMode.screen,
    );

    test('it starts on the plain blend whatever the brush is on', () {
      expect(inHand.activeBlendMode, BrushBlendMode.color);
      expect(inHand.toInputSettings().blendMode, BrushBlendMode.color);
      expect(inHand.toInputSettings().erase, isFalse);
    });

    test('the strip writes it, and no other tool\'s', () {
      final next = inHand.withActiveBlendMode(BrushBlendMode.overlay);
      expect(next.shapeBlendMode, BrushBlendMode.overlay);
      expect(next.activeBlendMode, BrushBlendMode.overlay);
      expect(next.blendMode, BrushBlendMode.multiply, reason: 'the brush\'s');
      expect(next.fillBlendMode, BrushBlendMode.screen, reason: 'the fill\'s');
      expect(next.toInputSettings().blendMode, BrushBlendMode.overlay);
    });

    test('on erase its stroke erases', () {
      final erasing = inHand.withActiveBlendMode(BrushBlendMode.erase);
      expect(erasing.toInputSettings().erase, isTrue);
      expect(erasing.toInputSettings().blendMode, BrushBlendMode.erase);
    });

    test('the brush keeps its own blend under its own tool', () {
      final onTheBrush = inHand
          .withActiveBlendMode(BrushBlendMode.overlay)
          .copyWith(tool: CanvasTool.brush);
      expect(onTheBrush.activeBlendMode, BrushBlendMode.multiply);
    });
  });

  group('the two values are part of the state', () {
    const state = BrushToolState.defaults;

    test('a state that differs in either is another state', () {
      final shape = state.copyWith(drawShape: CanvasShapeKind.ellipse);
      final blend = state.copyWith(shapeBlendMode: BrushBlendMode.multiply);
      expect(shape, isNot(state));
      expect(blend, isNot(state));
      expect(shape.hashCode, isNot(state.hashCode));
      expect(blend.hashCode, isNot(state.hashCode));
    });

    test('a brush taken up does not put them back', () {
      final set = state.copyWith(
        drawShape: CanvasShapeKind.line,
        shapeBlendMode: BrushBlendMode.multiply,
      );
      final carried = set.carryingBrushOf(BrushToolState.defaults);
      expect(carried.drawShape, CanvasShapeKind.line);
      expect(carried.shapeBlendMode, BrushBlendMode.multiply);
    });
  });

  // 유저 2026-10-04: 「브러시로 선택된 펜? 브러시 상태를 그대로 사용해서
  // 도형그림 … 브러시 값 따르기 마련(사이즈나 불투명도나 전부다)」.
  group('the shape tool holds the BRUSH tool\'s brush', () {
    PaintToolStateNotifier onTheBrushAt30() {
      final notifier = PaintToolStateNotifier(
        BrushToolState.defaults.copyWith(size: 30),
      );
      addTearDown(notifier.dispose);
      return notifier;
    }

    void take(PaintToolStateNotifier notifier, CanvasTool tool) =>
        notifier.value = notifier.value.copyWith(tool: tool);

    test('whose brush each tool holds', () {
      expect(canvasToolBrushOwner(CanvasTool.brush), CanvasTool.brush);
      expect(canvasToolBrushOwner(CanvasTool.eraser), CanvasTool.eraser);
      expect(canvasToolBrushOwner(CanvasTool.shape), CanvasTool.brush);
      for (final tool in CanvasTool.values) {
        if (tool != CanvasTool.brush &&
            tool != CanvasTool.eraser &&
            tool != CanvasTool.shape) {
          expect(canvasToolBrushOwner(tool), isNull, reason: '$tool');
        }
      }
    });

    test('taken up from the eraser, it draws with the brush\'s tip and not '
        'the eraser\'s', () {
      final notifier = onTheBrushAt30();
      take(notifier, CanvasTool.eraser);
      notifier.value = notifier.value.copyWith(size: 80);

      take(notifier, CanvasTool.shape);

      expect(notifier.value.size, 30);
    });

    test('and through a tool that holds no brush of its own', () {
      final notifier = onTheBrushAt30();
      take(notifier, CanvasTool.eraser);
      notifier.value = notifier.value.copyWith(size: 80);
      take(notifier, CanvasTool.select);

      take(notifier, CanvasTool.shape);

      expect(notifier.value.size, 30);
    });

    test('a size set while it is in hand is the brush\'s size — and the '
        'eraser keeps its own', () {
      final notifier = onTheBrushAt30();
      take(notifier, CanvasTool.eraser);
      notifier.value = notifier.value.copyWith(size: 80);
      take(notifier, CanvasTool.shape);
      notifier.value = notifier.value.copyWith(size: 12);

      take(notifier, CanvasTool.brush);
      expect(notifier.value.size, 12, reason: 'one brush, set from either');

      take(notifier, CanvasTool.eraser);
      expect(notifier.value.size, 80);

      take(notifier, CanvasTool.shape);
      expect(notifier.value.size, 12);
    });
  });

  group('the tool choice', () {
    test('writes and reads back the shape tool\'s shape and blend', () {
      final json = const ToolChoice(
        drawShape: CanvasShapeKind.line,
        shapeBlendMode: BrushBlendMode.multiply,
      ).toJson();
      expect(json['drawShape'], 'line');
      expect(json['shapeBlendMode'], 'multiply');

      final back = ToolChoice.fromJson(json);
      expect(back.drawShape, CanvasShapeKind.line);
      expect(back.shapeBlendMode, BrushBlendMode.multiply);
    });

    test('⛔a shape written for a verb that does not speak it reads as '
        'absent, and the rest still lands', () {
      final choice = ToolChoice.fromJson(const {
        'selectShape': 'line',
        'cutShape': 'line',
        'fillShape': 'line',
        'drawShape': 'lasso',
        'shapeBlendMode': 'multiply',
      });
      expect(choice.selectShape, isNull);
      expect(choice.cutShape, isNull);
      expect(choice.fillShape, isNull);
      expect(choice.drawShape, isNull);
      expect(choice.shapeBlendMode, BrushBlendMode.multiply);
    });

    test('resuming puts back what the shape tool was left on', () {
      final left = PaintToolStateNotifier(
        BrushToolState.defaults.copyWith(
          drawShape: CanvasShapeKind.line,
          shapeBlendMode: BrushBlendMode.multiply,
        ),
      );
      addTearDown(left.dispose);
      final choice = ToolChoice.fromJson(toolChoiceOf(left).toJson());

      final resumed = PaintToolStateNotifier(BrushToolState.defaults);
      addTearDown(resumed.dispose);
      resumeToolChoice(resumed, choice, brushFor: (_, _, _) => null);

      expect(resumed.value.drawShape, CanvasShapeKind.line);
      expect(resumed.value.shapeBlendMode, BrushBlendMode.multiply);
    });

    test('a shape the verb speaks still reads', () {
      final choice = ToolChoice.fromJson(const {
        'selectShape': 'lasso',
        'drawShape': 'ellipse',
      });
      expect(choice.selectShape, CanvasShapeKind.lasso);
      expect(choice.drawShape, CanvasShapeKind.ellipse);
    });
  });

  group('the drag', () {
    MarqueeDrag drag(CanvasShapeKind kind, CanvasPoint from, CanvasPoint to) =>
        MarqueeDrag(pointer: 1, shapeKind: kind, before: null, at: from)
          ..update(to);

    test('a line is its two ends: no outline, an open path, and the trail '
        'the ants draw while it is dragged', () {
      final line = drag(CanvasShapeKind.line, p(10, 10), p(60, 40));
      expect(line.shape(), isNull, reason: 'nothing is enclosed');
      expect(line.path()!.points, [p(10, 10), p(60, 40)]);
      expect(line.path()!.closed, isFalse);
      expect(line.openTrail, [p(10, 10), p(60, 40)]);
    });

    test('the trail follows the hand, from the same start', () {
      final line = drag(CanvasShapeKind.line, p(10, 10), p(60, 40))
        ..update(p(20, 90));
      expect(line.openTrail, [p(10, 10), p(20, 90)]);
      expect(line.path()!.points, [p(10, 10), p(20, 90)]);
    });

    test('a line too short to have meant one is nothing', () {
      expect(drag(CanvasShapeKind.line, p(10, 10), p(11, 11)).path(), isNull);
      expect(
        drag(CanvasShapeKind.line, p(10, 10), p(10, 12)).path(),
        isNotNull,
        reason: 'two pixels one way is a line',
      );
    });

    test('a box shape\'s path is its outline, closed', () {
      for (final kind in [CanvasShapeKind.rect, CanvasShapeKind.ellipse]) {
        final box = drag(kind, p(10, 10), p(60, 40));
        expect(box.path()!.points, box.shape()!.points, reason: '$kind');
        expect(box.path()!.closed, isTrue, reason: '$kind');
        expect(box.openTrail, isEmpty, reason: '$kind');
      }
      expect(drag(CanvasShapeKind.rect, p(10, 10), p(11, 11)).path(), isNull);
    });
  });

  group('the names and the actions', () {
    test('a shape tile of the shape tool is named for what it does', () {
      String label(CanvasShapeKind shape, AppLanguage language) =>
          shapeTileLabel(CanvasTool.shape, shape, AppStrings.of(language));
      expect(label(CanvasShapeKind.line, AppLanguage.en), 'Draw Line');
      expect(label(CanvasShapeKind.rect, AppLanguage.ko), '사각형 그리기');
      expect(label(CanvasShapeKind.ellipse, AppLanguage.ja), '楕円描画');
    });

    test('the tool and its three tiles are actions, and a line is an action '
        'of no other tool', () {
      final ids = {
        for (final definition in editorActionDefinitions) definition.id,
      };
      expect(
        ids,
        containsAll([
          'tool-shape',
          'tool-shape-rect',
          'tool-shape-ellipse',
          'tool-shape-line',
        ]),
      );
      expect(
        [
          for (final id in ids)
            if (id.startsWith('tool-') && id.endsWith('-line')) id,
        ],
        ['tool-shape-line'],
      );
      expect(ids, isNot(contains('tool-shape-lasso')));
    });
  });
}
