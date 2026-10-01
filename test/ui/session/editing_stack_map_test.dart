import 'dart:collection' show SplayTreeMap;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show isSyncedAttachedLayer;
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
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
      project: s,
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

  /// Every row the stack draws, folders walked through.
  List<CanvasStackRow> rowsIn(List<CompositeNode<CanvasStackRow>> nodes) => [
    for (final node in nodes)
      if (node is CompositeLeaf<CanvasStackRow>)
        node.payload
      else if (node is CompositeGroup<CanvasStackRow>)
        ...rowsIn(node.children),
  ];

  CanvasActiveLayerRow activeRowIn(List<CompositeNode<CanvasStackRow>> nodes) =>
      rowsIn(nodes).whereType<CanvasActiveLayerRow>().last;

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

  test('the active row names the SAME cel the image branch would have asked '
      'for', () {
    final s = sessionOnADressedRow();
    final cut = s.activeCutOrNull!;
    final (_, nodes) = stackOf(s);

    expect(
      activeRowIn(nodes).frameKey,
      s.brushFrameKeyForCut(cut, s.activeLayerId!, s.selectedFrame!.id),
      reason:
          'the build in which this cel leaves the active slot, the stack '
          'composes ITS image on the spot — a different key would compose '
          'someone else\'s and leave this row blank for a frame. (🪦Until '
          '2026-09-17 the same key served the opposite direction, the '
          'first-activation stand-in.)',
    );
  });

  test('a row you are NOT drawing on asks for its OWN cel', () {
    // 🧪Pinned when the audit's eighteenth family (2026-09-28) moved the
    // brush key onto the project role: a mutant that keyed the image
    // branch with another row's id survived every suite — only the active
    // arm's key was measured.
    final s = sessionOnADressedRow();
    final drawn = s.activeLayer!;
    final cel = s.selectedFrame!.id;
    s.layerStack.addLayer();
    expect(s.activeLayerId, isNot(drawn.id), reason: '⛔premise');
    final cut = s.activeCutOrNull!;
    final (_, nodes) = stackOf(s);

    expect(
      rowsIn(nodes).whereType<CanvasLayerImageRequest>().map((r) => r.frameKey),
      contains(s.brushFrameKeyForCut(cut, drawn.id, cel)),
    );
  });

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

  group('a drag that moves the brush\'s cel (canvas-follows-block-moves)', () {
    /// The stack of [shown] — the cut as a drag shows it — over [s]'s
    /// committed cut, with the active row placed as the canvas places it.
    (EditingStackMap, List<CompositeNode<CanvasStackRow>>) dragged(
      EditorSessionManager s,
      Cut shown, {
      int frameIndex = 0,
    }) {
      final map = EditingStackMap(
        opacityVerbs: s.opacityVerbs,
        project: s,
        cut: s.activeCutOrNull!,
        stackCut: shown,
        frameIndex: frameIndex,
        activeLayerId: s.activeLayerId,
      );
      return (
        map,
        map.mapTree(
          resolveCutFrameCompositeTree(
            cut: shown,
            frameIndex: frameIndex,
            liveLayerId: s.activeLayerId,
          ),
        ),
      );
    }

    /// The active row of [s] with its timeline replaced by [timeline].
    Cut withActiveTimeline(
      EditorSessionManager s,
      Map<int, TimelineExposure> timeline,
    ) {
      final cut = s.activeCutOrNull!;
      return cut.copyWith(
        layers: [
          for (final layer in cut.layers)
            if (layer.id == s.activeLayerId)
              layer.copyWith(timeline: SplayTreeMap.of(timeline))
            else
              layer,
        ],
      );
    }

    test('another cel under the playhead composites as an IMAGE, and the '
        'row still carries out its opacity and its keys', () {
      final s = sessionOnADressedRow();
      s.opacityVerbs.setLayerOpacity(layerId: s.activeLayer!.id, opacity: 0.5);
      final held = s.selectedFrame!.id;
      s.selectFrameIndex(2);
      s.createDrawingAtCurrentFrame();
      final other = s.selectedFrame!.id;
      s.selectFrameIndex(0);
      expect(s.selectedFrame!.id, held, reason: '⛔premise');

      final (map, nodes) = dragged(
        s,
        withActiveTimeline(s, {
          0: TimelineExposure.drawing(other, length: 1),
        }),
      );

      expect(rowsIn(nodes).whereType<CanvasActiveLayerRow>(), isEmpty);
      expect(
        rowsIn(nodes).whereType<CanvasLayerImageRequest>().map(
          (r) => r.frameKey,
        ),
        contains(
          s.brushFrameKeyForCut(s.activeCutOrNull!, s.activeLayerId!, other),
        ),
      );
      expect(map.activeLayerOpacity, closeTo(0.5, 1e-9));
      expect(
        map.activeSourceEffects.map((effect) => effect.kind),
        [EffectKind.deleteColor],
      );
    });

    test('the brush\'s own cel stays LIVE, wherever else the row moved', () {
      final s = sessionOnADressedRow();
      final held = s.selectedFrame!.id;

      final (_, nodes) = dragged(
        s,
        withActiveTimeline(s, {
          0: TimelineExposure.drawing(held, length: 3),
        }),
      );

      expect(activeRowIn(nodes).frameKey!.frameId, held);
    });

    test('nothing under the playhead draws NOTHING while the brush holds a '
        'cel — and the row still carries out its opacity', () {
      final s = sessionOnADressedRow();
      s.opacityVerbs.setLayerOpacity(layerId: s.activeLayer!.id, opacity: 0.5);
      final held = s.selectedFrame!.id;

      final (map, nodes) = dragged(
        s,
        withActiveTimeline(s, {
          4: TimelineExposure.drawing(held, length: 1),
        }),
      );

      expect(
        rowsIn(nodes).where(
          (row) =>
              row is CanvasActiveLayerRow ||
              (row is CanvasLayerImageRequest &&
                  row.frameKey.layerId == s.activeLayerId),
        ),
        isEmpty,
      );
      expect(map.activeLayerOpacity, closeTo(0.5, 1e-9));
    });

    test('a SYNCED attach row stands LIVE on its mirror cel — the cel the '
        'brush holds is read through the base, as the plan reads it', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      s.folders.addAttachedLayer(AttachedPlacement.above);
      expect(isSyncedAttachedLayer(s.activeLayer!), isTrue, reason: '⛔premise');
      final mirror = s.selectedFrame!.id;

      expect(
        rowsIn(
          s.editingCanvas.stack.nodes,
        ).whereType<CanvasActiveLayerRow>().single.frameKey!.frameId,
        mirror,
      );
    });

    test('with no cel held, nothing under the playhead is the EMPTY live row '
        '— where the first stroke lands', () {
      final s = sessionOnADressedRow();
      s.selectFrameIndex(1);
      expect(s.selectedFrame, isNull, reason: '⛔premise');

      final (_, nodes) = dragged(s, s.activeCutOrNull!, frameIndex: 1);

      expect(activeRowIn(nodes).frameKey, isNull);
    });
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
