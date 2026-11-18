import 'package:flutter/widgets.dart' show MatrixUtils, Rect;

import '../../models/composite_tree.dart';
import '../../services/layer_pose_matrix.dart'
    show LayerPlacement, placementMatrix;
import '../text/cel_number_paint.dart' show celNumberExtent;

/// The CANVAS-SPACE rect a buffer for [node] covers: what of it lies
/// [within] what reads the buffer — the rect each of its rows stands for
/// ([extentOf]) under the row's own placement ([placementOf]), a folder's
/// or an adjustment's the union of its children's.
///
/// [within] is the view at the top, and under a folder that folder's own
/// buffer: a blur on the folder reads its buffer past the view, so what
/// lies inside it has to be there too. 🔬A blurred folder holding a
/// buffered one, cut to the view at every depth, put the frame's edge 56
/// levels off (2026-10-13, measured against the camera's old bound).
///
/// 🚨★★★ONE LAW FOR EVERY WALK (card export-folders-and-rows-at-their-extent,
/// 2026-10-13). ↩️The camera bounded a folder by the square that covers its
/// frame at any turn — 2.1× a 2340×1654 canvas, 8.2 Mpx a folder, a
/// convenience of R6a (07-30), nobody's decision — where the editing stack
/// bounded the same folder by what of it is in view. 🔬On the user's film,
/// with a kit that bounded it by the frame alone: a folder cut's picture
/// 129 → 79 ms of GPU, the run 151 → 124 s, the video's bytes the same.
///
/// [extentOf] is the rect a row STANDS FOR, not the part of it that holds
/// the ink: a folder's buffer — and so where its blur is worked out —
/// reaches as far as it did when every image was whole.
///
/// ⛔RECOMPUTED, NEVER ACCUMULATED. A rect that only ever grew would be the
/// high-water mark of everything you had done — the "sticky / containment
/// 매칭 버퍼 rect" the composite plan rejects by name.
Rect subtreeBufferBounds<T>(
  CompositeNode<T> node, {
  required Rect within,
  required Rect Function(T row) extentOf,
  required LayerPlacement? Function(T row) placementOf,
}) => within.intersect(_subtreeExtent(node, extentOf, placementOf));

Rect _subtreeExtent<T>(
  CompositeNode<T> node,
  Rect Function(T row) extentOf,
  LayerPlacement? Function(T row) placementOf,
) {
  switch (node) {
    case CompositeLeaf(:final payload):
      return _placed(extentOf(payload), placementOf(payload));
    // The letters where they stand on their row's paper, laid as it lies.
    case CompositeCelNumber(:final on, :final letters):
      return _placed(celNumberExtent(letters), placementOf(on.payload));
    // What clips is cut to the base: the base's rect is all of it.
    case CompositeClip(base: final of):
    case CompositeOpaque(:final of):
    // What it reads of a row is read, not drawn: its own rect is all.
    case CompositeReadsRows(node: final of):
      return _subtreeExtent(of, extentOf, placementOf);
    case CompositeGroup(:final children):
    case CompositeAdjustment(:final children):
    case CompositeBackdropBlend(:final children):
      var union = Rect.zero;
      for (final child in children) {
        final rect = _subtreeExtent(child, extentOf, placementOf);
        if (rect.isEmpty) {
          continue;
        }
        union = union.isEmpty ? rect : union.expandToInclude(rect);
      }
      return union;
  }
}

/// [extent] on a row's paper as the canvas holds it, the row lying at
/// [placement].
Rect _placed(Rect extent, LayerPlacement? placement) => placement == null
    ? extent
    : MatrixUtils.transformRect(placementMatrix(placement), extent);
