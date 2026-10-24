import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★A FRAME'S ONE PICTURE IS KEYED BY THE TREE THE SCREEN STACKS FOR
/// IT (one-picture-per-frame ②-1): [framePictureKeyOf]. The picture store
/// is content-addressed — two stacks that draw two pictures under one key
/// are ONE picture, the wrong one on one of the screens — so every input
/// the drawing reads parts the key, and nothing else does: the canvas
/// standing on a frame and a run playing it ask one picture.
void main() {
  BrushFrameKey cel(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  const page = (
    canvasSize: CanvasSize(width: 24, height: 16),
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: ProjectBackground.defaultBackground,
  );

  /// A row under a translucent folder over another — built anew on every
  /// call, so a key equal to another's is equal by value.
  List<CompositeNode<CanvasStackRow>> stack({
    double opacity = 1.0,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    LayerPlacement? placement,
    List<ResolvedLayerEffect> effects = const [],
    double folderOpacity = 0.5,
    bool overTurned = false,
  }) {
    final below = CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: cel('below'), opacity: 1.0),
    );
    final folder = CompositeGroup<CanvasStackRow>(
      children: [
        CompositeLeaf(
          CanvasLayerImageRequest(
            frameKey: cel('inside'),
            opacity: opacity,
            blendMode: blendMode,
            placement: placement,
            effects: effects,
          ),
        ),
      ],
      opacity: folderOpacity,
      blendMode: LayerBlendMode.normal,
      effects: const [],
    );
    return overTurned ? [folder, below] : [below, folder];
  }

  FramePictureKey keyOf(
    List<CompositeNode<CanvasStackRow>> nodes, {
    CutId cutId = const CutId('c'),
    FramePage page = page,
    Map<String, int> revisions = const {},
  }) => framePictureKeyOf(
    nodes,
    cutId: cutId,
    page: page,
    revisionOf: (cel) => revisions[cel.layerId.value] ?? 1,
  );

  test('the same stack on the same page is one key', () {
    expect(keyOf(stack()), keyOf(stack()));
    expect(keyOf(stack()).hashCode, keyOf(stack()).hashCode);
  });

  test('🚨every input the picture is drawn from parts the key', () {
    final base = keyOf(stack());
    final parted = {
      'a cel drawn on since': keyOf(stack(), revisions: {'inside': 2}),
      'a row\'s opacity': keyOf(stack(opacity: 0.4)),
      'a row\'s blend': keyOf(stack(blendMode: LayerBlendMode.add)),
      'a row\'s pose': keyOf(
        stack(placement: const LayerPlacement(1, 0, 0, 1, 3, 2)),
      ),
      'a row\'s effects': keyOf(
        stack(
          effects: [
            ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 1]),
          ],
        ),
      ),
      'a folder\'s opacity': keyOf(stack(folderOpacity: 0.7)),
      'the rows\' order': keyOf(stack(overTurned: true)),
      'another cut\'s cels': keyOf(stack(), cutId: const CutId('copy')),
      'the page\'s size': keyOf(
        stack(),
        page: (
          canvasSize: const CanvasSize(width: 32, height: 16),
          pasteboardReach: page.pasteboardReach,
          paintPaper: page.paintPaper,
          paperBackground: page.paperBackground,
        ),
      ),
      'how far its pasteboard reaches': keyOf(
        stack(),
        page: (
          canvasSize: page.canvasSize,
          pasteboardReach: PasteboardReach.none,
          paintPaper: page.paintPaper,
          paperBackground: page.paperBackground,
        ),
      ),
      'whether it paints paper': keyOf(
        stack(),
        page: (
          canvasSize: page.canvasSize,
          pasteboardReach: page.pasteboardReach,
          paintPaper: false,
          paperBackground: page.paperBackground,
        ),
      ),
      'which paper': keyOf(
        stack(),
        page: (
          canvasSize: page.canvasSize,
          pasteboardReach: page.pasteboardReach,
          paintPaper: page.paintPaper,
          paperBackground: const ProjectBackground.color(0xFF30A060),
        ),
      ),
    };
    expect(
      [
        for (final MapEntry(:key, :value) in parted.entries)
          if (value == base) key,
      ],
      isEmpty,
      reason: 'each of these draws another picture',
    );
  });

  test('the row a pen stands on is keyed as the cel it shows', () {
    List<CompositeNode<CanvasStackRow>> withTheRow(CanvasStackRow row) => [
      CompositeLeaf(
        CanvasLayerImageRequest(frameKey: cel('below'), opacity: 1.0),
      ),
      CompositeLeaf(row),
    ];
    const placement = LayerPlacement(1, 0, 0, 1, 3, 2);
    final effects = [
      ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 1]),
    ];
    expect(
      keyOf(
        withTheRow(
          CanvasActiveLayerRow(
            frameKey: cel('pen'),
            opacity: 0.6,
            blendMode: LayerBlendMode.add,
            placement: placement,
            effects: effects,
          ),
        ),
      ),
      keyOf(
        withTheRow(
          CanvasLayerImageRequest(
            frameKey: cel('pen'),
            opacity: 0.6,
            blendMode: LayerBlendMode.add,
            placement: placement,
            effects: effects,
          ),
        ),
      ),
    );
  });

  test('a pen standing on nothing exposed keys nothing, nor the folder it '
      'leaves empty', () {
    final below = CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: cel('below'), opacity: 1.0),
    );
    expect(
      keyOf([
        below,
        const CompositeGroup(
          children: [CompositeLeaf(CanvasActiveLayerRow(opacity: 1.0))],
          opacity: 0.5,
          blendMode: LayerBlendMode.normal,
          effects: [],
        ),
      ]),
      keyOf([below]),
    );
  });

  test('⛔an onion ghost is no part of a frame\'s picture — keyed or drawn',
      () {
    final ghosted = [
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(
          frameKey: cel('ghost'),
          opacity: 0.3,
          tint: 0xFFFF0000,
        ),
      ),
    ];
    expect(() => keyOf(ghosted), throwsStateError);
    expect(
      () => stackedFrameDrawingOf(
        ghosted,
        page: page,
        surfaceOf: (_) => fail('a ghost has no surface to ask for'),
      ),
      throwsStateError,
    );
  });

  group('a session\'s stacks', () {
    (EditorSessionManager, LayerId) sessionStandingOnAMultiplyRow() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final target = s.activeLayer!.id;
      s.layerSwitches.setLayerBlendMode(target, LayerBlendMode.multiply);
      s.layerStack.addLayer();
      s.createDrawingAtCurrentFrame();
      s.selectLayer(target);
      return (s, target);
    }

    List<CanvasActiveLayerRow> penRowsIn(
      List<CompositeNode<CanvasStackRow>> nodes,
    ) => [
      for (final node in preorderNodes(nodes))
        if (node case CompositeLeaf(payload: final CanvasActiveLayerRow row))
          row,
    ];

    FramePictureKey keyIn(
      EditorSessionManager s,
      List<CompositeNode<CanvasStackRow>> nodes,
    ) => framePictureKeyOf(
      nodes,
      cutId: s.activeCutOrNull!.id,
      page: page,
      revisionOf: (cel) =>
          s.renderCaches.brushFrameStore.frameOrNull(cel)?.sourceRevision ??
          0,
    );

    test('★the canvas standing on a frame and a run playing it ask one '
        'picture', () {
      final (s, _) = sessionStandingOnAMultiplyRow();
      final standing = s.editingCanvas.stack.nodes;
      final playing = s.editingCanvas.playingStack.nodes;
      expect(
        [for (final row in penRowsIn(standing)) row.frameKey != null],
        [true],
        reason: '⛔premise: a pen stands on a cel of the frame',
      );
      expect(
        penRowsIn(playing),
        isEmpty,
        reason: '⛔premise: a run draws on nothing',
      );
      expect(keyIn(s, standing), keyIn(s, playing));
    });

    test('🚨what the screen stacks round the cut parts the key, where the '
        'plan\'s signature cannot see it', () {
      final (s, target) = sessionStandingOnAMultiplyRow();
      final cut = s.activeCutOrNull!;
      CutFrameCompositeSignature planned() =>
          computeCutFrameCompositeSignature(
            cut: s.activeCutOrNull!,
            frameIndex: 0,
            revisionOf: (_, _) => 1,
          );
      final before = (
        key: keyIn(s, s.editingCanvas.stack.nodes),
        plan: planned(),
      );

      // An opacity drag in flight: the canvas follows it, and nothing is
      // written until the release.
      s.opacityVerbs.previewLayerOpacity(target, 0.3);

      expect(s.activeCutOrNull, same(cut), reason: '⛔premise: no write');
      expect(planned(), before.plan, reason: '⛔premise: the plan sees none');
      expect(keyIn(s, s.editingCanvas.stack.nodes), isNot(before.key));
    });
  });
}
