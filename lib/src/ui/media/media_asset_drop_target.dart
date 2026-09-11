import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppColors;
import 'media_asset_drag_data.dart';

/// A full-bleed place ENTRANCE: the surface a media-browser row can be
/// dropped on, wherever that surface is (a timeline layer row, the stage,
/// the layer area).
///
/// It reports and stops there. Every entrance the place system has fills
/// the import window's answers rather than deciding for the user (§7), so
/// what a drop does with [onDrop] is the host's business — this only says
/// that one arrived, carrying which file, at which point on the screen.
///
/// 🚨[globalPosition] is [DragTargetDetails.offset], and that is the
/// pointer MINUS the drag source's anchor. It equals the pointer only
/// because the pool row anchors its chip at the pointer
/// (`pointerDragAnchorStrategy`, said there for this reason) — a drag in
/// flight never reaches this widget as pointer events, because a down
/// pointer's later events go to the hit-test path recorded at pointer-DOWN,
/// which is the row the drag started from. Hosts that read a coordinate out
/// of it (the timeline names a frame, the layer area a gap) depend on that
/// anchor.
class MediaAssetDropTarget extends StatelessWidget {
  const MediaAssetDropTarget({
    super.key,
    required this.onDrop,
    this.onHover,
    this.onLeave,
    this.framed = true,
  });

  final void Function(MediaAssetDragData data, Offset globalPosition) onDrop;

  /// Where a matching drag stands while it is over this entrance — the same
  /// offset [onDrop] gets, with the same anchor caveat — for a host whose
  /// answer is drawn at the pointer (the rail's caret).
  final void Function(MediaAssetDragData data, Offset globalPosition)?
  onHover;

  /// The drag left without being let go.
  final VoidCallback? onLeave;

  /// Whether the entrance lights its own border while a drag is over it.
  /// The layer area answers with the rail's caret instead, so it asks for
  /// none.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final hover = onHover;
    final leave = onLeave;
    return DragTarget<MediaAssetDragData>(
      onMove: hover == null
          ? null
          : (details) => hover(details.data, details.offset),
      onLeave: leave == null ? null : (_) => leave(),
      onAcceptWithDetails: (details) => onDrop(details.data, details.offset),
      // Lit only while a matching drag is in flight, and an empty SizedBox
      // absorbs no hit test — so the surface underneath (a brush stroke, a
      // cell tap, a range pan, a rail row's grip) keeps every pointer the
      // rest of the time.
      builder: (context, candidates, _) => candidates.isEmpty || !framed
          ? const SizedBox.expand()
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2),
              ),
            ),
    );
  }
}
