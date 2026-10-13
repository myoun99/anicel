import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

import '../../helpers/placement_reading.dart';

/// 🚨★★★ONE LAW FOR HOW BIG A SUB-TREE'S BUFFER IS (card
/// export-folders-and-rows-at-their-extent): what of it lies within what
/// reads the buffer — the rect each row stands for, under its own
/// placement, a folder's the union of its children's. The editing stack and
/// the camera both ask it (`every_route_composites_a_group_the_same_way`).
void main() {
  const canvas = CanvasSize(width: 100, height: 100);
  const everywhere = Rect.fromLTRB(-1000, -1000, 1000, 1000);

  CompositeNode<_Row> row(Rect extent, {LayerPlacement? placement}) =>
      CompositeLeaf((extent: extent, placement: placement));

  CompositeNode<_Row> folder(List<CompositeNode<_Row>> children) =>
      CompositeGroup(
        children: children,
        opacity: 1,
        blendMode: LayerBlendMode.normal,
      );

  Rect boundsOf(CompositeNode<_Row> node, {Rect within = everywhere}) =>
      subtreeBufferBounds(
        node,
        within: within,
        extentOf: (row) => row.extent,
        placementOf: (row) => row.placement,
      );

  test('a row: the rect it stands for, within what reads it', () {
    expect(
      boundsOf(
        row(const Rect.fromLTRB(0, 0, 100, 100)),
        within: const Rect.fromLTRB(10, 20, 50, 60),
      ),
      const Rect.fromLTRB(10, 20, 50, 60),
    );
  });

  test('a placed row: that rect where its placement puts it', () {
    final moved = placedBy(
      TransformPose(center: CanvasPoint(x: 60, y: 50)),
      canvas,
    );

    expect(
      boundsOf(row(const Rect.fromLTRB(0, 0, 100, 100), placement: moved)),
      const Rect.fromLTRB(10, 0, 110, 100),
    );
  });

  test('a folder: the union of its children at every depth, an empty one '
      'adding nothing', () {
    expect(
      boundsOf(
        folder([
          row(const Rect.fromLTRB(20, 20, 30, 30)),
          row(const Rect.fromLTWH(300, 300, 0, 0)),
          folder([row(const Rect.fromLTRB(60, 60, 70, 80))]),
        ]),
      ),
      const Rect.fromLTRB(20, 20, 70, 80),
    );
  });

  test('an adjustment: the union of its scope', () {
    expect(
      boundsOf(
        CompositeAdjustment(
          children: [
            row(const Rect.fromLTRB(20, 20, 30, 30)),
            row(const Rect.fromLTRB(60, 60, 70, 80)),
          ],
          effects: const [],
          mix: 1,
        ),
        within: const Rect.fromLTRB(50, 0, 100, 100),
      ),
      const Rect.fromLTRB(50, 20, 70, 80),
    );
  });
}

typedef _Row = ({Rect extent, LayerPlacement? placement});
