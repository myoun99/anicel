import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editing_stack_map.dart';

/// THE ROW YOU ARE DRAWING ON COMPOSITES LIKE EVERY OTHER ROW.
///
/// [EditingStackMap] turns the shared composite tree into the editing
/// canvas's stack, and the ACTIVE row is the one leaf it builds by hand
/// instead of forwarding — which is exactly where fields go missing. Two
/// have already: the blend mode ("five fields arrived and four were
/// forwarded", so standing on a multiply row silently made it normal on
/// the editing canvas only) and the CPU-side source effects (#1280 — the
/// keyed colour came back the moment you stood on the row and went again
/// when you stepped off).
///
/// 🚨Built HERE, by its own name, rather than through
/// `session.editingCanvas.stack`. `tool/mutation_run.dart` chooses the
/// tests that will witness a mutation by asking which tests IMPORT the
/// file, and this collaborator was imported by none of them.
void main() {
  /// An effect of [kind] with one parameter moved off its default —
  /// `LayerEffect.defaults` alone resolves to nothing (`isNoOp`), which is
  /// the promise "adding an effect changes nothing until you touch a
  /// value" and would leave the chain empty here.
  LayerEffect effect(EffectKind kind, String parameterId, double value) =>
      LayerEffect(
        id: EffectId('fx-$parameterId'),
        kind: kind,
        parameters: {parameterId: EffectParameter(value: value)},
      );

  /// A session standing on an animation row that has one cel at frame 0,
  /// a MULTIPLY blend, and a colour key (a CPU/source-pixel effect).
  EditorSessionManager sessionOnADressedRow() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.layerSwitches.setLayerBlendMode(
      s.activeLayer!.id,
      LayerBlendMode.multiply,
    );
    s.effectsAndFx.updateLayerEffects(s.activeLayer!.id, [
      effect(EffectKind.deleteColor, 'amount', 100),
    ]);
    return s;
  }

  /// The stack [EditingStackMap] makes of the active cut at frame 0, with
  /// the active row arriving as a stored-pixel entry (`liveLayerId: null`)
  /// — the branch the canvas takes for a row that already has a cel here.
  (EditingStackMap, List<CompositeNode<CanvasStackRow>>) stackOf(
    EditorSessionManager s,
  ) {
    final cut = s.activeCutOrNull!;
    final map = EditingStackMap(
      opacityVerbs: s.opacityVerbs,
      internals: s,
      cut: cut,
      stackCut: cut,
      frameIndex: 0,
      activeLayerId: s.activeLayerId,
    );
    return (
      map,
      map.mapTree(resolveCutFrameCompositeTree(cut: cut, frameIndex: 0)),
    );
  }

  CanvasActiveLayerRow activeRowIn(List<CompositeNode<CanvasStackRow>> nodes) {
    CanvasActiveLayerRow? found;
    void walk(List<CompositeNode<CanvasStackRow>> list) {
      for (final node in list) {
        if (node is CompositeLeaf<CanvasStackRow>) {
          final payload = node.payload;
          if (payload is CanvasActiveLayerRow) {
            found = payload;
          }
        } else if (node is CompositeGroup<CanvasStackRow>) {
          walk(node.children);
        }
      }
    }

    walk(nodes);
    return found!;
  }

  test('the active row keeps the blend it composites with — the SAME field '
      'its cached twin carries', () {
    final s = sessionOnADressedRow();
    final (_, nodes) = stackOf(s);

    expect(
      activeRowIn(nodes).blendMode,
      LayerBlendMode.multiply,
      reason:
          'being the row you are drawing on is not a reason to '
          'composite differently — this arm dropped the field once and a '
          'multiply row read as normal on the editing canvas alone',
    );
  });

  // 🪦「the active row is the SAME cel the image branch would have asked
  // for」 stood here until 2026-09-17: the row carried its cel's key so the
  // stack could hold that cel's image as the first-activation stand-in.
  // Nothing stands in any more — the tiles picture themselves inside the
  // activation paint — and the field went with its one reader.

  test('the active row\'s CPU half is carried out with it — #1280', () {
    final s = sessionOnADressedRow();
    final (map, _) = stackOf(s);

    expect(
      map.activeSourceEffects.map((effect) => effect.kind),
      [EffectKind.deleteColor],
      reason:
          'the row you are DRAWING on is painted tile by tile by the '
          'brush panel\'s own painter, which never applies the colour '
          'keys — without this the keyed colour comes back when you stand '
          'on the row and goes when you step off',
    );
  });

  test('a PAINT-side effect is not carried out as a source one', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.effectsAndFx.updateLayerEffects(s.activeLayer!.id, [
      effect(EffectKind.blur, 'blurX', 8),
    ]);
    final (map, _) = stackOf(s);

    expect(
      map.activeSourceEffects,
      isEmpty,
      reason:
          'a blur folds into an ImageFilter — the split is the law, '
          'not "the chain is non-empty"',
    );
  });

  test('the active row carries its display opacity out with it', () {
    final s = sessionOnADressedRow();
    s.opacityVerbs.setLayerOpacity(layerId: s.activeLayer!.id, opacity: 0.25);
    final (map, _) = stackOf(s);

    expect(
      map.activeLayerOpacity,
      closeTo(0.25, 1e-9),
      reason:
          'the brush panel\'s own painter draws this row and reads '
          'THIS number — the walk is where the chain is already resolved, '
          'so asking a second time somewhere else is how the panel and '
          'the stack come to disagree',
    );
  });
}
