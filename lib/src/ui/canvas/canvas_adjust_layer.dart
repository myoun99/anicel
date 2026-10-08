import 'package:flutter/material.dart';

import '../../core/point_bounds.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_pose.dart';
import '../session/canvas_adjust.dart';
import 'canvas_target_pill.dart';
import 'canvas_viewport_offset.dart';
import 'row_transform_box.dart';

/// A canvas being resized ON the canvas (I-79): its edges in the box every
/// box on the canvas wears ([RowTransformBox], each handle moving its own
/// edges — [RowBoxEdges]), and under it the canvas's pill with the size the
/// edges make, 확정 and 취소 ([CanvasTargetPill]).
///
/// 🗣️I-79-Q1 (유저 2026-10-08): the pill stands at the bottom middle of
/// what it adjusts — the canvas here, as it stands under the transform box.
/// I-79-Q2: no anchor is shown; the edge across from the one dragged stays.
///
/// Its ✓ lands the edges through [onLand] — the one landing Enter and the
/// rail's ↵ reach through 확정 too (`landCanvasAdjust`).
///
/// ↩️The layer once bound its [onLand] into the adjust for 확정 to find,
/// and rebound it whenever its parent rebuilt it with a new closure: the
/// rebinding told the adjust's listeners, the parent among them, which
/// rebuilt it again — the app froze the moment the adjust opened
/// (2026-10-08, caught by `a_canvas_adjust_runs_through_the_app_test`).
/// Nothing on the canvas is bound now; the home page hands 확정 the landing.
class CanvasAdjustLayer extends StatelessWidget {
  const CanvasAdjustLayer({
    super.key,
    required this.adjust,
    required this.viewport,
    required this.canvasSize,
    required this.onLand,
  });

  final CanvasAdjust adjust;
  final CanvasViewport viewport;

  /// The canvas as it stands — what the box measures its stage against.
  final CanvasSize canvasSize;

  /// Lands the edges: the canvas resized behind the app's wait window.
  final VoidCallback onLand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adjust,
    builder: (context, _) {
      final shown = adjust.shown;
      if (shown is! CanvasEdgesDraft) {
        return const SizedBox.shrink();
      }
      final edges = shown.edges;
      CanvasEdgesDraft to(Rect edges) =>
          CanvasEdgesDraft(cut: shown.cut, edges: edges);
      final corners = [
        CanvasPoint(x: edges.left, y: edges.top),
        CanvasPoint(x: edges.right, y: edges.top),
        CanvasPoint(x: edges.right, y: edges.bottom),
        CanvasPoint(x: edges.left, y: edges.bottom),
      ];
      return Stack(
        children: [
          Positioned.fill(
            child: RowTransformBox(
              corners: corners,
              pose: TransformPose(
                center: CanvasPoint(
                  x: edges.center.dx,
                  y: edges.center.dy,
                ),
              ),
              canvasSize: canvasSize,
              viewport: viewport,
              // The canvas stays the tools' and the view's: a press is the
              // box's on its handles alone.
              claimsCanvas: false,
              onCancelled: adjust.dropShowing,
              scale: RowBoxEdges((
                changed: (edges) => adjust.show(to(edges)),
                committed: (edges) => adjust.move(to(edges)),
              )),
            ),
          ),
          Positioned.fill(
            child: CanvasTargetPill(
              keyValue: 'canvas-adjust-pill',
              target: pointsBounds([
                for (final corner in corners)
                  viewport.canvasToViewportOffset(corner),
              ]),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${edges.width.round()} × ${edges.height.round()}',
                    key: const ValueKey<String>('canvas-adjust-size'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                ...targetPillVerbs(
                  'canvas-adjust',
                  onConfirm: onLand,
                  onCancel: adjust.end,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
