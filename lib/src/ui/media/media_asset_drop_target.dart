import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppColors;
import 'media_asset_drag_data.dart';
import 'media_drop_verdict.dart';

/// A full-bleed place ENTRANCE: the surface a media-browser row can be
/// dropped on, wherever that surface is (a timeline layer row, the stage,
/// the layer area, an SE block).
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
    this.accepts,
    this.onHover,
    this.onLeave,
    this.framed = true,
  });

  final void Function(MediaAssetDragData data, Offset globalPosition) onDrop;

  /// Whether the file standing at [globalPosition] can land here — the
  /// answer the drag's chip wears ([MediaDropVerdictScope]: 「불가능 = 칩의
  /// 금지 표시」). Null is yes, for every file. An entrance that says no
  /// does nothing with the drop: impossible means nothing happens.
  final bool Function(MediaAssetDragData data, Offset globalPosition)?
  accepts;

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

  bool _yes(MediaAssetDragData data, Offset globalPosition) =>
      accepts?.call(data, globalPosition) ?? true;

  @override
  Widget build(BuildContext context) {
    final verdict = MediaDropVerdictScope.maybeOf(context);
    return DragTarget<MediaAssetDragData>(
      onMove: (details) {
        verdict?.value = _yes(details.data, details.offset);
        onHover?.call(details.data, details.offset);
      },
      onLeave: (_) {
        verdict?.value = null;
        onLeave?.call();
      },
      onAcceptWithDetails: (details) {
        verdict?.value = null;
        if (_yes(details.data, details.offset)) {
          onDrop(details.data, details.offset);
        }
      },
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
