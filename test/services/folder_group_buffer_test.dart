import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

/// R27 #29 — the FOLDER GROUP BUFFER, 유저 확정: "폴더는 정식 합성
/// 레이어로해서 합성 버퍼 같이가자. 그룹 한번합쳐서 한번블렌드."
///
/// The contract has two halves and both matter:
/// - a folder that needs a buffer gets ONE, and its opacity/blend land on
///   that buffer instead of on each member;
/// - a folder that does NOT need one costs nothing at all — no node, no
///   saveLayer — which is what makes 통과 the safe default.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  Layer member(String id, {String? folder}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 1)},
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer folderRow(
    String id, {
    String? parent,
    LayerBlendMode blend = LayerBlendMode.passThrough,
    double opacity = 1,
    TransformTrack? transformTrack,
    bool isVisible = true,
  }) => createFolderLayer(
    id: LayerId(id),
    name: id.toUpperCase(),
    parentId: parent == null ? null : LayerId(parent),
  ).copyWith(
    blendMode: blend,
    opacity: opacity,
    transformTrack: transformTrack,
    isVisible: isVisible,
  );

  List<CutFrameCompositeEntryNode> treeOf(List<Layer> layers) =>
      resolveCutFrameCompositeTree(cut: cut(layers), frameIndex: 0);

  group('a folder buffers only when it must', () {
    test('PASS THROUGH + opaque: no group node, members sit at top level', () {
      final tree = treeOf([member('a', folder: 'f'), folderRow('f')]);
      expect(tree, hasLength(1));
      expect(
        tree.single,
        isA<CutFrameCompositeEntryLeaf>(),
        reason: 'an organizing folder must cost no buffer — the 통과 default',
      );
    });

    test('a real BLEND isolates the group', () {
      final tree = treeOf([
        member('a', folder: 'f'),
        folderRow('f', blend: LayerBlendMode.multiply),
      ]);
      final group = tree.single as CutFrameCompositeEntryGroup;
      expect(group.blendMode, LayerBlendMode.multiply);
      expect(group.opacity, 1);
      expect(group.children, hasLength(1));
    });

    test('opacity below 1 isolates even while PASS THROUGH — 0.5·(A over B) '
        'is not (0.5·A) over (0.5·B)', () {
      final tree = treeOf([
        member('a', folder: 'f'),
        folderRow('f', opacity: 0.5),
      ]);
      final group = tree.single as CutFrameCompositeEntryGroup;
      expect(group.opacity, closeTo(0.5, 1e-9));
      expect(
        group.blendMode,
        LayerBlendMode.normal,
        reason: 'it buffered for the opacity alone; the buffer blends plainly',
      );
    });

    test('a POSE does NOT isolate — an affine transform distributes over '
        'compositing, so folder FX stays free', () {
      final tree = treeOf([
        member('a', folder: 'f'),
        folderRow(
          'f',
          transformTrack: TransformTrack(
            keyframes: {
              0: TransformPose(center: CanvasPoint(x: 3, y: 2), zoom: 2),
            },
          ),
        ),
      ]);
      final leaf = tree.single as CutFrameCompositeEntryLeaf;
      expect(
        leaf.entry.pose?.zoom,
        2,
        reason: 'the folder pose still reaches the member, without a buffer',
      );
    });
  });

  group('a buffering folder owns its opacity and blend', () {
    test('the MEMBER no longer carries them — that double-application was '
        'the darkening bug', () {
      final tree = treeOf([
        member('a', folder: 'f'),
        folderRow('f', blend: LayerBlendMode.multiply, opacity: 0.5),
      ]);
      final group = tree.single as CutFrameCompositeEntryGroup;
      final leaf = group.children.single as CutFrameCompositeEntryLeaf;

      expect(group.opacity, closeTo(0.5, 1e-9));
      expect(group.blendMode, LayerBlendMode.multiply);
      expect(
        leaf.entry.opacity,
        1,
        reason: 'the folder opacity belongs to the buffer, not the member',
      );
      expect(
        leaf.entry.blendMode,
        LayerBlendMode.normal,
        reason: 'inside the buffer a member keeps its OWN blend',
      );
    });

    test('the flat path still folds — the readers that cannot nest keep '
        'today\'s approximation', () {
      final entries = resolveCutFrameCompositeEntries(
        cut: cut([
          member('a', folder: 'f'),
          folderRow('f', blend: LayerBlendMode.multiply, opacity: 0.5),
        ]),
        frameIndex: 0,
      );
      expect(entries.single.opacity, closeTo(0.5, 1e-9));
      expect(entries.single.blendMode, LayerBlendMode.multiply);
    });
  });

  group('nesting and gates', () {
    test('a PASS-THROUGH folder inside a buffering one adds no level', () {
      final tree = treeOf([
        member('a', folder: 'inner'),
        folderRow('inner', parent: 'outer'),
        folderRow('outer', blend: LayerBlendMode.screen),
      ]);
      final group = tree.single as CutFrameCompositeEntryGroup;
      expect(group.blendMode, LayerBlendMode.screen);
      expect(
        group.children.single,
        isA<CutFrameCompositeEntryLeaf>(),
        reason: 'the inner 통과 folder left no node',
      );
    });

    test('buffering folders nest', () {
      final tree = treeOf([
        member('a', folder: 'inner'),
        folderRow('inner', parent: 'outer', blend: LayerBlendMode.multiply),
        folderRow('outer', blend: LayerBlendMode.screen),
      ]);
      final outer = tree.single as CutFrameCompositeEntryGroup;
      final inner = outer.children.single as CutFrameCompositeEntryGroup;
      expect(outer.blendMode, LayerBlendMode.screen);
      expect(inner.blendMode, LayerBlendMode.multiply);
    });

    test('a hidden folder drops its subtree; an empty one leaves no node', () {
      expect(
        treeOf([member('a', folder: 'f'), folderRow('f', isVisible: false)]),
        isEmpty,
      );
      expect(
        treeOf([folderRow('f', blend: LayerBlendMode.multiply)]),
        isEmpty,
        reason: 'an empty buffer is a wasted saveLayer',
      );
    });

    test('the fx switch on the FOLDER kills its animated opacity, so a '
        'folder buffering only for that stops buffering', () {
      final layers = [
        member('a', folder: 'f'),
        folderRow(
          'f',
          transformTrack: TransformTrack.empty().copyWith(
            opacity: PropertyTrack<double>.empty().withKey(0, 0.25),
          ),
        ),
      ];
      expect(
        treeOf(layers).single,
        isA<CutFrameCompositeEntryGroup>(),
        reason: 'the animated opacity lane pulls it below 1',
      );
      expect(
        treeOf([
          for (final layer in layers)
            layer.kind == LayerKind.folder
                ? layer.copyWith(transformEnabled: false)
                : layer,
        ]).single,
        isA<CutFrameCompositeEntryLeaf>(),
        reason: 'the folder\'s transform switch off means opacity 1 again — '
            'no buffer needed',
      );
    });
  });
}
